// `annotate run`: fully unattended delivery. Each new session becomes one `claude -p` run in the
// project directory; runs are serialized and resume the previous run's conversation, so follow-up
// annotations ("bigger still") keep context. Status goes working → done (with the run's last line
// as the summary) or failed, which the app shows live.

#if os(macOS) || os(Linux)
import AnnotateCore
import Foundation

public struct HeadlessRunner: Sendable {
    public struct Result: Sendable, Equatable {
        public var exitCode: Int32
        public var text: String?
        public var sessionID: String?
        public var isError: Bool
        public var stderr: String
    }

    public var workingDirectory: URL
    public var permissionMode: String
    public var extraArguments: [String]
    public var executable: String

    public init(workingDirectory: URL, permissionMode: String = "acceptEdits", extraArguments: [String] = [], executable: String = "claude") {
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.extraArguments = extraArguments
        self.executable = executable
    }

    public func arguments(prompt: String, resume: String?) -> [String] {
        var arguments = [executable, "-p", prompt, "--permission-mode", permissionMode, "--output-format", "json"]
        if let resume { arguments += ["--resume", resume] }
        return arguments + extraArguments
    }

    /// Runs one session synchronously.
    public func run(prompt: String, resume: String?) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments(prompt: prompt, resume: resume)
        process.currentDirectoryURL = workingDirectory

        let stdout = Pipe()
        // stderr to a file: two pipes read one after the other can deadlock on a full buffer
        let stderrURL = FileManager.default.temporaryDirectory.appendingPathComponent("annotate-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stderrURL)
        }
        process.standardOutput = stdout
        process.standardError = stderrHandle
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        let parsed = Self.parse(output: output)
        return Result(
            exitCode: process.terminationStatus,
            text: parsed.text,
            sessionID: parsed.sessionID,
            isError: parsed.isError || process.terminationStatus != 0,
            stderr: stderr
        )
    }

    /// Reads `--output-format json`: `{"result": "...", "session_id": "...", "is_error": false}`.
    public static func parse(output: Data) -> (text: String?, sessionID: String?, isError: Bool) {
        guard let object = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any] else {
            let raw = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw.isEmpty ? nil : raw, nil, false)
        }
        return (object["result"] as? String, object["session_id"] as? String, object["is_error"] as? Bool ?? false)
    }

    /// The run's last non-empty line, minus a "Summary:" label, cut to fit a toast.
    public static func summary(from text: String?, limit: Int = 140) -> String? {
        guard let text else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard var last = lines.last else { return nil }
        for label in ["**Summary:**", "Summary:", "summary:"] where last.hasPrefix(label) {
            last = String(last.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        last = last.trimmingCharacters(in: CharacterSet(charactersIn: "*_` "))
        guard last.count > limit else { return last }
        return String(last.prefix(limit - 1)) + "…"
    }

    /// Watches `feed` forever, running sessions one at a time.
    public func serve(feed: SessionFeed, resumeConversations: Bool, log: @Sendable (String) -> Void) async {
        var conversation: String?
        while !Task.isCancelled {
            for sessionID in feed.claimPending(as: .delivered) {
                let output = feed.outputDirectory
                guard let prompt = try? SessionInbox.loadPrompt(id: sessionID, in: output) else { continue }
                try? SessionInbox.writeStatus(SessionStatus(state: .working, message: "Claude is working…"), id: sessionID, in: output)
                log("→ \(sessionID): running claude -p")
                do {
                    let result = try run(prompt: prompt, resume: resumeConversations ? conversation : nil)
                    if result.isError {
                        let reason = Self.summary(from: result.stderr.isEmpty ? result.text : result.stderr) ?? "claude exited with \(result.exitCode)"
                        try? SessionInbox.writeStatus(SessionStatus(state: .failed, message: reason), id: sessionID, in: output)
                        log("✗ \(sessionID): \(reason)")
                    } else {
                        let summary = Self.summary(from: result.text)
                        try? SessionInbox.writeStatus(SessionStatus(state: .done, message: summary), id: sessionID, in: output)
                        conversation = result.sessionID ?? conversation
                        log("✓ \(sessionID): \(summary ?? "done")")
                    }
                } catch {
                    let reason = "Couldn't start claude: \(error.localizedDescription)"
                    try? SessionInbox.writeStatus(SessionStatus(state: .failed, message: reason), id: sessionID, in: output)
                    log("✗ \(sessionID): \(reason)")
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}
#endif

// Argument parsing and dispatch for the `annotate` executable (kept here, not in the executable
// target, so it's unit-testable). Commands:
//   annotate mcp                     channel MCP server for Claude Code (stdio)
//   annotate watch [--once]          one line per new session and per user reply on stdout, for a Monitor /
//                                    background watcher
//   annotate run [--fresh] [--permission-mode M] [-- <claude args>]   headless claude -p per session
//   annotate status <id|latest> <working|done|failed> [message…]
//   annotate resolve <id|latest> <pin> [summary…]     per-pin result, shown on the device
//   annotate dismiss <id|latest> <pin> [reason…]
//   annotate ask <id|latest> <pin> <question…> [--wait <seconds>]   blocks for the user's reply
//                                    (stdout, exit 0) or times out (exit 3)
//   annotate list
// resolve / dismiss / ask are the CLI counterparts of the MCP per-pin tools, so an agent driven by
// `annotate watch` (no MCP) can report pins and ask questions too.
// Every command takes --dir <path>; default is .annotate at the project root above the cwd.
// mcp, watch and run also keep a heartbeat (the app's connection dot) and copy Sends from paired
// devices (`DeviceMirror`); --no-device turns the device part off.

import AnnotateCore
import Foundation

public enum Command: Equatable, Sendable {
    case mcp
    case watch(once: Bool)
    case run(fresh: Bool, permissionMode: String, claudeArguments: [String])
    case status(sessionID: String, state: SessionStatus.State, message: String?)
    case resolve(sessionID: String, pin: Int, summary: String?)
    case dismiss(sessionID: String, pin: Int, reason: String?)
    case ask(sessionID: String, pin: Int, question: String, wait: Double)
    case list
    case help

    public struct Invocation: Equatable, Sendable {
        public var command: Command
        public var directory: String?
        /// Copy Sends from paired devices (on by default; `--no-device` turns it off).
        public var devices: Bool = true
    }

    public static let usage = """
        annotate — deliver AnnotateKit sessions from the Simulator or a device to your coding agent

        USAGE
          annotate mcp                 MCP server: pushes each Send into your open Claude Code session
                                       (channels) and serves the session tools
          annotate watch [--once]      print one line per new session and per reply from the user
                                       (for a Monitor or background watcher)
          annotate run [--fresh] [--permission-mode acceptEdits] [-- <extra claude args>]
                                       run `claude -p` for every new session, unattended
          annotate status <id|latest> <working|done|failed> [message]
                                       report progress back to the app
          annotate resolve <id|latest> <pin> [summary]
                                       mark one pin done, with what changed
          annotate dismiss <id|latest> <pin> [reason]
                                       mark one pin as not done, with why
          annotate ask <id|latest> <pin> <question> [--wait <seconds>]
                                       ask the user about one pin and wait for the reply (default 120s);
                                       prints it and exits 0, or exits 3 when none arrives in time
          annotate list                recent sessions and their status

        OPTIONS
          --dir <path>                 sessions folder (default: <project root>/.annotate)
          --no-device                  don't copy Sends from paired iPhones and iPads (mcp, watch, run)
        """

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case unknown(String)
        case invalidState(String)
        case missingArguments(String)
        case invalidPin(String)

        public var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) needs a value"
            case .unknown(let token): "unknown argument \(token)"
            case .invalidState(let state): "state must be working, done or failed (got \(state))"
            case .missingArguments(let usage): "usage: \(usage)"
            case .invalidPin(let pin): "pin must be a positive note number (got \(pin))"
            }
        }
    }

    public static func parse(_ arguments: [String]) throws -> Invocation {
        var tokens = arguments
        var directory: String?
        var passthrough: [String] = []
        if let separator = tokens.firstIndex(of: "--") {
            passthrough = Array(tokens[(separator + 1)...])
            tokens = Array(tokens[..<separator])
        }
        if let flag = tokens.firstIndex(of: "--dir") {
            guard flag + 1 < tokens.count else { throw ParseError.missingValue("--dir") }
            directory = tokens[flag + 1]
            tokens.removeSubrange(flag...(flag + 1))
        }
        let devices = !tokens.contains("--no-device")
        tokens.removeAll { $0 == "--no-device" }
        var invocation = try parseCommand(tokens, directory: directory, passthrough: passthrough)
        invocation.devices = devices
        return invocation
    }

    private static func parseCommand(_ tokens: [String], directory: String?, passthrough: [String]) throws -> Invocation {
        guard let name = tokens.first else { return Invocation(command: .help, directory: directory) }
        let rest = Array(tokens.dropFirst())

        switch name {
        case "mcp":
            try expectEmpty(rest)
            return Invocation(command: .mcp, directory: directory)
        case "watch":
            try expectEmpty(rest.filter { $0 != "--once" })
            return Invocation(command: .watch(once: rest.contains("--once")), directory: directory)
        case "run":
            var mode = "acceptEdits"
            var remaining = rest
            if let flag = remaining.firstIndex(of: "--permission-mode") {
                guard flag + 1 < remaining.count else { throw ParseError.missingValue("--permission-mode") }
                mode = remaining[flag + 1]
                remaining.removeSubrange(flag...(flag + 1))
            }
            let fresh = remaining.contains("--fresh")
            try expectEmpty(remaining.filter { $0 != "--fresh" })
            return Invocation(command: .run(fresh: fresh, permissionMode: mode, claudeArguments: passthrough), directory: directory)
        case "status":
            guard rest.count >= 2 else { throw ParseError.missingArguments("annotate status <id|latest> <working|done|failed> [message]") }
            guard let state = SessionStatus.State(rawValue: rest[1]), SessionStatus.State.reportable.contains(state) else {
                throw ParseError.invalidState(rest[1])
            }
            let message = rest.count > 2 ? rest[2...].joined(separator: " ") : nil
            return Invocation(command: .status(sessionID: rest[0], state: state, message: message), directory: directory)
        case "resolve", "dismiss":
            guard rest.count >= 2 else { throw ParseError.missingArguments("annotate \(name) <id|latest> <pin> [\(name == "resolve" ? "summary" : "reason")]") }
            let pin = try parsePin(rest[1])
            let note = rest.count > 2 ? rest[2...].joined(separator: " ") : nil
            let command: Command = name == "resolve"
                ? .resolve(sessionID: rest[0], pin: pin, summary: note)
                : .dismiss(sessionID: rest[0], pin: pin, reason: note)
            return Invocation(command: command, directory: directory)
        case "ask":
            return Invocation(command: try parseAsk(rest), directory: directory)
        case "list":
            try expectEmpty(rest)
            return Invocation(command: .list, directory: directory)
        case "help", "-h", "--help":
            return Invocation(command: .help, directory: directory)
        default:
            throw ParseError.unknown(name)
        }
    }

    private static func expectEmpty(_ rest: [String]) throws {
        if let extra = rest.first { throw ParseError.unknown(extra) }
    }

    /// How long `annotate ask` waits for the user's reply when --wait is absent (matches annotation_ask's default).
    static let defaultAskWait: Double = 120

    /// Pins are the 1-based note numbers the user sees on the device, so only positive integers name one.
    private static func parsePin(_ token: String) throws -> Int {
        guard let pin = Int(token), pin > 0 else { throw ParseError.invalidPin(token) }
        return pin
    }

    /// `ask <id|latest> <pin> <question…> [--wait <seconds>]`; --wait may sit anywhere after `ask`.
    private static func parseAsk(_ rest: [String]) throws -> Command {
        var remaining = rest
        var wait = defaultAskWait
        if let flag = remaining.firstIndex(of: "--wait") {
            guard flag + 1 < remaining.count, let seconds = Double(remaining[flag + 1]), seconds >= 0, seconds.isFinite else {
                throw ParseError.missingValue("--wait")
            }
            wait = seconds
            remaining.removeSubrange(flag...(flag + 1))
        }
        guard remaining.count >= 3 else {
            throw ParseError.missingArguments("annotate ask <id|latest> <pin> <question> [--wait <seconds>]")
        }
        let pin = try parsePin(remaining[1])
        let question = remaining[2...].joined(separator: " ")
        return .ask(sessionID: remaining[0], pin: pin, question: question, wait: wait)
    }

    /// Runs a parsed invocation; returns the process exit code.
    public static func execute(_ invocation: Invocation, workingDirectory: String = FileManager.default.currentDirectoryPath) async -> Int32 {
        let output = SessionFeed.outputDirectory(explicit: invocation.directory, workingDirectory: workingDirectory)
        let feed = SessionFeed(outputDirectory: output)

        switch invocation.command {
        case .help:
            writeLine(usage)
            return 0

        case .mcp:
            let devices = invocation.devices
            await ChannelServer.serveStdio(feed: feed) { server in
                let runtime = makeRuntime(output: output, feed: feed, devices: devices) { await server.presence() }
                await runtime.run()
            }
            return 0

        case .watch(let once):
            let agent = currentAgent()
            let runtime = makeRuntime(output: output, feed: feed, devices: invocation.devices) {
                AgentPresence(agent: agent, mode: .push, via: "watch")
            }
            let background = Task { await runtime.run() }
            writeError("annotate: watching \(output.path)")
            watching: while !Task.isCancelled {
                for sessionID in feed.claimPending(as: .delivered) {
                    writeLine(watchLine(sessionID: sessionID, directory: feed.sessionDirectory(sessionID)))
                    if once { break watching }
                }
                // Replies to `annotate ask` / annotation_ask questions that no blocking ask picked up.
                // Consumed before printing so a second watcher (or the MCP server) can't repeat them.
                for pending in feed.pendingReplies() {
                    feed.consume(pending.reply, sessionID: pending.sessionID)
                    writeLine(replyLine(sessionID: pending.sessionID, reply: pending.reply))
                    if once { break watching }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            background.cancel()
            await background.value
            return 0

        case .run(let fresh, let mode, let claudeArguments):
            #if os(macOS) || os(Linux)
            let projectRoot = output.deletingLastPathComponent()
            let runner = HeadlessRunner(workingDirectory: projectRoot, permissionMode: mode, extraArguments: claudeArguments)
            let runtime = makeRuntime(output: output, feed: feed, devices: invocation.devices) {
                AgentPresence(agent: "Claude Code", mode: .push, via: "run")
            }
            let background = Task { await runtime.run() }
            writeError("annotate: running claude -p for new sessions in \(output.path) (permission mode \(mode))")
            await runner.serve(feed: feed, resumeConversations: !fresh) { writeError($0) }
            background.cancel()
            await background.value
            return 0
            #else
            writeError("annotate run isn't supported on this platform")
            return 1
            #endif

        case .status(let requested, let state, let message):
            guard let sessionID = feed.resolve(requested) else {
                writeError("annotate: no sessions in \(output.path)")
                return 1
            }
            do {
                try SessionInbox.writeStatus(SessionStatus(state: state, message: message), id: sessionID, in: output)
                return 0
            } catch {
                writeError("annotate: couldn't write status for \(sessionID): \(error.localizedDescription)")
                return 1
            }

        case .resolve(let requested, let pin, let summary):
            return writePin(PinStatus(index: pin, state: .resolved, note: summary), requested: requested, feed: feed, output: output)

        case .dismiss(let requested, let pin, let reason):
            return writePin(PinStatus(index: pin, state: .dismissed, note: reason), requested: requested, feed: feed, output: output)

        case .ask(let requested, let pin, let question, let wait):
            return await ask(question, pin: pin, requested: requested, wait: wait, feed: feed, output: output)

        case .list:
            let ids = SessionInbox.sessionIDs(in: output).suffix(15).reversed()
            if ids.isEmpty { writeLine("No sessions in \(output.path)") }
            for id in ids {
                let state = SessionInbox.readStatus(id: id, in: output)
                writeLine("\(id)  \(state?.state.rawValue ?? "pending")\(state?.message.map { "  \($0)" } ?? "")")
            }
            return 0
        }
    }

    /// Exit code `annotate ask` returns when no reply arrived in time — distinct from 1 (a real failure)
    /// so a script can tell "ask again later" apart from "something broke".
    static let askTimeoutExitCode: Int32 = 3

    /// How often `annotate ask` re-reads replies.json; the app's write lands within a poll, and the
    /// file is tiny, so 500ms is responsive without busy-looping (same cadence as `watch`).
    static let askPollInterval: Duration = .milliseconds(500)

    /// Upserts one pin's status in the resolved session; returns the exit code.
    private static func writePin(_ status: PinStatus, requested: String, feed: SessionFeed, output: URL) -> Int32 {
        guard let sessionID = feed.resolve(requested) else {
            writeError("annotate: no sessions in \(output.path)")
            return 1
        }
        do {
            try SessionInbox.updatePin(status, id: sessionID, in: output)
            return 0
        } catch {
            writeError("annotate: couldn't update pin \(status.index) of \(sessionID): \(error.localizedDescription)")
            return 1
        }
    }

    /// Marks the pin `.question`, then polls for the user's reply to it until `wait` elapses. The reply
    /// goes to stdout (exit 0); a timeout leaves the question open, so the reply still reaches the agent
    /// later through `annotate watch`.
    private static func ask(
        _ question: String,
        pin: Int,
        requested: String,
        wait: Double,
        feed: SessionFeed,
        output: URL
    ) async -> Int32 {
        guard let sessionID = feed.resolve(requested) else {
            writeError("annotate: no sessions in \(output.path)")
            return 1
        }
        do {
            try SessionInbox.updatePin(PinStatus(index: pin, state: .question, note: question), id: sessionID, in: output)
        } catch {
            writeError("annotate: couldn't ask about pin \(pin) of \(sessionID): \(error.localizedDescription)")
            return 1
        }
        let deadline = Date().addingTimeInterval(wait)
        while !Task.isCancelled {
            if let reply = SessionInbox.unansweredReplies(id: sessionID, in: output).first(where: { $0.index == pin }) {
                do {
                    try SessionInbox.markAnswered(reply, id: sessionID, in: output)
                } catch {
                    // The reply is still printed: the agent has it. Without the mark a watcher may repeat it.
                    writeError("annotate: couldn't mark pin \(pin) of \(sessionID) answered: \(error.localizedDescription)")
                }
                writeLine(reply.text)
                return 0
            }
            if Date() >= deadline { break }
            try? await Task.sleep(for: askPollInterval)
        }
        writeError("annotate: no answer to pin \(pin) of \(sessionID) after \(Int(wait))s; "
            + "it will arrive through `annotate watch`")
        return askTimeoutExitCode
    }

    /// Heartbeat for a long-lived command, plus the device mirror where devicectl exists.
    static func makeRuntime(
        output: URL,
        feed: SessionFeed,
        devices: Bool,
        presence: @escaping AgentRuntime.PresenceProvider
    ) -> AgentRuntime {
        var mirror: DeviceMirror?
        #if os(macOS)
        if devices, let bridge = DeviceCtlBridge.makeIfAvailable() {
            mirror = DeviceMirror(outputDirectory: output, cutoffID: feed.cutoffID, bridge: bridge) { writeError($0) }
        }
        #endif
        return AgentRuntime(outputDirectory: output, mirror: mirror, presence: presence)
    }

    /// The agent whose shell started this process, for the connection dot.
    static func currentAgent() -> String {
        #if os(macOS) || os(Linux)
        AgentIdentity.current() ?? AgentIdentity.fallbackName
        #else
        AgentIdentity.fallbackName
        #endif
    }

    /// The line a watcher prints; written so the agent reading it knows what to do.
    public static func watchLine(sessionID: String, directory: URL) -> String {
        "annotation session \(sessionID) ready: read \(directory.path)/prompt.md and its images, make the changes, "
            + "then run `annotate status \(sessionID) done \"<one-line summary>\"`"
    }

    /// The line a watcher prints for a user's reply to a pin question; tells the agent where to pick up.
    public static func replyLine(sessionID: String, reply: PinReply) -> String {
        "reply on pin \(reply.index) of session \(sessionID): \"\(reply.text)\" — continue that session, "
            + "then `annotate resolve|dismiss \(sessionID) \(reply.index) …`"
    }

    static func writeLine(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func writeError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

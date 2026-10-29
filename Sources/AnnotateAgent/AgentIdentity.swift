// Names the agent an `annotate` process serves, for the app's connection dot. `annotate mcp` knows
// from the MCP client's `clientInfo.name`; `watch` and `run` are started from an agent's shell, so
// they look at its environment (Claude Code sets CLAUDECODE=1) and then at their parent processes.

import Foundation

public enum AgentIdentity {
    public static let fallbackName = "Agent"

    /// Display name for an MCP client: "claude-code" → "Claude Code", "cursor-vscode" → "Cursor"…
    public static func name(forClient client: String?) -> String {
        guard let client = client?.trimmingCharacters(in: .whitespacesAndNewlines), !client.isEmpty else {
            return fallbackName
        }
        return knownName(in: client) ?? client
    }

    /// Only Claude Code takes channel events; other clients read sessions through the tools.
    public static func isClaudeCode(client: String?) -> Bool {
        guard let client else { return false }
        return knownName(in: client) == "Claude Code"
    }

    /// The agent behind a `watch` / `run` process, from its environment and its ancestors' names
    /// (nearest first); nil when nothing recognizable started it.
    public static func name(environment: [String: String], ancestors: [String]) -> String? {
        if environment["CLAUDECODE"] == "1" || environment["CLAUDE_CODE_ENTRYPOINT"] != nil {
            return "Claude Code"
        }
        if environment.keys.contains(where: { $0.hasPrefix("CODEX_") }) {
            return "Codex"
        }
        if environment["CURSOR_TRACE_ID"] != nil || environment["CURSOR_AGENT"] != nil {
            return "Cursor"
        }
        return ancestors.lazy.compactMap(knownName(in:)).first
    }

    static func knownName(in raw: String) -> String? {
        let lowered = raw.lowercased()
        if lowered.contains("claude") { return "Claude Code" }
        if lowered.contains("cursor") { return "Cursor" }
        if lowered.contains("codex") { return "Codex" }
        if lowered.contains("windsurf") { return "Windsurf" }
        if lowered.contains("visual studio code") || lowered == "vscode" || lowered.hasPrefix("code helper") {
            return "VS Code"
        }
        return nil
    }

    #if os(macOS) || os(Linux)
    /// Command names of this process's ancestors, nearest first, from `ps`. Empty when `ps` fails.
    public static func ancestorNames(limit: Int = 8) -> [String] {
        var names: [String] = []
        var pid = ProcessInfo.processInfo.processIdentifier
        // Depth 0 is this process itself: only its parent link is used
        for depth in 0...limit {
            guard let info = parentAndName(of: pid) else { break }
            if depth > 0 { names.append(info.name) }
            guard info.parent > 1 else { break }
            pid = info.parent
        }
        return names
    }

    /// `ps -o ppid=,comm= -p <pid>` → (parent pid, command name).
    private static func parentAndName(of pid: Int32) -> (parent: Int32, name: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "ppid=,comm=", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let space = line.firstIndex(of: " "),
              let parent = Int32(line[..<space]) else { return nil }
        let command = line[space...].trimmingCharacters(in: .whitespaces)
        return (parent, (command as NSString).lastPathComponent)
    }

    /// The agent running this process, or nil.
    public static func current() -> String? {
        name(environment: ProcessInfo.processInfo.environment, ancestors: ancestorNames())
    }
    #endif
}

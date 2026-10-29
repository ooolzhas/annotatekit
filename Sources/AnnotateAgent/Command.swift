// Argument parsing and dispatch for the `annotate` executable (kept here, not in the executable
// target, so it's unit-testable). Commands:
//   annotate mcp                     channel MCP server for Claude Code (stdio)
//   annotate watch [--once]          one line per new session on stdout, for a Monitor / background watcher
//   annotate run [--fresh] [--permission-mode M] [-- <claude args>]   headless claude -p per session
//   annotate status <id|latest> <working|done|failed> [message…]
//   annotate list
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
          annotate watch [--once]      print one line per new session (for a Monitor or background watcher)
          annotate run [--fresh] [--permission-mode acceptEdits] [-- <extra claude args>]
                                       run `claude -p` for every new session, unattended
          annotate status <id|latest> <working|done|failed> [message]
                                       report progress back to the app
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

        public var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) needs a value"
            case .unknown(let token): "unknown argument \(token)"
            case .invalidState(let state): "state must be working, done or failed (got \(state))"
            case .missingArguments(let usage): "usage: \(usage)"
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

    static func writeLine(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func writeError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

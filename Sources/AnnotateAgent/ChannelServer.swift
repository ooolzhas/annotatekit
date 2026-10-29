// `annotate mcp`: a stdio MCP server that pushes each new session into the running Claude Code
// session as a channel event (Claude Code channels, research preview), so Send in the app starts
// a turn with no copy/paste. It also exposes tools, which work with or without channels:
//   get_annotation_session  prompt + annotated screens + crops as images; marks the session received
//   annotation_status       working / done / failed + one-line message, shown live in the app
//   list_annotation_sessions
// Wire format: newline-delimited JSON-RPC 2.0 on stdin/stdout. Channel capability is declared as
// `experimental["claude/channel"]`; events go out as `notifications/claude/channel`.
// Claude Code must be started with `--dangerously-load-development-channels server:annotate` for
// events to arrive; without it they're dropped silently and the tools still work. Because a drop is
// silent, a pushed session counts as delivered only once Claude is seen acting on one: until then,
// an event nobody answers within `ackTimeout` is released for a watcher or the tools, and the
// server stops claiming. Clients other than Claude Code never get pushes; they read with the tools.

import AnnotateCore
import Foundation

public actor ChannelServer {
    public static let serverName = "annotate"
    public static let version = "0.1.1"
    /// Answered regardless of the client's request: Claude Code doesn't register channel servers
    /// that negotiate its newest revision (same effect as MCP_PROTOCOL_NEGOTIATION=legacy).
    public static let protocolVersion = "2025-06-18"

    public static let instructions = """
        Annotate delivers UI annotations the user just drew on their running iOS app. A \
        channel event from "annotate" means: make those UI changes now. Steps: \
        (1) call get_annotation_session with the event's session_id to see the annotated \
        screenshots and crops (this also tells the app you picked it up); \
        (2) find the code and make the changes — coordinates are iOS points, origin top-left, and \
        screen images are 1x so pixel = point; use the nearby text and visible-text outline to grep \
        for the SwiftUI view; \
        (3) call annotation_status with state "done" and a one-line summary of what you changed, \
        or "failed" with the reason. For long work, send state "working" with a short progress note \
        first. The user sees these statuses on the device.
        """

    let feed: SessionFeed
    let send: @Sendable (Data) -> Void
    let maxImages: Int
    let maxImageBytes: Int
    /// Seconds a pushed session may go unanswered before it's handed back (see the header).
    let ackTimeout: TimeInterval
    private var isInitialized = false
    private var announced: Set<String> = []
    /// `clientInfo.name` from initialize: "claude-code", "cursor-vscode"…
    private(set) var clientName: String?
    /// Claude has answered a pushed session, so channel events reach it.
    private(set) var channelConfirmed = false
    /// A pushed session went unanswered: stop claiming and leave sessions to other consumers.
    private(set) var channelSilent = false
    private var awaitingAck: [String: Date] = [:]

    public init(
        feed: SessionFeed,
        maxImages: Int = 10,
        maxImageBytes: Int = 6_000_000,
        ackTimeout: TimeInterval = 45,
        send: @escaping @Sendable (Data) -> Void
    ) {
        self.feed = feed
        self.maxImages = maxImages
        self.maxImageBytes = maxImageBytes
        self.ackTimeout = ackTimeout
        self.send = send
    }

    /// What this server tells the app through its heartbeat: push only once a channel is confirmed.
    public func presence() -> AgentPresence {
        AgentPresence(
            agent: AgentIdentity.name(forClient: clientName),
            mode: channelConfirmed ? .push : .pull,
            via: channelConfirmed ? "channel" : "mcp"
        )
    }

    // MARK: Stdio

    /// Serves on stdin/stdout until stdin closes, polling for new sessions twice a second.
    /// `alongside` runs for as long as the server does and is cancelled (and awaited) when it ends.
    public static func serveStdio(feed: SessionFeed, alongside: (@Sendable (ChannelServer) async -> Void)? = nil) async {
        let server = ChannelServer(feed: feed) { data in
            FileHandle.standardOutput.write(data)
        }
        let side = Task { await alongside?(server) }
        let (lines, continuation) = AsyncStream.makeStream(of: String.self)
        let reader = Thread {
            while let line = readLine(strippingNewline: true) {
                continuation.yield(line)
            }
            continuation.finish()
        }
        reader.start()
        let poller = Task {
            while !Task.isCancelled {
                await server.poll()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        for await line in lines {
            await server.handle(line)
        }
        poller.cancel()
        side.cancel()
        await side.value
    }

    // MARK: JSON-RPC

    public func handle(_ line: String) {
        guard let data = line.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let method = message["method"] as? String else { return }
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            clientName = (params["clientInfo"] as? [String: Any])?["name"] as? String
            respond(to: id, result: initializeResult())
        case "notifications/initialized":
            isInitialized = true
            poll()
        case "ping":
            respond(to: id, result: [String: Any]())
        case "tools/list":
            respond(to: id, result: ["tools": Self.toolDefinitions()])
        case "tools/call":
            respond(to: id, result: callTool(params))
        default:
            // Notifications (no id) we don't handle are ignored; unknown requests get an error
            if id != nil {
                respondError(to: id, code: -32601, message: "Method not found: \(method)")
            }
        }
    }

    /// Announces sessions sent since startup that no other consumer has claimed, and hands back
    /// pushes that went unanswered.
    public func poll(now: Date = Date()) {
        guard isInitialized else { return }
        releaseUnanswered(now: now)
        guard pushesSessions(now: now) else { return }
        for sessionID in feed.claimPending(as: .delivered) where announced.insert(sessionID).inserted {
            awaitingAck[sessionID] = now
            announce(sessionID)
        }
    }

    /// Only Claude Code takes channel events, and an unconfirmed channel yields to a watcher or
    /// headless runner in the same folder: they deliver for certain.
    private func pushesSessions(now: Date) -> Bool {
        guard AgentIdentity.isClaudeCode(client: clientName), !channelSilent else { return false }
        if channelConfirmed { return true }
        let others = AgentPresenceFile.liveHeartbeats(in: feed.outputDirectory, now: now)
        return !others.contains { $0.via == "watch" || $0.via == "run" }
    }

    private func releaseUnanswered(now: Date) {
        guard !channelConfirmed else {
            awaitingAck.removeAll()
            return
        }
        for (sessionID, sentAt) in awaitingAck where now.timeIntervalSince(sentAt) > ackTimeout {
            awaitingAck[sessionID] = nil
            if SessionInbox.release(id: sessionID, in: feed.outputDirectory) {
                announced.remove(sessionID)
            }
            if !channelSilent {
                channelSilent = true
                FileHandle.standardError.write(Data((
                    "annotate: channel events aren't reaching Claude (start Claude Code with "
                        + "--dangerously-load-development-channels, or run `annotate watch`); "
                        + "leaving sessions for the tools\n").utf8))
            }
        }
    }

    /// Claude called a tool while a push was waiting: the channel works.
    private func noteAgentActivity() {
        guard !awaitingAck.isEmpty else { return }
        channelConfirmed = true
        channelSilent = false
        awaitingAck.removeAll()
    }

    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": Self.protocolVersion,
            "capabilities": [
                "tools": [String: Any](),
                "experimental": ["claude/channel": [String: Any]()]
            ],
            "serverInfo": ["name": Self.serverName, "version": Self.version],
            "instructions": Self.instructions
        ]
    }

    private func announce(_ sessionID: String) {
        let prompt = (try? SessionInbox.loadPrompt(id: sessionID, in: feed.outputDirectory)) ?? ""
        let content = "New UI annotations from the app (session \(sessionID)). "
            + "Call get_annotation_session with this session_id to see the screenshots, then make the changes.\n\n"
            + prompt
        notify(method: "notifications/claude/channel", params: [
            "content": content,
            "meta": ["session_id": sessionID, "session_dir": feed.sessionDirectory(sessionID).path]
        ])
    }

    // MARK: Tools

    static func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "get_annotation_session",
                "description": "Load a UI annotation session sent from the iOS app: the prompt with every pin "
                    + "(element, coordinates, comment, nearby text), the annotated screenshots with numbered pins, "
                    + "and per-pin crops. Marks the session as picked up in the app.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string", "description": "Session id from the channel event. Omit for the latest session."]
                    ]
                ]
            ],
            [
                "name": "annotation_status",
                "description": "Report progress on an annotation session; the user sees it on the device. "
                    + "Call with state \"done\" and a one-line summary when finished, or \"failed\" with the reason.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string"],
                        "state": ["type": "string", "enum": ["working", "done", "failed"]],
                        "message": ["type": "string", "description": "One line, e.g. \"Edited HomeView.swift and AlarmCard.swift\""]
                    ],
                    "required": ["session_id", "state"]
                ]
            ],
            [
                "name": "list_annotation_sessions",
                "description": "List recent annotation sessions with pin counts and delivery status.",
                "inputSchema": ["type": "object", "properties": [String: Any]()]
            ]
        ]
    }

    private func callTool(_ params: [String: Any]) -> [String: Any] {
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch params["name"] as? String {
        case "get_annotation_session":
            noteAgentActivity()
            return getSession(arguments["session_id"] as? String)
        case "annotation_status":
            noteAgentActivity()
            return setStatus(arguments)
        case "list_annotation_sessions":
            return listSessions()
        case let name:
            return toolError("Unknown tool \(name ?? "(none)")")
        }
    }

    private func getSession(_ requested: String?) -> [String: Any] {
        guard let sessionID = feed.resolve(requested) else {
            return toolError("No annotation sessions in \(feed.outputDirectory.path) yet.")
        }
        guard let session = try? SessionInbox.loadSession(id: sessionID, in: feed.outputDirectory),
              let prompt = try? SessionInbox.loadPrompt(id: sessionID, in: feed.outputDirectory) else {
            return toolError("Session \(sessionID) is missing or incomplete.")
        }
        let status = SessionInbox.readStatus(id: sessionID, in: feed.outputDirectory)
        if status == nil || status?.state == .delivered {
            try? SessionInbox.writeStatus(SessionStatus(state: .received), id: sessionID, in: feed.outputDirectory)
        }

        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        var budget = maxImageBytes
        let directory = feed.sessionDirectory(sessionID)
        let paths = session.screens.compactMap(\.annotatedImage)
            + session.annotations.sorted { $0.index < $1.index }.compactMap(\.crop)
        for path in paths.filter(SessionInbox.isSafeRelativePath).prefix(maxImages) {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(path)), data.count <= budget else { continue }
            budget -= data.count
            content.append(["type": "text", "text": path])
            content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
        }
        return ["content": content]
    }

    private func setStatus(_ arguments: [String: Any]) -> [String: Any] {
        guard let sessionID = feed.resolve(arguments["session_id"] as? String) else {
            return toolError("session_id is required.")
        }
        guard let raw = arguments["state"] as? String,
              let state = SessionStatus.State(rawValue: raw),
              SessionStatus.State.reportable.contains(state) else {
            return toolError("state must be one of working, done, failed.")
        }
        let message = arguments["message"] as? String
        do {
            try SessionInbox.writeStatus(SessionStatus(state: state, message: message), id: sessionID, in: feed.outputDirectory)
        } catch {
            return toolError("Couldn't write status for \(sessionID): \(error.localizedDescription)")
        }
        return ["content": [["type": "text", "text": "Status for \(sessionID): \(state.rawValue)"]]]
    }

    private func listSessions() -> [String: Any] {
        let ids = SessionInbox.sessionIDs(in: feed.outputDirectory).suffix(15).reversed()
        guard !ids.isEmpty else {
            return ["content": [["type": "text", "text": "No annotation sessions in \(feed.outputDirectory.path) yet."]]]
        }
        let lines = ids.map { id -> String in
            let pins = (try? SessionInbox.loadSession(id: id, in: feed.outputDirectory))?.annotations.count ?? 0
            let status = SessionInbox.readStatus(id: id, in: feed.outputDirectory)
            let state = status.map { $0.state.rawValue + ($0.message.map { " — \($0)" } ?? "") } ?? "not picked up"
            return "\(id) · \(pins) \(pins == 1 ? "pin" : "pins") · \(state)"
        }
        return ["content": [["type": "text", "text": lines.joined(separator: "\n")]]]
    }

    private func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    // MARK: Output

    private func respond(to id: Any?, result: [String: Any]) {
        guard let id else { return }
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func respondError(to id: Any?, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private func notify(method: String, params: [String: Any]) {
        write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        send(data)
    }
}

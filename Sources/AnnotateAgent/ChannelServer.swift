// `annotate mcp`: a stdio MCP server that pushes each new session into the running Claude Code
// session as a channel event (Claude Code channels, research preview), so Send in the app starts
// a turn with no copy/paste. It also exposes tools, which work with or without channels:
//   get_annotation_session  prompt + annotated screens + crops as images; marks the session received
//   annotation_status       working / done / failed + one-line message, shown live in the app
//   list_annotation_sessions
//   annotation_wait         blocks until Sends (or replies to questions) arrive, batches them and
//                           returns them; hands-free delivery for any MCP client, no channels needed
//   annotation_resolve / annotation_dismiss   per-pin result the app shows next to each note
//   annotation_ask          asks the user about one pin and waits for the reply typed on the device
// Wire format: newline-delimited JSON-RPC 2.0 on stdin/stdout. Channel capability is declared as
// `experimental["claude/channel"]`; events go out as `notifications/claude/channel`.
// Claude Code must be started with `--dangerously-load-development-channels server:annotate` for
// events to arrive; without it they're dropped silently and the tools still work. Because a drop is
// silent, a pushed session counts as delivered only once Claude is seen acting on one: until then,
// an event nobody answers within `ackTimeout` is released for a watcher or the tools, and the
// server stops claiming. Clients other than Claude Code never get pushes; they read with the tools.
// annotation_wait and annotation_ask run in their own Task so a long wait never stalls the line
// loop (pings, other tool calls, `notifications/cancelled`). A pending wait is push presence: it
// takes new sessions itself, so channel pushes pause while one is open. Agents call it in a loop,
// so presence stays "wait" for `waitPresenceWindow` after one ends.

import AnnotateCore
import Foundation

public actor ChannelServer {
    public static let serverName = "annotate"
    public static let version = "0.2.1"
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
        first; before rebuilding and reinstalling the app, send "working" with "Changes applied, \
        reinstalling". The user sees these statuses on the device. \
        Without channel events, call annotation_wait in a loop: it returns each new session (and \
        the user's answers to your questions) as it arrives. \
        Report each pin as you finish it with annotation_resolve (what changed) or \
        annotation_dismiss (why not). \
        When a pin is unclear, ask with annotation_ask; the user answers on the device.
        """

    /// annotation_wait `timeout_seconds` (contract A1).
    static let waitDefaultSeconds: Double = 120
    static let waitMaxSeconds: Double = 300
    /// annotation_wait `batch_seconds`: how long to keep collecting after the first arrival (contract A1).
    static let batchDefaultSeconds: Double = 10
    static let batchMaxSeconds: Double = 60
    /// annotation_ask `wait_seconds` (contract A1).
    static let askDefaultSeconds: Double = 120
    static let askMaxSeconds: Double = 300
    /// Agents call annotation_wait in a loop; the gap between two calls still counts as push
    /// presence for this long after one ends (contract A1).
    static let waitPresenceWindow: TimeInterval = 30
    /// Disk poll cadence while a wait or ask is pending; matches the stdio poller.
    static let waitPollInterval: Duration = .milliseconds(500)

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
    /// annotation_wait calls in flight.
    private(set) var activeWaits = 0
    /// When the last annotation_wait returned (see `waitPresenceWindow`).
    private(set) var lastWaitEnded: Date?
    /// Pins an annotation_ask is waiting on ("<session>#<pin>" → count): their replies go to the
    /// ask, not to a wait or a channel event.
    private var askedPins: [String: Int] = [:]
    /// Long-running tool calls by JSON-encoded request id, so `notifications/cancelled` can stop them.
    private var calls: [Data: Task<Void, Never>] = [:]

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

    /// What this server tells the app through its heartbeat: push while an agent is waiting on
    /// annotation_wait (or just was) or once a channel is confirmed; pull otherwise.
    public func presence(now: Date = Date()) -> AgentPresence {
        let agent = AgentIdentity.name(forClient: clientName)
        if isWaitPresent(now: now) {
            return AgentPresence(agent: agent, mode: .push, via: "wait")
        }
        if channelConfirmed {
            return AgentPresence(agent: agent, mode: .push, via: "channel")
        }
        return AgentPresence(agent: agent, mode: .pull, via: "mcp")
    }

    private func isWaitPresent(now: Date) -> Bool {
        if activeWaits > 0 { return true }
        guard let lastWaitEnded else { return false }
        return now.timeIntervalSince(lastWaitEnded) < Self.waitPresenceWindow
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
            switch callTool(params) {
            case .done(let result):
                respond(to: id, result: result)
            case .pending(let call):
                start(call, id: id)
            }
        case "notifications/cancelled":
            // MCP: the client gave up on a request; stop a pending wait/ask and send no response
            if let key = Self.encodeID(params["requestId"]), let task = calls.removeValue(forKey: key) {
                task.cancel()
            }
        default:
            // Notifications (no id) we don't handle are ignored; unknown requests get an error
            if id != nil {
                respondError(to: id, code: -32601, message: "Method not found: \(method)")
            }
        }
    }

    /// Announces sessions sent since startup that no other consumer has claimed, and hands back
    /// pushes that went unanswered. Over a confirmed channel it also announces the user's replies.
    public func poll(now: Date = Date()) {
        guard isInitialized else { return }
        releaseUnanswered(now: now)
        // A pending annotation_wait takes new sessions and replies itself
        guard activeWaits == 0 else { return }
        guard pushesSessions(now: now) else { return }
        for sessionID in feed.claimPending(as: .delivered) where announced.insert(sessionID).inserted {
            awaitingAck[sessionID] = now
            announce(sessionID)
        }
        if channelConfirmed {
            announceReplies()
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

    /// Replies to questions asked earlier (an ask that timed out, or another process's ask), pushed
    /// once each. Pins a live annotation_ask is waiting on are left to it.
    private func announceReplies() {
        for item in feed.pendingReplies() where !isAsked(item.sessionID, item.reply.index) {
            feed.consume(item.reply, sessionID: item.sessionID)
            notify(method: "notifications/claude/channel", params: [
                "content": Self.replyText(sessionID: item.sessionID, reply: item.reply),
                "meta": ["session_id": item.sessionID]
            ])
        }
    }

    static func replyText(sessionID: String, reply: PinReply) -> String {
        "The user answered your question on pin \(reply.index) of session \(sessionID): \(reply.text)"
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
            ],
            [
                "name": "annotation_wait",
                "description": "Wait for the user to send UI annotations from the iOS app (or answer a question you asked). "
                    + "Blocks until something arrives, keeps collecting for batch_seconds, then returns each session "
                    + "(prompt + images, as get_annotation_session) and each answer. Call it again in a loop to keep listening.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "timeout_seconds": [
                            "type": "number",
                            "description": "Give up after this long with nothing new (default 120, max 300)."
                        ],
                        "batch_seconds": [
                            "type": "number",
                            "description": "After the first arrival, keep collecting this long (default 10, max 60)."
                        ]
                    ]
                ]
            ],
            [
                "name": "annotation_resolve",
                "description": "Mark one pin of a session as done; the user sees the summary next to that note in the app.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string"],
                        "pin": ["type": "integer", "description": "The note number from the prompt."],
                        "summary": ["type": "string", "description": "One line: what changed."]
                    ],
                    "required": ["session_id", "pin"]
                ]
            ],
            [
                "name": "annotation_dismiss",
                "description": "Mark one pin of a session as not done; the user sees the reason next to that note in the app.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string"],
                        "pin": ["type": "integer", "description": "The note number from the prompt."],
                        "reason": ["type": "string", "description": "One line: why not."]
                    ],
                    "required": ["session_id", "pin"]
                ]
            ],
            [
                "name": "annotation_ask",
                "description": "Ask the user a question about one pin. The app shows it on that note and the user "
                    + "answers on the device. Waits up to wait_seconds for the answer; a later answer arrives "
                    + "through annotation_wait (or a channel event).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "session_id": ["type": "string"],
                        "pin": ["type": "integer", "description": "The note number from the prompt."],
                        "question": ["type": "string"],
                        "wait_seconds": [
                            "type": "number",
                            "description": "How long to wait for the answer (default 120, max 300)."
                        ]
                    ],
                    "required": ["session_id", "pin", "question"]
                ]
            ]
        ]
    }

    /// A tool's outcome: answered now, or a long-running call answered from its own Task.
    private enum ToolOutcome {
        case done([String: Any])
        case pending(LongCall)
    }

    /// Long-running tool calls, with arguments already validated and Sendable.
    private enum LongCall: Sendable {
        case wait(timeout: Double, batch: Double)
        case ask(sessionID: String, pin: Int, wait: Double)
    }

    private func callTool(_ params: [String: Any]) -> ToolOutcome {
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch params["name"] as? String {
        case "get_annotation_session":
            noteAgentActivity()
            return .done(getSession(arguments["session_id"] as? String))
        case "annotation_status":
            noteAgentActivity()
            return .done(setStatus(arguments))
        case "list_annotation_sessions":
            return .done(listSessions())
        case "annotation_wait":
            noteAgentActivity()
            return .pending(.wait(
                timeout: Self.seconds(arguments["timeout_seconds"], default: Self.waitDefaultSeconds, max: Self.waitMaxSeconds),
                batch: Self.seconds(arguments["batch_seconds"], default: Self.batchDefaultSeconds, max: Self.batchMaxSeconds)
            ))
        case "annotation_resolve":
            noteAgentActivity()
            return .done(setPin(arguments, state: .resolved, noteKey: "summary"))
        case "annotation_dismiss":
            noteAgentActivity()
            return .done(setPin(arguments, state: .dismissed, noteKey: "reason"))
        case "annotation_ask":
            noteAgentActivity()
            return ask(arguments)
        case let name:
            return .done(toolError("Unknown tool \(name ?? "(none)")"))
        }
    }

    private func getSession(_ requested: String?) -> [String: Any] {
        guard let sessionID = feed.resolve(requested) else {
            return toolError("No annotation sessions in \(feed.outputDirectory.path) yet.")
        }
        guard let content = sessionContent(sessionID) else {
            return toolError("Session \(sessionID) is missing or incomplete.")
        }
        return ["content": content]
    }

    /// Prompt + annotated screens + crops for one session, marking it received; nil when the
    /// bundle is missing or incomplete. Shared by get_annotation_session and annotation_wait.
    private func sessionContent(_ sessionID: String) -> [[String: Any]]? {
        guard let session = try? SessionInbox.loadSession(id: sessionID, in: feed.outputDirectory),
              let prompt = try? SessionInbox.loadPrompt(id: sessionID, in: feed.outputDirectory) else {
            return nil
        }
        let status = SessionInbox.readStatus(id: sessionID, in: feed.outputDirectory)
        if status == nil || status?.state == .delivered {
            try? SessionInbox.writeStatus(SessionStatus(state: .received), id: sessionID, in: feed.outputDirectory)
        }

        var content: [[String: Any]] = [Self.text(prompt)]
        var budget = maxImageBytes
        let directory = feed.sessionDirectory(sessionID)
        let paths = session.screens.compactMap(\.annotatedImage)
            + session.annotations.sorted { $0.index < $1.index }.compactMap(\.crop)
        for path in paths.filter(SessionInbox.isSafeRelativePath).prefix(maxImages) {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(path)), data.count <= budget else { continue }
            budget -= data.count
            content.append(Self.text(path))
            content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"])
        }
        return content
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
        return ["content": [Self.text("Status for \(sessionID): \(state.rawValue)")]]
    }

    private func listSessions() -> [String: Any] {
        let ids = SessionInbox.sessionIDs(in: feed.outputDirectory).suffix(15).reversed()
        guard !ids.isEmpty else {
            return ["content": [Self.text("No annotation sessions in \(feed.outputDirectory.path) yet.")]]
        }
        let lines = ids.map { id -> String in
            let pins = (try? SessionInbox.loadSession(id: id, in: feed.outputDirectory))?.annotations.count ?? 0
            let status = SessionInbox.readStatus(id: id, in: feed.outputDirectory)
            let state = status.map { $0.state.rawValue + ($0.message.map { " — \($0)" } ?? "") } ?? "not picked up"
            return "\(id) · \(pins) \(pins == 1 ? "pin" : "pins") · \(state)"
        }
        return ["content": [Self.text(lines.joined(separator: "\n"))]]
    }

    // MARK: Per-pin tools

    /// The session and pin a per-pin tool names, or the tool error to return.
    private func pinTarget(_ arguments: [String: Any]) -> Result<(sessionID: String, pin: Int), PinTargetError> {
        guard let sessionID = feed.resolve(arguments["session_id"] as? String) else {
            return .failure(PinTargetError(message: "session_id is required."))
        }
        guard let pin = Self.integer(arguments["pin"]) else {
            return .failure(PinTargetError(message: "pin must be the note number from the prompt."))
        }
        guard let session = try? SessionInbox.loadSession(id: sessionID, in: feed.outputDirectory) else {
            return .failure(PinTargetError(message: "Session \(sessionID) is missing or incomplete."))
        }
        guard session.annotations.contains(where: { $0.index == pin }) else {
            return .failure(PinTargetError(message: "Session \(sessionID) has no pin \(pin)."))
        }
        return .success((sessionID, pin))
    }

    private struct PinTargetError: Error {
        let message: String
    }

    private func setPin(_ arguments: [String: Any], state: PinStatus.State, noteKey: String) -> [String: Any] {
        let target: (sessionID: String, pin: Int)
        switch pinTarget(arguments) {
        case .success(let value): target = value
        case .failure(let error): return toolError(error.message)
        }
        let note = Self.trimmed(arguments[noteKey] as? String)
        do {
            try SessionInbox.updatePin(
                PinStatus(index: target.pin, state: state, note: note),
                id: target.sessionID, in: feed.outputDirectory
            )
        } catch {
            return toolError("Couldn't update pin \(target.pin) of \(target.sessionID): \(error.localizedDescription)")
        }
        return ["content": [Self.text("Pin \(target.pin) of \(target.sessionID): \(state.rawValue)")]]
    }

    /// Writes the question now (so the app shows it at once), then waits for the answer in a Task.
    private func ask(_ arguments: [String: Any]) -> ToolOutcome {
        let target: (sessionID: String, pin: Int)
        switch pinTarget(arguments) {
        case .success(let value): target = value
        case .failure(let error): return .done(toolError(error.message))
        }
        guard let question = Self.trimmed(arguments["question"] as? String) else {
            return .done(toolError("question is required."))
        }
        do {
            try SessionInbox.updatePin(
                PinStatus(index: target.pin, state: .question, note: question),
                id: target.sessionID, in: feed.outputDirectory
            )
        } catch {
            return .done(toolError("Couldn't ask about pin \(target.pin) of \(target.sessionID): \(error.localizedDescription)"))
        }
        let wait = Self.seconds(arguments["wait_seconds"], default: Self.askDefaultSeconds, max: Self.askMaxSeconds)
        return .pending(.ask(sessionID: target.sessionID, pin: target.pin, wait: wait))
    }

    // MARK: Long-running calls

    /// Runs `call` in its own Task on this actor so the line loop keeps serving; the Task awaits
    /// only `Task.sleep`, so other messages interleave between polls.
    private func start(_ call: LongCall, id: Any?) {
        let key = Self.encodeID(id)
        let task = Task { await self.serve(call, key: key) }
        if let key {
            calls[key] = task
        }
    }

    private func serve(_ call: LongCall, key: Data?) async {
        let result: [String: Any]?
        switch call {
        case let .wait(timeout, batch):
            result = await collectArrivals(timeout: timeout, batch: batch)
        case let .ask(sessionID, pin, wait):
            result = await awaitReply(sessionID: sessionID, pin: pin, wait: wait)
        }
        guard let key else { return }
        calls[key] = nil
        // Cancelled (notifications/cancelled): MCP says send no response
        guard let result, !Task.isCancelled else { return }
        respond(to: Self.decodeID(key), result: result)
    }

    /// annotation_wait: blocks until a session or a reply arrives, keeps collecting for `batch`,
    /// then returns them all. nil when cancelled; claimed sessions are then handed back and
    /// replies stay unconsumed, so nothing is lost.
    private func collectArrivals(timeout: Double, batch: Double) async -> [String: Any]? {
        activeWaits += 1
        defer {
            activeWaits -= 1
            lastWaitEnded = Date()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var batchEnd: Date?
        var sessions: [String] = []
        var replies: [(sessionID: String, reply: PinReply)] = []
        while true {
            if Task.isCancelled {
                // Hand the sessions back and forget announcing them, so the next wait (or a channel
                // push) claims and delivers them; `announced` alone would filter them out for good
                for sessionID in sessions where SessionInbox.release(id: sessionID, in: feed.outputDirectory) {
                    announced.remove(sessionID)
                }
                return nil
            }
            for sessionID in feed.claimPending(as: .delivered) where announced.insert(sessionID).inserted {
                sessions.append(sessionID)
            }
            // Consumed only on return, so a cancelled wait leaves them for the next consumer
            for item in feed.pendingReplies() where !isAsked(item.sessionID, item.reply.index)
                && !replies.contains(where: { $0.sessionID == item.sessionID && $0.reply == item.reply }) {
                replies.append(item)
            }
            let now = Date()
            if batchEnd == nil, !sessions.isEmpty || !replies.isEmpty {
                batchEnd = now.addingTimeInterval(batch)
            }
            if let batchEnd {
                if now >= batchEnd { break }
            } else if now >= deadline {
                break
            }
            try? await Task.sleep(for: Self.waitPollInterval)
        }

        var content: [[String: Any]] = []
        for sessionID in sessions {
            content.append(Self.text("Session \(sessionID)"))
            content += sessionContent(sessionID) ?? [Self.text("Session \(sessionID) is missing or incomplete.")]
        }
        for item in replies {
            feed.consume(item.reply, sessionID: item.sessionID)
            content.append(Self.text(Self.replyText(sessionID: item.sessionID, reply: item.reply)))
        }
        if content.isEmpty {
            content.append(Self.text(
                "No new annotations in \(Int(timeout))s. Call annotation_wait again to keep listening."
            ))
        }
        return ["content": content]
    }

    /// annotation_ask: waits for the user's reply to one pin. nil when cancelled.
    private func awaitReply(sessionID: String, pin: Int, wait: Double) async -> [String: Any]? {
        let key = Self.askKey(sessionID, pin)
        askedPins[key, default: 0] += 1
        defer {
            let remaining = (askedPins[key] ?? 1) - 1
            askedPins[key] = remaining > 0 ? remaining : nil
        }
        let deadline = Date().addingTimeInterval(wait)
        while !Task.isCancelled {
            let replies = SessionInbox.unansweredReplies(id: sessionID, in: feed.outputDirectory)
            if let reply = replies.first(where: { $0.index == pin }) {
                do {
                    try SessionInbox.markAnswered(reply, id: sessionID, in: feed.outputDirectory)
                } catch {
                    // The agent still gets the answer; it may be delivered once more later
                    FileHandle.standardError.write(Data(
                        "annotate: couldn't mark pin \(pin) of \(sessionID) answered: \(error.localizedDescription)\n".utf8))
                }
                return ["content": [Self.text("The user answered: \(reply.text)")]]
            }
            if Date() >= deadline { break }
            try? await Task.sleep(for: Self.waitPollInterval)
        }
        if Task.isCancelled { return nil }
        return ["content": [Self.text("No answer yet. It will arrive through annotation_wait (or a channel event).")]]
    }

    private func isAsked(_ sessionID: String, _ pin: Int) -> Bool {
        askedPins[Self.askKey(sessionID, pin)] != nil
    }

    private static func askKey(_ sessionID: String, _ pin: Int) -> String {
        "\(sessionID)#\(pin)"
    }

    /// JSON-RPC ids are `Any` (number or string); a one-element JSON array makes them Sendable
    /// and hashable, and decodes back to the same value for the response.
    private static func encodeID(_ id: Any?) -> Data? {
        guard let id, !(id is NSNull), JSONSerialization.isValidJSONObject([id]) else { return nil }
        return try? JSONSerialization.data(withJSONObject: [id])
    }

    private static func decodeID(_ data: Data) -> Any? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [Any])?.first
    }

    // MARK: Arguments

    /// A seconds argument clamped to 0…max; `fallback` when absent or not a number.
    private static func seconds(_ value: Any?, default fallback: Double, max maximum: Double) -> Double {
        guard let number = double(value), number.isFinite else { return fallback }
        return Swift.min(Swift.max(number, 0), maximum)
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    /// Pins arrive as JSON numbers (some clients send 2.0 or "2").
    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = double(value), value.isFinite, value.rounded() == value, abs(value) < Double(Int32.max) {
            return Int(value)
        }
        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    // MARK: Output

    private static func text(_ string: String) -> [String: Any] {
        ["type": "text", "text": string]
    }

    private func toolError(_ message: String) -> [String: Any] {
        ["content": [Self.text(message)], "isError": true]
    }

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

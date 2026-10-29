// The agent loop on the Mac side: annotation_wait (async delivery of Sends and replies, wait
// presence, cancellation), the per-pin tools (acknowledge / resolve / dismiss / ask), SessionFeed's reply queue,
// the CLI's per-pin commands, and the device mirror pulling replies.json back while a question is open.

import AnnotateCore
import Foundation
import Testing
@testable import AnnotateAgent

/// JSON-RPC plumbing shared by the suites below; same shape as ChannelServerTests' helpers.
enum LoopHarness {
    static func makeServer(_ output: URL) -> (ChannelServer, Sink) {
        let sink = Sink()
        let server = ChannelServer(feed: SessionFeed(outputDirectory: output), ackTimeout: 45) { sink.append($0) }
        return (server, sink)
    }

    static func initialize(_ server: ChannelServer, client: String) async {
        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2026-07-28", "clientInfo": ["name": client, "version": "1.0"]]
        ]))
        await server.handle(AgentFixtures.json(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    }

    static func call(_ server: ChannelServer, id: Int, _ tool: String, _ arguments: [String: Any] = [:]) async {
        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": id, "method": "tools/call",
            "params": ["name": tool, "arguments": arguments]
        ]))
    }

    static func hasResponse(to id: Int, in sink: Sink) -> Bool {
        sink.messages.contains { $0["id"] as? Int == id && $0["result"] != nil }
    }

    /// The `result` of the response to `id`; long tools answer later from their own Task, so poll.
    static func response(to id: Int, in sink: Sink, within seconds: Double = 5) async -> [String: Any]? {
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        while ContinuousClock.now < deadline {
            if let message = sink.messages.first(where: { $0["id"] as? Int == id && $0["result"] != nil }) {
                return message["result"] as? [String: Any]
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    static func texts(_ result: [String: Any]?) -> [String] {
        (result?["content"] as? [[String: Any]] ?? []).compactMap { item in
            item["type"] as? String == "text" ? item["text"] as? String : nil
        }
    }

    static func channelEvents(_ sink: Sink) -> [[String: Any]] {
        sink.messages
            .filter { $0["method"] as? String == "notifications/claude/channel" }
            .compactMap { $0["params"] as? [String: Any] }
    }

    /// Polls an async condition (actor state) for up to `seconds`.
    static func eventually(within seconds: Double = 2, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    static func pin(_ index: Int, of id: String, in output: URL) -> PinStatus? {
        SessionInbox.readStatus(id: id, in: output)?.pins?.first { $0.index == index }
    }
}

// MARK: annotation_wait

@Suite struct AnnotationWaitTests {
    @Test func timesOutWithNothingNew() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        let started = ContinuousClock.now
        await LoopHarness.call(server, id: 2, "annotation_wait", ["timeout_seconds": 1, "batch_seconds": 0])
        #expect(!LoopHarness.hasResponse(to: 2, in: sink)) // handle() returned before the wait ended

        let result = try #require(await LoopHarness.response(to: 2, in: sink, within: 3))
        let elapsed = ContinuousClock.now - started
        #expect(elapsed >= .milliseconds(900))
        #expect(elapsed < .seconds(2.5))
        #expect(result["isError"] == nil)
        let texts = LoopHarness.texts(result)
        #expect(texts.count == 1)
        #expect(texts.first?.hasPrefix("No new annotations in 1s") == true)
        #expect(texts.first?.contains("annotation_wait") == true)
    }

    @Test func returnsANewSessionAndMarksItReceived() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        await LoopHarness.call(server, id: 2, "annotation_wait", ["timeout_seconds": 5, "batch_seconds": 0])
        let result = try #require(await LoopHarness.response(to: 2, in: sink, within: 2))
        let texts = LoopHarness.texts(result)
        #expect(texts.first == "Session \(id)")
        #expect(texts.contains { $0.contains("PROMPT \(id)") })
        let images = (result["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "image" }
        #expect(images.count == 2) // annotated screen + crop, as get_annotation_session
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .received)
        #expect(SessionInbox.pendingSessionIDs(in: output).isEmpty)
    }

    @Test func aPendingWaitIsPushPresence() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        await LoopHarness.initialize(server, client: "cursor-vscode")
        #expect(await server.presence().mode == .pull)

        await LoopHarness.call(server, id: 2, "annotation_wait", ["timeout_seconds": 30, "batch_seconds": 0])
        #expect(await LoopHarness.eventually { await server.activeWaits == 1 })
        let pending = await server.presence()
        #expect(pending.mode == .push)
        #expect(pending.via == "wait")
        #expect(pending.agent == "Cursor")

        // notifications/cancelled stops the wait without a response…
        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 2]
        ]))
        #expect(await LoopHarness.eventually { await server.activeWaits == 0 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(!LoopHarness.hasResponse(to: 2, in: sink))

        // …and agents call it in a loop, so presence stays "wait" for a while after one ends
        #expect(await server.presence().via == "wait")
        let later = await server.presence(now: Date().addingTimeInterval(ChannelServer.waitPresenceWindow + 1))
        #expect(later.mode == .pull)
        #expect(later.via == "mcp")
    }

    @Test func aCancelledWaitHandsItsSessionBackForTheNextWait() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        // Claimed on the first pass, then held for the batch window
        await LoopHarness.call(server, id: 2, "annotation_wait", ["timeout_seconds": 10, "batch_seconds": 10])
        #expect(await LoopHarness.eventually { SessionInbox.readStatus(id: id, in: output)?.state == .delivered })
        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 2]
        ]))
        #expect(await LoopHarness.eventually { await server.activeWaits == 0 })
        #expect(SessionInbox.pendingSessionIDs(in: output) == [id]) // released, nothing lost
        #expect(!LoopHarness.hasResponse(to: 2, in: sink))

        await LoopHarness.call(server, id: 3, "annotation_wait", ["timeout_seconds": 1, "batch_seconds": 0])
        let result = try #require(await LoopHarness.response(to: 3, in: sink, within: 3))
        // A cancelled wait hands its session back, so the next wait delivers it
        #expect(LoopHarness.texts(result).first == "Session \(id)")
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .received)
    }

    @Test func aPendingWaitTakesSessionsInsteadOfChannelPushes() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        await LoopHarness.initialize(server, client: "claude-code")

        await LoopHarness.call(server, id: 2, "annotation_wait", ["timeout_seconds": 5, "batch_seconds": 0])
        #expect(await LoopHarness.eventually { await server.activeWaits == 1 })
        let id = try AgentFixtures.writeSession(to: output)
        await server.poll()
        #expect(LoopHarness.channelEvents(sink).isEmpty)

        let result = try #require(await LoopHarness.response(to: 2, in: sink, within: 3))
        #expect(LoopHarness.texts(result).first == "Session \(id)")
        #expect(LoopHarness.channelEvents(sink).isEmpty)
    }

    @Test func returnsAReplyAndConsumesIt() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        // Sent long before this consumer started: replies are surfaced regardless of the cutoff
        let id = try AgentFixtures.writeSession(id: "20200101-000000-aaaa", to: output)
        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "Which blue?", updatedAt: Date().addingTimeInterval(-60)), id: id, in: output)
        try SessionInbox.appendReply(PinReply(index: 1, text: "The brand one"), id: id, in: output)
        let (server, sink) = LoopHarness.makeServer(output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        await LoopHarness.call(server, id: 2, "annotation_wait", ["timeout_seconds": 5, "batch_seconds": 0])
        let result = try #require(await LoopHarness.response(to: 2, in: sink, within: 2))
        #expect(LoopHarness.texts(result) == ["The user answered your question on pin 1 of session \(id): The brand one"])
        let pin = try #require(LoopHarness.pin(1, of: id, in: output))
        #expect(pin.state == .answered)
        #expect(pin.note == "Which blue?")
        #expect(pin.reply == "The brand one")
    }

    @Test func aConfirmedChannelAnnouncesRepliesOnce() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "claude-code") // pushes the session
        await LoopHarness.call(server, id: 2, "get_annotation_session", ["session_id": id]) // confirms the channel
        #expect(await server.channelConfirmed)

        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "Which blue?", updatedAt: Date().addingTimeInterval(-60)), id: id, in: output)
        try SessionInbox.appendReply(PinReply(index: 1, text: "The brand one"), id: id, in: output)
        await server.poll()
        await server.poll()

        let events = LoopHarness.channelEvents(sink)
        #expect(events.count == 2) // the session, then the reply
        let reply = try #require(events.last)
        #expect(reply["content"] as? String == "The user answered your question on pin 1 of session \(id): The brand one")
        #expect((reply["meta"] as? [String: String])?["session_id"] == id)
        #expect(LoopHarness.pin(1, of: id, in: output)?.state == .answered)
    }
}

// MARK: Per-pin tools

@Suite struct PinToolTests {
    @Test func resolveAndDismissWritePinStatus() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        await LoopHarness.call(server, id: 2, "annotation_resolve", ["session_id": id, "pin": 1, "summary": "Edited HomeView.swift"])
        #expect((sink.messages.last?["result"] as? [String: Any])?["isError"] == nil)
        var status = try #require(SessionInbox.readStatus(id: id, in: output))
        #expect(status.state == .working) // a pin report on an unclaimed session means the agent is on it
        #expect(status.pins?.count == 1)
        #expect(status.pins?.first?.index == 1)
        #expect(status.pins?.first?.state == .resolved)
        #expect(status.pins?.first?.note == "Edited HomeView.swift")

        await LoopHarness.call(server, id: 3, "annotation_dismiss", ["session_id": id, "pin": 1, "reason": "Already 16pt"])
        #expect((sink.messages.last?["result"] as? [String: Any])?["isError"] == nil)
        status = try #require(SessionInbox.readStatus(id: id, in: output))
        #expect(status.pins?.count == 1) // upserted by index
        #expect(status.pins?.first?.state == .dismissed)
        #expect(status.pins?.first?.note == "Already 16pt")
    }

    @Test func acknowledgeRecordsThePinTheAgentIsOn() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        await LoopHarness.call(server, id: 2, "annotation_acknowledge", ["session_id": id, "pin": 1])
        let result = try #require(await LoopHarness.response(to: 2, in: sink, within: 1))
        #expect(result["isError"] == nil)
        let status = try #require(SessionInbox.readStatus(id: id, in: output))
        #expect(status.state == .working)
        #expect(status.acknowledged == [1])

        await LoopHarness.call(server, id: 3, "annotation_acknowledge", ["session_id": id, "pin": 4])
        let unknown = try #require(await LoopHarness.response(to: 3, in: sink, within: 1))
        #expect(unknown["isError"] as? Bool == true)
        #expect(SessionInbox.readStatus(id: id, in: output)?.acknowledged == [1])
    }

    @Test func unknownPinsAndSessionsAreErrors() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        let calls: [(String, [String: Any])] = [
            ("annotation_resolve", ["session_id": id, "pin": 7, "summary": "x"]),
            ("annotation_dismiss", ["session_id": id, "pin": 7, "reason": "x"]),
            ("annotation_resolve", ["session_id": "20200101-000000-zzzz", "pin": 1]),
            ("annotation_ask", ["session_id": id, "pin": 7, "question": "why?"]),
            ("annotation_ask", ["session_id": id, "pin": 1])
        ]
        for (offset, call) in calls.enumerated() {
            let requestID = 10 + offset
            await LoopHarness.call(server, id: requestID, call.0, call.1)
            let result = try #require(await LoopHarness.response(to: requestID, in: sink, within: 1))
            #expect(result["isError"] as? Bool == true, "\(call.0) \(call.1)")
        }
        #expect(SessionInbox.readStatus(id: id, in: output) == nil) // nothing written
    }

    @Test func askReturnsTheUsersAnswer() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        await LoopHarness.call(server, id: 2, "annotation_ask", ["session_id": id, "pin": 1, "question": "Which blue?", "wait_seconds": 3])
        // The question is on disk at once, so the app can show it while the ask waits
        #expect(LoopHarness.pin(1, of: id, in: output)?.state == .question)
        #expect(LoopHarness.pin(1, of: id, in: output)?.note == "Which blue?")
        #expect(!LoopHarness.hasResponse(to: 2, in: sink))

        try await Task.sleep(for: .milliseconds(300))
        try SessionInbox.appendReply(PinReply(index: 1, text: "The brand one"), id: id, in: output)

        let result = try #require(await LoopHarness.response(to: 2, in: sink, within: 3))
        let text = try #require(LoopHarness.texts(result).first)
        #expect(text.contains("The user answered"))
        #expect(text.contains("The brand one"))
        let pin = try #require(LoopHarness.pin(1, of: id, in: output))
        #expect(pin.state == .answered)
        #expect(pin.note == "Which blue?")
        #expect(pin.reply == "The brand one")
        #expect(pin.thread?.map(\.role) == [.agent, .human])
        #expect(pin.thread?.map(\.text) == ["Which blue?", "The brand one"])
    }

    @Test func askTimesOutWithNoAnswerYet() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = LoopHarness.makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await LoopHarness.initialize(server, client: "cursor-vscode")

        await LoopHarness.call(server, id: 2, "annotation_ask", ["session_id": id, "pin": 1, "question": "Which blue?", "wait_seconds": 1])
        let result = try #require(await LoopHarness.response(to: 2, in: sink, within: 3))
        #expect(result["isError"] == nil)
        #expect(LoopHarness.texts(result).first?.hasPrefix("No answer yet") == true)
        #expect(LoopHarness.pin(1, of: id, in: output)?.state == .question) // still open for annotation_wait
    }
}

// MARK: SessionFeed replies

@Suite struct SessionFeedReplyTests {
    @Test func aReplyToAnOpenQuestionIsPendingUntilConsumed() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let id = try AgentFixtures.writeSession(to: output)
        let feed = SessionFeed(outputDirectory: output)
        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "Which blue?", updatedAt: Date().addingTimeInterval(-60)), id: id, in: output)
        #expect(feed.pendingReplies().isEmpty)

        try SessionInbox.appendReply(PinReply(index: 1, text: "The brand one"), id: id, in: output)
        let pending = feed.pendingReplies()
        #expect(pending.count == 1)
        let item = try #require(pending.first)
        #expect(item.sessionID == id)
        #expect(item.reply.index == 1)
        #expect(item.reply.text == "The brand one")

        feed.consume(item.reply, sessionID: item.sessionID)
        #expect(feed.pendingReplies().isEmpty)
        let pin = try #require(LoopHarness.pin(1, of: id, in: output))
        #expect(pin.state == .answered)
        #expect(pin.reply == "The brand one")
    }

    @Test func repliesOnlyCountForOpenQuestions() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let id = try AgentFixtures.writeSession(to: output)
        let feed = SessionFeed(outputDirectory: output)

        try SessionInbox.updatePin(PinStatus(index: 1, state: .resolved, note: "Done", updatedAt: Date().addingTimeInterval(-60)), id: id, in: output)
        try SessionInbox.appendReply(PinReply(index: 1, text: "late reply", at: Date().addingTimeInterval(-30)), id: id, in: output)
        #expect(feed.pendingReplies().isEmpty)

        // A reply older than the question answers an earlier one (the agent re-asked). Dates are
        // stored as whole-second ISO 8601, so "older" here is well clear of the same second.
        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "Again?"), id: id, in: output)
        #expect(feed.pendingReplies().isEmpty)
        try SessionInbox.appendReply(PinReply(index: 1, text: "new reply"), id: id, in: output)
        #expect(feed.pendingReplies().map(\.reply.text) == ["new reply"])
    }

    @Test func repliesComeFromEverySessionOldestFirst() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let old = try AgentFixtures.writeSession(id: "20200101-000000-aaaa", to: output)
        let fresh = try AgentFixtures.writeSession(to: output)
        let asked = Date().addingTimeInterval(-60)
        for id in [old, fresh] {
            try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "?", updatedAt: asked), id: id, in: output)
        }
        try SessionInbox.appendReply(PinReply(index: 1, text: "second", at: Date().addingTimeInterval(-10)), id: old, in: output)
        try SessionInbox.appendReply(PinReply(index: 1, text: "first", at: Date().addingTimeInterval(-20)), id: fresh, in: output)

        let pending = SessionFeed(outputDirectory: output).pendingReplies()
        #expect(pending.map(\.sessionID) == [fresh, old])
        #expect(pending.map(\.reply.text) == ["first", "second"])
    }
}

// MARK: CLI

@Suite struct PinCommandTests {
    @Test func parsesPerPinCommands() throws {
        #expect(try Command.parse(["resolve", "latest", "2", "Edited", "X"]).command
            == .resolve(sessionID: "latest", pin: 2, summary: "Edited X"))
        #expect(try Command.parse(["resolve", "abc", "1"]).command == .resolve(sessionID: "abc", pin: 1, summary: nil))
        #expect(try Command.parse(["dismiss", "abc", "3"]).command == .dismiss(sessionID: "abc", pin: 3, reason: nil))
        #expect(try Command.parse(["dismiss", "abc", "3", "Already", "done"]).command
            == .dismiss(sessionID: "abc", pin: 3, reason: "Already done"))
        #expect(try Command.parse(["ask", "abc", "1", "why?", "--wait", "5"]).command
            == .ask(sessionID: "abc", pin: 1, question: "why?", wait: 5))
        #expect(try Command.parse(["ask", "abc", "1", "which", "blue?"]).command
            == .ask(sessionID: "abc", pin: 1, question: "which blue?", wait: 120))
        #expect(try Command.parse(["ask", "--wait", "2.5", "abc", "1", "why?"]).command
            == .ask(sessionID: "abc", pin: 1, question: "why?", wait: 2.5))
        #expect(try Command.parse(["resolve", "abc", "1", "--dir", "x/.annotate"]).directory == "x/.annotate")
        #expect(try Command.parse(["ack", "latest", "2"]).command == .acknowledge(sessionID: "latest", pins: [2]))
        #expect(try Command.parse(["acknowledge", "abc", "1", "3"]).command == .acknowledge(sessionID: "abc", pins: [1, 3]))
    }

    @Test func ackCommandRecordsThePins() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let id = try AgentFixtures.writeSession(to: output)

        let invocation = try Command.parse(["ack", "latest", "1", "--dir", output.path])
        #expect(await Command.execute(invocation) == 0)
        #expect(SessionInbox.readStatus(id: id, in: output)?.acknowledged == [1])
    }

    @Test func rejectsBadPins() {
        #expect(throws: Command.ParseError.invalidPin("0")) { try Command.parse(["resolve", "latest", "0"]) }
        #expect(throws: Command.ParseError.invalidPin("x")) { try Command.parse(["dismiss", "latest", "x"]) }
        #expect(throws: Command.ParseError.invalidPin("-1")) { try Command.parse(["resolve", "latest", "-1"]) }
        #expect(throws: Command.ParseError.invalidPin("x")) { try Command.parse(["ask", "latest", "x", "why?"]) }
        #expect(throws: Command.ParseError.missingValue("--wait")) { try Command.parse(["ask", "latest", "1", "why?", "--wait"]) }
        #expect(throws: (any Error).self) { try Command.parse(["ask", "latest", "1"]) }
        #expect(throws: (any Error).self) { try Command.parse(["resolve", "latest"]) }
        #expect(throws: Command.ParseError.invalidPin("0")) { try Command.parse(["ack", "latest", "0"]) }
        #expect(throws: (any Error).self) { try Command.parse(["ack", "latest"]) }
    }

    @Test func replyLineNamesThePinAndText() {
        let line = Command.replyLine(sessionID: "s1", reply: PinReply(index: 2, text: "The brand one"))
        #expect(line.contains("pin 2"))
        #expect(line.contains("s1"))
        #expect(line.contains("The brand one"))
        #expect(line.contains("annotate resolve"))
    }
}

// MARK: Device mirror replies

@Suite struct DeviceMirrorReplyTests {
    static let app = DeviceMirrorTests.app

    static func remoteReplies(_ id: String) -> String {
        "\(DeviceMirror.remoteRoot)/\(SessionWriter.sessionsFolder)/\(id)/\(SessionInbox.repliesFile)"
    }

    static func localReplies(_ id: String, _ checkout: Checkout) -> Data? {
        try? Data(contentsOf: SessionInbox.sessionDirectory(id, in: checkout.output).appendingPathComponent(SessionInbox.repliesFile))
    }

    @Test func pullsRepliesWhileAQuestionIsOpen() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: [Self.app])
        let id = try DeviceMirrorTests.deviceSession(installFile: checkout.installFile, in: bridge)
        let mirror = DeviceMirrorTests.mirror(checkout, bridge)
        let start = Date()
        await mirror.tick(now: start)
        #expect(SessionInbox.sessionIDs(in: checkout.output) == [id])

        let one = try AnnotationSession.encoder.encode([PinReply(index: 1, text: "The brand one")])
        bridge.put(one, at: Self.remoteReplies(id), app: Self.app)

        // No question open: replies stay on the device
        try SessionInbox.updatePin(PinStatus(index: 1, state: .resolved, note: "Done"), id: id, in: checkout.output)
        await mirror.tick(now: start.addingTimeInterval(1))
        #expect(Self.localReplies(id, checkout) == nil)

        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "Which blue?"), id: id, in: checkout.output)
        await mirror.tick(now: start.addingTimeInterval(1.5))
        #expect(Self.localReplies(id, checkout) == one)
        #expect(SessionInbox.readReplies(id: id, in: checkout.output).map(\.text) == ["The brand one"])

        // Pulled at most every hotInterval
        let two = try AnnotationSession.encoder.encode([
            PinReply(index: 1, text: "The brand one"), PinReply(index: 1, text: "Actually darker")
        ])
        bridge.put(two, at: Self.remoteReplies(id), app: Self.app)
        await mirror.tick(now: start.addingTimeInterval(1.5 + DeviceMirror.hotInterval / 2))
        #expect(Self.localReplies(id, checkout) == one)
        await mirror.tick(now: start.addingTimeInterval(1.5 + DeviceMirror.hotInterval))
        #expect(Self.localReplies(id, checkout) == two)
    }

    @Test func aFinalSessionStaysTrackedUntilItsQuestionIsAnswered() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: [Self.app])
        let id = try DeviceMirrorTests.deviceSession(installFile: checkout.installFile, in: bridge)
        let mirror = DeviceMirrorTests.mirror(checkout, bridge)
        let start = Date()
        await mirror.tick(now: start)

        // The agent reported done, then asked
        try SessionInbox.writeStatus(SessionStatus(state: .done, message: "Edited X.swift"), id: id, in: checkout.output)
        try SessionInbox.updatePin(PinStatus(index: 1, state: .question, note: "Which blue?"), id: id, in: checkout.output)
        let replies = try AnnotationSession.encoder.encode([PinReply(index: 1, text: "The brand one")])
        bridge.put(replies, at: Self.remoteReplies(id), app: Self.app)
        await mirror.tick(now: start.addingTimeInterval(1))
        #expect(Self.localReplies(id, checkout) == replies)

        // Answered: the final status goes to the device once more, then the session is dropped
        let reply = try #require(SessionFeed(outputDirectory: checkout.output).pendingReplies().first)
        SessionFeed(outputDirectory: checkout.output).consume(reply.reply, sessionID: id)
        await mirror.tick(now: start.addingTimeInterval(2))
        let remoteStatus = "\(DeviceMirror.remoteRoot)/\(SessionWriter.sessionsFolder)/\(id)/\(SessionInbox.statusFile)"
        let decode = { try bridge.file(remoteStatus, app: Self.app).map { try AnnotationSession.decoder.decode(SessionStatus.self, from: $0) } }
        #expect(try decode()?.pins?.first?.state == .answered)

        try SessionInbox.writeStatus(SessionStatus(state: .failed, message: "late"), id: id, in: checkout.output)
        await mirror.tick(now: start.addingTimeInterval(3))
        #expect(try decode()?.state == .done)
    }
}

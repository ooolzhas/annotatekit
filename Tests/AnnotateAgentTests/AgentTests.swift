// The Mac side: argument parsing, session discovery/claiming, the channel MCP server's JSON-RPC
// conversation (initialize, push, tools), and headless-run output parsing.

import AnnotateCore
import Foundation
import Testing
@testable import AnnotateAgent

final class Sink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String: Any]] = []

    func append(_ data: Data) {
        for line in data.split(separator: 0x0A) {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            lock.lock()
            storage.append(object)
            lock.unlock()
        }
    }

    var messages: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

enum AgentFixtures {
    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("annotate-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func writeSession(id: String = SessionWriter.makeSessionID(), to output: URL, withImages: Bool = true, app: AppInfo = AppInfo()) throws -> String {
        let screen = Screen(
            index: 1, capturedAt: Date(), size: AnnotationSize(width: 402, height: 874),
            image: "screens/1.png", annotatedImage: "screens/1-annotated.png"
        )
        let pin = Annotation(index: 1, kind: .point, comment: "more space", frame: AnnotationRect(x: 10, y: 10, width: 44, height: 44), crop: "crops/1.png")
        let session = AnnotationSession(
            id: id, createdAt: Date(), app: app,
            device: DeviceInfo(model: "iPhone", systemName: "iOS", systemVersion: "26.0", isSimulator: true,
                               screen: AnnotationSize(width: 402, height: 874), scale: 3, colorScheme: "light",
                               contentSize: "L", orientation: "portrait"),
            screens: [screen], annotations: [pin]
        )
        let images = withImages ? ["screens/1-annotated.png": Data([0x89, 0x50]), "crops/1.png": Data([0x89])] : [:]
        try SessionWriter.write(SessionBundle(session: session, images: images), prompt: "PROMPT \(id)\n", to: output)
        return id
    }

    static func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

@Suite struct CommandParsingTests {
    @Test func parsesEveryCommand() throws {
        #expect(try Command.parse([]).command == .help)
        #expect(try Command.parse(["mcp"]).command == .mcp)
        #expect(try Command.parse(["watch", "--once"]).command == .watch(once: true))
        #expect(try Command.parse(["list", "--dir", "x/.annotate"]) == Command.Invocation(command: .list, directory: "x/.annotate"))
        #expect(try Command.parse(["run"]).command == .run(fresh: false, permissionMode: "acceptEdits", claudeArguments: []))
        #expect(try Command.parse(["run", "--fresh", "--permission-mode", "auto", "--", "--model", "opus"]).command
            == .run(fresh: true, permissionMode: "auto", claudeArguments: ["--model", "opus"]))
        #expect(try Command.parse(["status", "latest", "done", "Edited", "HomeView.swift"]).command
            == .status(sessionID: "latest", state: .done, message: "Edited HomeView.swift"))
        #expect(try Command.parse(["status", "abc", "working"]).command == .status(sessionID: "abc", state: .working, message: nil))
        #expect(try Command.parse(["watch"]).devices)
        let noDevice = try Command.parse(["--no-device", "mcp"])
        #expect(noDevice.command == .mcp)
        #expect(!noDevice.devices)
    }

    @Test func rejectsBadInput() {
        #expect(throws: Command.ParseError.unknown("frobnicate")) { try Command.parse(["frobnicate"]) }
        #expect(throws: Command.ParseError.invalidState("delivered")) { try Command.parse(["status", "x", "delivered"]) }
        #expect(throws: Command.ParseError.missingValue("--dir")) { try Command.parse(["list", "--dir"]) }
        #expect(throws: Command.ParseError.unknown("--nope")) { try Command.parse(["mcp", "--nope"]) }
    }
}

@Suite struct SessionFeedTests {
    @Test func onlySessionsAfterCutoffAreNew() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let old = try AgentFixtures.writeSession(id: "20200101-000000-aaaa", to: output)
        let fresh = try AgentFixtures.writeSession(to: output)
        let feed = SessionFeed(outputDirectory: output)
        #expect(feed.pending() == [fresh])
        #expect(feed.resolve("latest") == fresh)
        #expect(feed.resolve(nil) == fresh)
        #expect(feed.resolve(old) == old)
    }

    @Test func rejectsPathLikeSessionIDs() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let feed = SessionFeed(outputDirectory: output)
        #expect(feed.resolve("../../etc") == nil)
        #expect(feed.resolve("a/b") == nil)
        #expect(feed.resolve(".hidden") == nil)
        #expect(feed.resolve("20261028-141502-a1b2") == "20261028-141502-a1b2")
        #expect(SessionInbox.isSafeRelativePath("crops/1.png"))
        #expect(!SessionInbox.isSafeRelativePath("../secret.png"))
        #expect(!SessionInbox.isSafeRelativePath("/etc/passwd"))
    }

    @Test func claimingIsExclusiveAcrossConsumers() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let id = try AgentFixtures.writeSession(to: output)
        let first = SessionFeed(outputDirectory: output)
        let second = SessionFeed(outputDirectory: output)
        #expect(first.claimPending(as: .delivered) == [id])
        #expect(second.claimPending(as: .delivered).isEmpty)
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .delivered)
    }

    @Test func outputDirectoryDefaultsToProjectRoot() throws {
        let root = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let nested = root.appendingPathComponent("App/Views")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let resolved = SessionFeed.outputDirectory(explicit: nil, workingDirectory: nested.path)
        #expect(resolved.standardizedFileURL.path == root.appendingPathComponent(".annotate").standardizedFileURL.path)
        let explicit = SessionFeed.outputDirectory(explicit: "custom", workingDirectory: root.path)
        #expect(explicit.path == root.appendingPathComponent("custom").standardizedFileURL.path)
    }
}

@Suite struct ChannelServerTests {
    func makeServer(_ output: URL) -> (ChannelServer, Sink) {
        let sink = Sink()
        let server = ChannelServer(feed: SessionFeed(outputDirectory: output)) { sink.append($0) }
        return (server, sink)
    }

    func initialize(_ server: ChannelServer, client: String = "claude-code") async {
        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2026-07-28", "clientInfo": ["name": client, "version": "2.1"]]
        ]))
        await server.handle(AgentFixtures.json(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    }

    @Test func initializeDeclaresChannelAndTools() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = makeServer(output)
        await initialize(server)

        let response = try #require(sink.messages.first)
        #expect(response["id"] as? Int == 1)
        let result = try #require(response["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        let capabilities = try #require(result["capabilities"] as? [String: Any])
        let experimental = try #require(capabilities["experimental"] as? [String: Any])
        #expect(experimental["claude/channel"] != nil)
        #expect(capabilities["tools"] != nil)
        #expect((result["instructions"] as? String)?.contains("annotation_status") == true)

        await server.handle(AgentFixtures.json(["jsonrpc": "2.0", "id": 2, "method": "tools/list"]))
        let tools = try #require((sink.messages.last?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == [
            "get_annotation_session", "annotation_status", "list_annotation_sessions",
            "annotation_wait", "annotation_acknowledge", "annotation_resolve", "annotation_dismiss", "annotation_ask"
        ])
    }

    @Test func pushesEachNewSessionOnceAfterInitialization() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)

        await server.poll()
        #expect(sink.messages.isEmpty) // not initialized yet

        await initialize(server) // initialized triggers a poll
        await server.poll()
        let pushes = sink.messages.filter { $0["method"] as? String == "notifications/claude/channel" }
        #expect(pushes.count == 1)
        let params = try #require(pushes.first?["params"] as? [String: Any])
        #expect((params["content"] as? String)?.contains("PROMPT \(id)") == true)
        let meta = try #require(params["meta"] as? [String: String])
        #expect(meta["session_id"] == id)
        #expect(meta["session_dir"]?.hasSuffix("/sessions/\(id)") == true)
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .delivered)
    }

    @Test func getSessionReturnsPromptAndImagesAndMarksReceived() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await initialize(server)

        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": ["name": "get_annotation_session", "arguments": ["session_id": id]]
        ]))
        let result = try #require(sink.messages.last?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == "PROMPT \(id)\n")
        let images = content.filter { $0["type"] as? String == "image" }
        #expect(images.count == 2)
        #expect(images.first?["mimeType"] as? String == "image/png")
        #expect(images.first?["data"] as? String == Data([0x89, 0x50]).base64EncodedString())
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .received)
    }

    @Test func statusToolWritesWhatTheAppReads() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await initialize(server)

        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": 4, "method": "tools/call",
            "params": ["name": "annotation_status", "arguments": ["session_id": id, "state": "done", "message": "Edited HomeView.swift"]]
        ]))
        #expect((sink.messages.last?["result"] as? [String: Any])?["isError"] == nil)
        let status = try #require(SessionInbox.readStatus(id: id, in: output))
        #expect(status.state == .done)
        #expect(status.message == "Edited HomeView.swift")

        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": 5, "method": "tools/call",
            "params": ["name": "annotation_status", "arguments": ["session_id": id, "state": "delivered"]]
        ]))
        #expect((sink.messages.last?["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test func unknownRequestsGetMethodNotFound() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = makeServer(output)
        await server.handle(AgentFixtures.json(["jsonrpc": "2.0", "id": "x", "method": "resources/list"]))
        let error = try #require(sink.messages.last?["error"] as? [String: Any])
        #expect(error["code"] as? Int == -32601)
        await server.handle(AgentFixtures.json(["jsonrpc": "2.0", "method": "notifications/cancelled"]))
        #expect(sink.messages.count == 1)
    }
}

@Suite struct HeadlessRunnerTests {
    @Test func buildsClaudeArguments() {
        let runner = HeadlessRunner(workingDirectory: URL(fileURLWithPath: "/p"), extraArguments: ["--model", "opus"])
        #expect(runner.arguments(prompt: "do it", resume: nil)
            == ["claude", "-p", "do it", "--permission-mode", "acceptEdits", "--output-format", "json", "--model", "opus"])
        #expect(runner.arguments(prompt: "x", resume: "abc").contains("--resume"))
    }

    @Test func parsesJSONOutput() {
        let json = Data(#"{"type":"result","result":"Changed padding.\nSummary: Edited HomeView.swift","session_id":"s1","is_error":false}"#.utf8)
        let parsed = HeadlessRunner.parse(output: json)
        #expect(parsed.sessionID == "s1")
        #expect(parsed.isError == false)
        #expect(HeadlessRunner.summary(from: parsed.text) == "Edited HomeView.swift")
    }

    @Test func summaryTakesLastLineAndTruncates() {
        #expect(HeadlessRunner.summary(from: "a\n\n**Summary:** Tightened the card  \n") == "Tightened the card")
        #expect(HeadlessRunner.summary(from: String(repeating: "x", count: 200), limit: 10) == "xxxxxxxxx…")
        #expect(HeadlessRunner.summary(from: "  \n ") == nil)
        #expect(HeadlessRunner.summary(from: nil) == nil)
    }

    @Test func watchLineTellsTheAgentWhatToDo() {
        let line = Command.watchLine(sessionID: "s1", directory: URL(fileURLWithPath: "/p/.annotate/sessions/s1"))
        #expect(line.contains("/p/.annotate/sessions/s1/prompt.md"))
        #expect(line.contains("annotate status s1 done"))
    }
}

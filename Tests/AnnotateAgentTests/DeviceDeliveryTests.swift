// Device delivery and presence on the Mac side: the mirror copies only this checkout's bundles off
// a (fake) device, rewrites their paths, and sends status and presence back; bundle-id patterns;
// the hub lease; agent naming; and the channel server's rule that a push counts only once Claude
// is seen answering one.

import AnnotateCore
import Foundation
import Testing
@testable import AnnotateAgent

/// An in-memory device: one app container per (device, app), files keyed by container path.
final class FakeBridge: DeviceBridge, @unchecked Sendable {
    private let lock = NSLock()
    private var containers: [String: [String: (data: Data, modified: Date)]] = [:]
    private(set) var pushed: [String] = []
    /// Apps listed through `files`, in call order.
    private(set) var listed: [String] = []
    let deviceID = "device-1"
    let apps: [String]

    init(apps: [String]) {
        self.apps = apps
    }

    private func key(_ app: String) -> String { "\(deviceID)/\(app)" }

    func put(_ data: Data, at path: String, app: String, modified: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        containers[key(app), default: [:]][path] = (data, modified)
    }

    func file(_ path: String, app: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return containers[key(app)]?[path]?.data
    }

    /// Copies a bundle written by SessionWriter into the fake container, as the app would on a device.
    func putSession(from output: URL, id: String, app: String) throws {
        let sessionDir = SessionInbox.sessionDirectory(id, in: output)
        let enumerator = FileManager.default.enumerator(at: sessionDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard !url.hasDirectoryPath, let data = try? Data(contentsOf: url) else { continue }
            let relative = ProjectRoot.relativePath(of: url.path, to: sessionDir)
            put(data, at: "\(DeviceMirror.remoteRoot)/sessions/\(id)/\(relative)", app: app)
        }
    }

    func devices() async throws -> [RemoteDevice] { [RemoteDevice(id: deviceID, name: "Test iPhone")] }

    func developerApps(on device: String) async throws -> [String] { apps }

    private func container(_ app: String) -> [String: (data: Data, modified: Date)] {
        lock.withLock { containers[key(app)] ?? [:] }
    }

    func files(on device: String, app: String, path: String) async throws -> [RemoteFile] {
        lock.withLock { listed.append(app) }
        let prefix = path + "/"
        let entries = container(app).filter { $0.key.hasPrefix(prefix) }
        guard !entries.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        return entries.map { RemoteFile(path: String($0.key.dropFirst(prefix.count)), modified: $0.value.modified) }
    }

    func copy(from path: String, on device: String, app: String, to local: URL) async throws {
        let container = container(app)
        if let file = container[path] {
            try file.data.write(to: local)
            return
        }
        let children = container.filter { $0.key.hasPrefix(path + "/") }
        guard !children.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        for (childPath, file) in children {
            let target = local.appendingPathComponent(String(childPath.dropFirst(path.count + 1)))
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: target)
        }
    }

    func copy(_ local: URL, to path: String, on device: String, app: String) async throws {
        put(try Data(contentsOf: local), at: path, app: app)
        lock.withLock { pushed.append(path) }
    }
}

/// A checkout on disk (`.git` + one source file) whose `.annotate` the mirror fills.
struct Checkout {
    let root: URL
    var output: URL { root.appendingPathComponent(".annotate", isDirectory: true) }
    var installFile: String { root.appendingPathComponent("App/MyApp.swift").path }

    init() throws {
        root = try AgentFixtures.tempDir()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App"), withIntermediateDirectories: true)
        try Data("// app".utf8).write(to: URL(fileURLWithPath: installFile))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite struct DeviceMirrorTests {
    static let app = "com.example.app"

    /// A session as the app on the device would write it, with its prompt naming the container path.
    static func deviceSession(installFile: String?, bundleID: String = app, in bridge: FakeBridge) throws -> String {
        let scratch = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let id = try AgentFixtures.writeSession(to: scratch, app: AppInfo(bundleID: bundleID, installFile: installFile))
        let remoteDir = "/var/mobile/Containers/Data/Application/ABC/Documents/.annotate/sessions/\(id)"
        let prompt = "Session: \(remoteDir)\nScreen 1 — annotated \(remoteDir)/screens/1-annotated.png\n"
        try Data(prompt.utf8).write(to: SessionInbox.sessionDirectory(id, in: scratch).appendingPathComponent(SessionInbox.promptFile))
        try bridge.putSession(from: scratch, id: id, app: bundleID)
        return id
    }

    static func mirror(_ checkout: Checkout, _ bridge: FakeBridge, bundleIDs: [String] = []) -> DeviceMirror {
        DeviceMirror(
            outputDirectory: checkout.output,
            cutoffID: SessionWriter.makeSessionID(date: Date().addingTimeInterval(-120), suffix: ""),
            bridge: bridge,
            projectBundleIDs: bundleIDs
        )
    }

    @Test func copiesThisCheckoutsSessionAndRelocatesItsPrompt() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: [Self.app])
        let id = try Self.deviceSession(installFile: checkout.installFile, in: bridge)

        await Self.mirror(checkout, bridge).tick()

        #expect(SessionInbox.pendingSessionIDs(in: checkout.output) == [id])
        let prompt = try SessionInbox.loadPrompt(id: id, in: checkout.output)
        let local = SessionInbox.sessionDirectory(id, in: checkout.output).path
        #expect(prompt.contains("Session: \(local)\n"))
        #expect(prompt.contains("\(local)/screens/1-annotated.png"))
        #expect(!prompt.contains("/var/mobile"))
        #expect(FileManager.default.fileExists(atPath: SessionInbox.sessionDirectory(id, in: checkout.output).appendingPathComponent("crops/1.png").path))
    }

    @Test func coldBuildsThatNeverAnswerBackOff() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: ["com.cold.app"])
        let mirror = Self.mirror(checkout, bridge)
        let start = Date()
        // 60 s, then 120 s after one miss, then 240 s after two
        for offset in [0, 61, 121, 300, 362] as [TimeInterval] {
            await mirror.tick(now: start.addingTimeInterval(offset))
        }
        #expect(bridge.listed == ["com.cold.app", "com.cold.app", "com.cold.app"])
    }

    @Test func repeatColdPollsGoOnePerTick() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: ["com.cold.one", "com.cold.two"])
        let mirror = Self.mirror(checkout, bridge)
        let start = Date()
        await mirror.tick(now: start)
        #expect(bridge.listed.count == 2) // every app's first listing, so a beacon is never kept waiting
        await mirror.tick(now: start.addingTimeInterval(121))
        #expect(bridge.listed.count == 3)
        await mirror.tick(now: start.addingTimeInterval(122))
        #expect(bridge.listed.count == 4)
    }

    @Test func prunesTheMacCopyPastTheHistoryWindow() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let old = Date().addingTimeInterval(-SessionInbox.historyWindow - 3600)
        for minute in 0..<(DeviceMirror.keptSessions + 5) {
            let id = SessionWriter.makeSessionID(date: old.addingTimeInterval(Double(minute) * 60))
            try AgentFixtures.writeSession(id: id, to: checkout.output, withImages: false)
        }
        let bridge = FakeBridge(apps: [Self.app])
        let id = try Self.deviceSession(installFile: checkout.installFile, in: bridge)

        await Self.mirror(checkout, bridge).tick()

        let kept = SessionInbox.sessionIDs(in: checkout.output)
        #expect(kept.count == DeviceMirror.keptSessions)
        #expect(kept.last == id)
    }

    #if os(macOS)
    @Test func parsesDevicectlDatesWithAndWithoutFractions() {
        let whole = DeviceCtlBridge.date("2026-10-28T22:14:30Z")
        #expect(whole != nil)
        #expect(DeviceCtlBridge.date("2026-10-28T22:14:30.000Z") == whole)
        #expect(DeviceCtlBridge.date("yesterday") == nil)
    }
    #endif

    @Test func leavesAnotherCheckoutsSessionAlone() async throws {
        let mine = try Checkout()
        let other = try Checkout()
        defer { mine.remove(); other.remove() }
        let bridge = FakeBridge(apps: [Self.app])
        _ = try Self.deviceSession(installFile: other.installFile, in: bridge)

        await Self.mirror(mine, bridge).tick()

        #expect(SessionInbox.sessionIDs(in: mine.output).isEmpty)
    }

    @Test func oldBuildsFallBackToTheProjectsBundleIDs() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: [Self.app, "com.other.app"])
        let mine = try Self.deviceSession(installFile: nil, in: bridge)
        _ = try Self.deviceSession(installFile: nil, bundleID: "com.other.app", in: bridge)

        await Self.mirror(checkout, bridge, bundleIDs: ["com.example.$(SUFFIX)"]).tick()

        #expect(SessionInbox.sessionIDs(in: checkout.output) == [mine])
    }

    @Test func skipsSessionsSentBeforeTheWatcherStarted() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: [Self.app])
        let old = SessionWriter.makeSessionID(date: Date().addingTimeInterval(-3600))
        let scratch = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try AgentFixtures.writeSession(id: old, to: scratch, app: AppInfo(bundleID: Self.app, installFile: checkout.installFile))
        try bridge.putSession(from: scratch, id: old, app: Self.app)

        await Self.mirror(checkout, bridge).tick()

        #expect(SessionInbox.sessionIDs(in: checkout.output).isEmpty)
    }

    @Test func forwardsStatusChangesToTheDevice() async throws {
        let checkout = try Checkout()
        defer { checkout.remove() }
        let bridge = FakeBridge(apps: [Self.app])
        let id = try Self.deviceSession(installFile: checkout.installFile, in: bridge)
        let mirror = Self.mirror(checkout, bridge)
        await mirror.tick()

        let remote = "\(DeviceMirror.remoteRoot)/sessions/\(id)/status.json"
        #expect(SessionInbox.claim(id: id, in: checkout.output, as: .delivered))
        await mirror.tick()
        #expect(try bridge.file(remote, app: Self.app).map { try AnnotationSession.decoder.decode(SessionStatus.self, from: $0) }?.state == .delivered)

        try SessionInbox.writeStatus(SessionStatus(state: .done, message: "Edited X.swift"), id: id, in: checkout.output)
        await mirror.tick()
        let done = try bridge.file(remote, app: Self.app).map { try AnnotationSession.decoder.decode(SessionStatus.self, from: $0) }
        #expect(done?.state == .done)
        #expect(done?.message == "Edited X.swift")

        let pushes = bridge.pushed.filter { $0 == remote }.count
        await mirror.tick()
        #expect(bridge.pushed.filter { $0 == remote }.count == pushes) // unchanged status isn't re-sent
    }

    @Test func pushesPresenceOnlyToThisCheckoutsOpenApp() async throws {
        let checkout = try Checkout()
        let other = try Checkout()
        defer { checkout.remove(); other.remove() }
        let bridge = FakeBridge(apps: [Self.app, "com.other.app"])
        let encode = { (file: String) in try AnnotationSession.encoder.encode(AppBeacon(bundleID: nil, installFile: file)) }
        bridge.put(try encode(checkout.installFile), at: "\(DeviceMirror.remoteRoot)/app.json", app: Self.app)
        bridge.put(try encode(other.installFile), at: "\(DeviceMirror.remoteRoot)/app.json", app: "com.other.app")
        try AgentPresenceFile.write(AgentPresence(agent: "Claude Code", mode: .push, via: "watch"), in: checkout.output)

        await Self.mirror(checkout, bridge).tick()

        let presencePath = "\(DeviceMirror.remoteRoot)/agent.json"
        #expect(bridge.file(presencePath, app: Self.app) != nil)
        #expect(bridge.file(presencePath, app: "com.other.app") == nil)
    }

    @Test func listingsYieldOnlyCompleteSessions() {
        let files = [
            RemoteFile(path: "latest"),
            RemoteFile(path: "sessions/20261029-010101-aaaa/session.json"),
            RemoteFile(path: "sessions/20261029-010101-aaaa/prompt.md"),
            RemoteFile(path: "sessions/20261029-000000-bbbb/prompt.md"),
            RemoteFile(path: "sessions/../session.json"),
            RemoteFile(path: "sessions/20261028-235959-cccc/session.json")
        ]
        #expect(DeviceMirror.completeSessionIDs(in: files) == ["20261028-235959-cccc", "20261029-010101-aaaa"])
    }
}

@Suite struct BundleIDPatternTests {
    @Test func variablesMatchAnything() {
        #expect(BundleIDPattern.matches("com.example.Notes.dev", anyOf: ["com.example.Notes.dev"]))
        #expect(BundleIDPattern.matches("com.example.Notes.dev", anyOf: ["com.example.Notes$(BUNDLE_SUFFIX)"]))
        #expect(BundleIDPattern.matches("com.example.app", anyOf: ["${PREFIX}.app"]))
        #expect(!BundleIDPattern.matches("com.example.Notes.dev", anyOf: ["com.example.Notes"]))
        #expect(!BundleIDPattern.matches("comXexample", anyOf: ["com.example"]))
    }

    @Test func readsPbxprojAndXcodeGenValues() {
        let pbxproj = """
            PRODUCT_BUNDLE_IDENTIFIER = com.example.Notes.dev;
            PRODUCT_BUNDLE_IDENTIFIER = "com.example.$(TARGET_NAME)";
            """
        #expect(BundleIDPattern.values(in: pbxproj) == ["com.example.Notes.dev", "com.example.$(TARGET_NAME)"])
        #expect(BundleIDPattern.values(in: "    PRODUCT_BUNDLE_IDENTIFIER: com.example.yml") == ["com.example.yml"])
    }
}

@Suite struct HubLeaseTests {
    @Test func oneHubUntilItGoesQuiet() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let now = Date()
        #expect(HubLease.acquire(pid: 100, in: output, now: now))
        #expect(!HubLease.acquire(pid: 200, in: output, now: now.addingTimeInterval(1)))
        #expect(HubLease.acquire(pid: 100, in: output, now: now.addingTimeInterval(2)))
        #expect(HubLease.acquire(pid: 200, in: output, now: now.addingTimeInterval(2 + HubLease.staleAfter + 1)))
        HubLease.release(pid: 100, in: output) // not the holder any more: no effect
        #expect(!HubLease.acquire(pid: 300, in: output, now: now.addingTimeInterval(2 + HubLease.staleAfter + 2)))
        HubLease.release(pid: 200, in: output)
        #expect(HubLease.acquire(pid: 300, in: output, now: now.addingTimeInterval(2 + HubLease.staleAfter + 3)))
    }

    @Test func hubPublishesTheMergedPresence() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let runtime = AgentRuntime(outputDirectory: output, mirror: nil) {
            AgentPresence(agent: "Claude Code", mode: .push, via: "watch")
        }
        await runtime.beat()
        #expect(await runtime.isHub)
        #expect(AgentPresenceFile.read(in: output)?.agent == "Claude Code")

        await runtime.stop()
        #expect(AgentPresenceFile.read(in: output) == nil)
        #expect(AgentPresenceFile.liveHeartbeats(in: output).isEmpty)
    }
}

@Suite struct AgentIdentityTests {
    @Test func namesMCPClients() {
        #expect(AgentIdentity.name(forClient: "claude-code") == "Claude Code")
        #expect(AgentIdentity.name(forClient: "cursor-vscode") == "Cursor")
        #expect(AgentIdentity.name(forClient: "codex-mcp-client") == "Codex")
        #expect(AgentIdentity.name(forClient: "Zed") == "Zed")
        #expect(AgentIdentity.name(forClient: nil) == AgentIdentity.fallbackName)
        #expect(AgentIdentity.isClaudeCode(client: "claude-code"))
        #expect(!AgentIdentity.isClaudeCode(client: "cursor-vscode"))
    }

    @Test func namesTheShellsAgent() {
        #expect(AgentIdentity.name(environment: ["CLAUDECODE": "1"], ancestors: ["zsh"]) == "Claude Code")
        #expect(AgentIdentity.name(environment: [:], ancestors: ["zsh", "node", "codex"]) == "Codex")
        #expect(AgentIdentity.name(environment: [:], ancestors: ["zsh", "Cursor Helper (Plugin)"]) == "Cursor")
        #expect(AgentIdentity.name(environment: [:], ancestors: ["zsh", "login"]) == nil)
    }
}

@Suite struct ChannelDeliveryTests {
    func makeServer(_ output: URL, ackTimeout: TimeInterval = 45) -> (ChannelServer, Sink) {
        let sink = Sink()
        let server = ChannelServer(feed: SessionFeed(outputDirectory: output), ackTimeout: ackTimeout) { sink.append($0) }
        return (server, sink)
    }

    func initialize(_ server: ChannelServer, client: String) async {
        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2026-07-28", "clientInfo": ["name": client]]
        ]))
        await server.handle(AgentFixtures.json(["jsonrpc": "2.0", "method": "notifications/initialized"]))
    }

    func pushes(_ sink: Sink) -> Int {
        sink.messages.filter { $0["method"] as? String == "notifications/claude/channel" }.count
    }

    @Test func otherClientsNeverClaim() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await initialize(server, client: "cursor-vscode")
        await server.poll()

        #expect(pushes(sink) == 0)
        #expect(SessionInbox.pendingSessionIDs(in: output) == [id])
        #expect(await server.presence().mode == .pull)
        #expect(await server.presence().agent == "Cursor")
    }

    @Test func anUnansweredPushIsHandedBack() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, sink) = makeServer(output, ackTimeout: 10)
        let id = try AgentFixtures.writeSession(to: output)
        await initialize(server, client: "claude-code")
        #expect(pushes(sink) == 1)
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .delivered)

        await server.poll(now: Date().addingTimeInterval(11))
        #expect(SessionInbox.pendingSessionIDs(in: output) == [id])
        let later = try AgentFixtures.writeSession(to: output)
        await server.poll(now: Date().addingTimeInterval(12))
        #expect(pushes(sink) == 1) // stopped pushing
        #expect(Set(SessionInbox.pendingSessionIDs(in: output)) == [id, later])
        #expect(await server.presence().mode == .pull)
    }

    @Test func anAnsweredPushConfirmsTheChannel() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let (server, _) = makeServer(output, ackTimeout: 10)
        let id = try AgentFixtures.writeSession(to: output)
        await initialize(server, client: "claude-code")
        await server.handle(AgentFixtures.json([
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": ["name": "get_annotation_session", "arguments": ["session_id": id]]
        ]))

        await server.poll(now: Date().addingTimeInterval(60))
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .received)
        let presence = await server.presence()
        #expect(presence.agent == "Claude Code")
        #expect(presence.mode == .push)
        #expect(presence.via == "channel")
    }

    @Test func anUnconfirmedChannelLeavesSessionsToAWatcher() async throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        try AgentPresenceFile.writeHeartbeat(AgentPresence(agent: "Claude Code", mode: .push, via: "watch"), pid: 4242, in: output)
        let (server, sink) = makeServer(output)
        let id = try AgentFixtures.writeSession(to: output)
        await initialize(server, client: "claude-code")

        #expect(pushes(sink) == 0)
        #expect(SessionInbox.pendingSessionIDs(in: output) == [id])
    }
}

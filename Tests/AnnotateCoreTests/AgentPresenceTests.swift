// Agent presence: which heartbeat the app shows when several agents listen, freshness by file
// date (so a dead process's heartbeat reads as gone), releasing an unanswered claim, and that
// bundles from builds before `installFile` still decode.

import Foundation
import Testing
@testable import AnnotateCore

@Suite struct AgentPresenceTests {
    private static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("annotate-presence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func age(_ url: URL, by seconds: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)], ofItemAtPath: url.path)
    }

    @Test func pushBeatsPullThenNewestWins() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let pullNew = AgentPresence(agent: "Cursor", mode: .pull, via: "mcp", updatedAt: new)
        let pushOld = AgentPresence(agent: "Claude Code", mode: .push, via: "watch", updatedAt: old)
        let pushNew = AgentPresence(agent: "Codex", mode: .push, via: "watch", updatedAt: new)
        #expect(AgentPresenceFile.merge([pullNew, pushOld]) == pushOld)
        #expect(AgentPresenceFile.merge([pushOld, pullNew, pushNew]) == pushNew)
        #expect(AgentPresenceFile.merge([]) == nil)
    }

    @Test func readsMergedFileOnlyWhileFresh() throws {
        let output = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let presence = AgentPresence(agent: "Claude Code", mode: .push, via: "watch")
        try AgentPresenceFile.write(presence, in: output)
        #expect(AgentPresenceFile.read(in: output)?.agent == "Claude Code")

        try Self.age(output.appendingPathComponent(AgentPresenceFile.fileName), by: AgentPresenceFile.staleAfter + 5)
        #expect(AgentPresenceFile.read(in: output) == nil)

        try AgentPresenceFile.write(nil, in: output)
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent(AgentPresenceFile.fileName).path))
    }

    @Test func liveHeartbeatsSkipStaleOnes() throws {
        let output = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        try AgentPresenceFile.writeHeartbeat(AgentPresence(agent: "Claude Code", mode: .push, via: "watch"), pid: 10, in: output)
        try AgentPresenceFile.writeHeartbeat(AgentPresence(agent: "Cursor", mode: .pull, via: "mcp"), pid: 11, in: output)
        try Self.age(AgentPresenceFile.heartbeatURL(pid: 10, in: output), by: AgentPresenceFile.staleAfter + 1)

        #expect(AgentPresenceFile.liveHeartbeats(in: output).map(\.agent) == ["Cursor"])
        AgentPresenceFile.removeHeartbeat(pid: 11, in: output)
        #expect(AgentPresenceFile.liveHeartbeats(in: output).isEmpty)
    }

    @Test func releaseUndoesOnlyAnUnansweredClaim() throws {
        let output = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let session = AnnotationSession(
            id: "20261029-010203-abcd", createdAt: Date(), app: AppInfo(),
            device: DeviceInfo(model: "iPhone", systemName: "iOS", systemVersion: "26.0", isSimulator: false,
                               screen: AnnotationSize(width: 393, height: 852), scale: 3, colorScheme: "dark",
                               contentSize: "L", orientation: "portrait"),
            screens: [], annotations: []
        )
        try SessionWriter.write(SessionBundle(session: session, images: [:]), prompt: "p", to: output)
        let id = session.id

        #expect(SessionInbox.claim(id: id, in: output, as: .delivered))
        #expect(SessionInbox.pendingSessionIDs(in: output).isEmpty)
        #expect(SessionInbox.release(id: id, in: output))
        #expect(SessionInbox.pendingSessionIDs(in: output) == [id])

        #expect(SessionInbox.claim(id: id, in: output, as: .delivered))
        try SessionInbox.writeStatus(SessionStatus(state: .working, message: "on it"), id: id, in: output)
        #expect(!SessionInbox.release(id: id, in: output))
        #expect(SessionInbox.readStatus(id: id, in: output)?.state == .working)
    }

    @Test func appInfoWithoutInstallFileStillDecodes() throws {
        let json = #"{"bundleID":"com.example.app","name":"Example","version":"1.0","build":"7"}"#
        let info = try AnnotationSession.decoder.decode(AppInfo.self, from: Data(json.utf8))
        #expect(info.bundleID == "com.example.app")
        #expect(info.installFile == nil)

        let withFile = AppInfo(bundleID: "a", installFile: "/Users/me/app/App.swift")
        let round = try AnnotationSession.decoder.decode(AppInfo.self, from: AnnotationSession.encoder.encode(withFile))
        #expect(round == withFile)
    }
}

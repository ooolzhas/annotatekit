// `annotate hook stop`: when Claude's turn ends, a Send this conversation worked on that the device
// still shows as in progress blocks the stop once, with instructions to report it. Pins on: scope by
// transcript, final and stale sessions, an open question as a legitimate pause, `stop_hook_active`
// letting the second stop through, unreadable input, and the CLI parse.

import AnnotateCore
import Foundation
import Testing
@testable import AnnotateAgent

@Suite struct StopHookTests {
    private static func session(_ output: URL, state: SessionStatus.State, message: String? = nil,
                                updatedAt: Date = Date(), pins: [PinStatus]? = nil) throws -> String {
        let id = try AgentFixtures.writeSession(to: output, withImages: false)
        try SessionInbox.writeStatus(SessionStatus(state: state, message: message, updatedAt: updatedAt, pins: pins), id: id, in: output)
        return id
    }

    private static func input(cwd: URL, transcript: URL, active: Bool = false) -> Data {
        let object: [String: Any] = [
            "session_id": "abc", "hook_event_name": "Stop", "cwd": cwd.path,
            "transcript_path": transcript.path, "stop_hook_active": active
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    @Test("an open Send from this conversation blocks the stop with how to report it")
    func blocksOnOwnOpenSession() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let id = try Self.session(output, state: .working, message: "All changes applied · Reinstalling")
        let transcript = output.appendingPathComponent("t.jsonl")
        try "{\"command\":\"annotate status \(id) working\"}".write(to: transcript, atomically: true, encoding: .utf8)

        let out = try #require(StopHook.run(input: Self.input(cwd: output, transcript: transcript),
                                            explicitDirectory: output.path, workingDirectory: output.path))
        let decision = try #require(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: String])
        #expect(decision["decision"] == "block")
        #expect(decision["reason"]?.contains(id) == true)
        #expect(decision["reason"]?.contains("annotate status <id> done") == true)
    }

    @Test("another conversation's open Send doesn't block this one")
    func ignoresSessionsNotInTranscript() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        _ = try Self.session(output, state: .working)
        let transcript = output.appendingPathComponent("t.jsonl")
        try "nothing about annotate here".write(to: transcript, atomically: true, encoding: .utf8)
        #expect(StopHook.run(input: Self.input(cwd: output, transcript: transcript),
                             explicitDirectory: output.path, workingDirectory: output.path) == nil)
    }

    @Test("the second stop goes through, so the hook can't trap a session")
    func stopHookActiveLetsItStop() {
        let open = [StopHook.OpenSession(id: "20261029-145913-ac25", state: .working, message: nil)]
        #expect(StopHook.blockReason(open: open, transcript: "20261029-145913-ac25", stopHookActive: true) == nil)
        #expect(StopHook.blockReason(open: open, transcript: "20261029-145913-ac25", stopHookActive: false) != nil)
    }

    @Test("final, stale and question-waiting sessions aren't open")
    func openSessionsSkipFinishedStaleAndWaiting() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let working = try Self.session(output, state: .received)
        _ = try Self.session(output, state: .done, message: "All set")
        _ = try Self.session(output, state: .working, updatedAt: Date().addingTimeInterval(-StopHook.trackingLimit - 60))
        _ = try Self.session(output, state: .working, pins: [PinStatus(index: 1, state: .question, note: "Which one?")])
        #expect(StopHook.openSessions(in: output).map(\.id) == [working])
    }

    @Test("a Send from before the app's tracking window isn't read, even with a fresh status")
    func openSessionsSkipOldSends() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let old = SessionWriter.makeSessionID(date: Date().addingTimeInterval(-3 * StopHook.trackingLimit))
        try AgentFixtures.writeSession(id: old, to: output, withImages: false)
        try SessionInbox.writeStatus(SessionStatus(state: .working), id: old, in: output)
        let recent = try Self.session(output, state: .working)
        #expect(StopHook.openSessions(in: output).map(\.id) == [recent])
    }

    @Test("the second stop goes through before the transcript is read")
    func stopHookActiveSkipsTheTranscript() throws {
        let output = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let id = try Self.session(output, state: .working)
        let transcript = output.appendingPathComponent("t.jsonl")
        try "annotate status \(id) working".write(to: transcript, atomically: true, encoding: .utf8)
        #expect(StopHook.run(input: Self.input(cwd: output, transcript: transcript, active: true),
                             explicitDirectory: output.path, workingDirectory: output.path) == nil)
    }

    @Test("no sessions folder or unreadable input lets Claude stop")
    func missingInputsNeverBlock() throws {
        let empty = try AgentFixtures.tempDir()
        defer { try? FileManager.default.removeItem(at: empty) }
        let missing = empty.appendingPathComponent("absent")
        #expect(StopHook.run(input: Data("not json".utf8), explicitDirectory: missing.path, workingDirectory: empty.path) == nil)
        #expect(StopHook.run(input: Data(), explicitDirectory: empty.path, workingDirectory: empty.path) == nil)
    }

    @Test func parsesHookStop() throws {
        #expect(try Command.parse(["hook", "stop"]).command == .hookStop)
        #expect(throws: Command.ParseError.self) { try Command.parse(["hook"]) }
        #expect(throws: Command.ParseError.self) { try Command.parse(["hook", "start"]) }
    }
}

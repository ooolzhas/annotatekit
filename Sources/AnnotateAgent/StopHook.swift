// `annotate hook stop`: a Claude Code Stop hook that keeps an agent from ending its turn while a
// Send it worked on still shows as in progress on the device. Without it, an agent that forgets
// `annotate status <id> done` (or finishes other work first) leaves the app narrating "working"
// until its one-hour tracking limit, though every change is already in.
// Scope: only sessions this conversation's transcript mentions, so two Claude sessions on one
// project never finish each other's Sends. Blocks once per stop (`stop_hook_active` is the second
// try) and never while a pin waits on the user's answer, which is a legitimate pause.

import AnnotateCore
import Foundation

public enum StopHook {
    /// The fields of Claude Code's Stop hook input this hook reads.
    public struct Input: Decodable, Equatable, Sendable {
        public var cwd: String?
        public var transcriptPath: String?
        public var stopHookActive: Bool?

        enum CodingKeys: String, CodingKey {
            case cwd
            case transcriptPath = "transcript_path"
            case stopHookActive = "stop_hook_active"
        }

        public init(cwd: String? = nil, transcriptPath: String? = nil, stopHookActive: Bool? = nil) {
            self.cwd = cwd
            self.transcriptPath = transcriptPath
            self.stopHookActive = stopHookActive
        }
    }

    /// A session the device still shows as in progress.
    public struct OpenSession: Equatable, Sendable {
        public var id: String
        public var state: SessionStatus.State
        public var message: String?
    }

    /// Past this age the app has stopped tracking a Send (`deliveryTrackingLimit`), so an open status
    /// no longer shows anywhere and isn't worth stopping for.
    static let trackingLimit: TimeInterval = 3600

    /// Claimed sessions whose status isn't final, updated within `trackingLimit`, with no pin waiting
    /// on the user's answer.
    public static func openSessions(in output: URL, now: Date = Date()) -> [OpenSession] {
        // Ids are send times and the app stops tracking an hour after the Send, so older folders
        // can't be open: skip them without reading their status (twice the limit covers clock skew
        // between the device and the Mac).
        let since = SessionWriter.makeSessionID(date: now.addingTimeInterval(-2 * trackingLimit), suffix: "")
        return SessionInbox.sessionIDs(in: output, since: since).compactMap { id in
            guard let status = SessionInbox.readStatus(id: id, in: output), !status.isFinal,
                  now.timeIntervalSince(status.updatedAt) <= trackingLimit,
                  !(status.pins ?? []).contains(where: { $0.state == .question }) else { return nil }
            return OpenSession(id: id, state: status.state, message: status.message)
        }
    }

    /// The reason to hand Claude when it should report before stopping, or nil to let it stop.
    public static func blockReason(open: [OpenSession], transcript: String, stopHookActive: Bool) -> String? {
        blockReason(open: open, stopHookActive: stopHookActive) { transcript.contains($0) }
    }

    /// `mentions` says whether the transcript contains a session id.
    public static func blockReason(open: [OpenSession], stopHookActive: Bool, mentions: (String) -> Bool) -> String? {
        guard !stopHookActive else { return nil }
        let mine = open.filter { mentions($0.id) }
        guard !mine.isEmpty else { return nil }
        let list = mine.map { session in
            let message = session.message.map { ": \"\($0)\"" } ?? ""
            return "\(session.id) (\(session.state.rawValue)\(message))"
        }.joined(separator: ", ")
        return """
            The user's device still shows this AnnotateKit Send as in progress: \(list). Report it \
            before you stop, or the app keeps saying Claude is working. For each one: report any note \
            you haven't (`annotate resolve <id> <pin> "what changed"` or `annotate dismiss <id> <pin> \
            "why not"`), then `annotate status <id> done "<one-line summary>"`, or \
            `annotate status <id> failed "<why>"`. The annotation_resolve, annotation_dismiss and \
            annotation_status MCP tools do the same. If you need the user's input on a note, ask with \
            `annotate ask` (or annotation_ask) instead of in the chat.
            """
    }

    /// Reads the hook input, decides, and returns what to print on stdout (nil: print nothing and
    /// let Claude stop). Any failure to read lets Claude stop: a hook must never trap a session.
    public static func run(input data: Data, explicitDirectory: String?, workingDirectory: String, now: Date = Date()) -> String? {
        let input = (try? JSONDecoder().decode(Input.self, from: data)) ?? Input()
        // The second try always lets Claude stop, so settle it before touching the disk
        guard input.stopHookActive != true else { return nil }
        let output = SessionFeed.outputDirectory(explicit: explicitDirectory, workingDirectory: input.cwd ?? workingDirectory)
        guard FileManager.default.fileExists(atPath: output.path) else { return nil }
        let open = openSessions(in: output, now: now)
        // Mapped and searched as bytes: transcripts reach hundreds of MB, and decoding one into a
        // String and running `contains` per open session made every stop wait seconds
        guard !open.isEmpty, let path = input.transcriptPath,
              let transcript = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return nil }
        guard let reason = blockReason(open: open, stopHookActive: false, mentions: { transcript.range(of: Data($0.utf8)) != nil }) else {
            return nil
        }
        let decision = ["decision": "block", "reason": reason]
        guard let json = try? JSONSerialization.data(withJSONObject: decision, options: [.sortedKeys]) else { return nil }
        return String(decoding: json, as: UTF8.self)
    }
}

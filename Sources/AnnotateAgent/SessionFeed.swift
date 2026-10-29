// Mac-side discovery of sessions the app sends. Every consumer (channel server, watcher, headless
// runner) uses the same rules: only complete bundles, only ones sent after the consumer started
// (minus a grace window, so a Send just before launching isn't lost), and an atomic claim so two
// open Claude Code sessions never both act on one bundle. It also surfaces the user's replies to the
// agent's per-pin questions (from any session, regardless of cutoff) and consumes each one exactly once.

import AnnotateCore
import Foundation

public struct SessionFeed: Sendable {
    public let outputDirectory: URL
    /// Session ids sort by UTC timestamp; anything at or after this is new to this consumer.
    public let cutoffID: String

    public init(outputDirectory: URL, startedAt: Date = Date(), grace: TimeInterval = 120) {
        self.outputDirectory = outputDirectory
        self.cutoffID = SessionWriter.makeSessionID(date: startedAt.addingTimeInterval(-grace), suffix: "")
    }

    /// New, complete, unclaimed sessions, oldest first.
    public func pending() -> [String] {
        SessionInbox.pendingSessionIDs(in: outputDirectory, since: cutoffID)
    }

    /// Claims every pending session as `state`; returns the ones this consumer won.
    public func claimPending(as state: SessionStatus.State) -> [String] {
        pending().filter { SessionInbox.claim(id: $0, in: outputDirectory, as: state) }
    }

    /// Replies the user wrote on the device to questions the agent asked, across every session on disk
    /// (a question may outlive the consumer's cutoff), oldest first.
    public func pendingReplies() -> [(sessionID: String, reply: PinReply)] {
        // No `since:` cutoff: the agent may ask about a session sent long before this consumer started.
        let found = SessionInbox.sessionIDs(in: outputDirectory).flatMap { id in
            SessionInbox.unansweredReplies(id: id, in: outputDirectory).map { (sessionID: id, reply: $0) }
        }
        // Stable on ties: `sorted` isn't, so fall back to discovery order (session id, then file order).
        return found.enumerated()
            .sorted { lhs, rhs in
                lhs.element.reply.at != rhs.element.reply.at
                    ? lhs.element.reply.at < rhs.element.reply.at
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Marks it answered so no other consumer delivers it again.
    public func consume(_ reply: PinReply, sessionID: String) {
        // Best effort: a failed write only means the reply may be delivered once more, which beats
        // failing the delivery that already happened.
        try? SessionInbox.markAnswered(reply, id: sessionID, in: outputDirectory)
    }

    public func sessionDirectory(_ id: String) -> URL {
        SessionInbox.sessionDirectory(id, in: outputDirectory)
    }

    /// "latest" (or nothing) resolves to the newest complete session; malformed ids resolve to nil.
    public func resolve(_ id: String?) -> String? {
        guard let id, id != "latest", !id.isEmpty else {
            return SessionInbox.sessionIDs(in: outputDirectory).last
        }
        return SessionInbox.isValidSessionID(id) ? id : nil
    }

    /// `--dir` if given, else `.annotate` at the project root above `workingDirectory`.
    public static func outputDirectory(explicit: String?, workingDirectory: String) -> URL {
        if let explicit {
            return URL(fileURLWithPath: explicit, relativeTo: URL(fileURLWithPath: workingDirectory, isDirectory: true)).standardizedFileURL
        }
        // locate() starts from the parent of the path it is given
        let marker = (workingDirectory as NSString).appendingPathComponent("_")
        let root = ProjectRoot.locate(fromSourceFile: marker) ?? URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return root.appendingPathComponent(".annotate", isDirectory: true)
    }
}

extension SessionStatus.State {
    /// States an agent may report through `annotation_status` / `annotate status`.
    public static let reportable: [SessionStatus.State] = [.received, .working, .done, .failed]
}

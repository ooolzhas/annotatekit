// Writes a session bundle to disk, finds where it should go, and tracks delivery status.
// Layout under the output directory (default `<project root>/.annotate`):
//   .gitignore                 "*" — sessions never get committed
//   latest                     "sessions/<id>" — the newest bundle
//   sessions/<id>/prompt.md    the message for the agent
//   sessions/<id>/screens/<n>.png, <n>-annotated.png, <n>@3x.png, crops/<n>.png
//   sessions/<id>/session.json written LAST: its presence means the bundle is complete
//   sessions/<id>/status.json  written by the receiving side (received → working → done/failed);
//                              the app polls it to show progress. Absent = not picked up yet.
//                              Also carries per-pin results (`pins`: resolved / dismissed / question / answered).
//   sessions/<id>/replies.json written by the APP: the user's answers to the agent's per-pin
//                              questions, append-only (on a device DeviceMirror copies it to the Mac)
//   agent.json, agents/<pid>.json   who is listening (AgentPresence.swift)
// Simulator apps can write to the host file system, so the overlay locates the project root by
// walking up from the `#filePath` of the `Annotate.install()` call site. On a device the bundle
// goes to the app's Documents folder and the Mac copies it over (DeviceMirror).

import Foundation

public struct SessionBundle: Sendable {
    public var session: AnnotationSession
    /// PNG data keyed by path relative to the session directory ("crops/1.png").
    public var images: [String: Data]

    public init(session: AnnotationSession, images: [String: Data]) {
        self.session = session
        self.images = images
    }
}

public enum SessionWriter {
    public static let sessionsFolder = "sessions"

    /// Writes the bundle and returns the session directory.
    @discardableResult
    public static func write(_ bundle: SessionBundle, prompt: String, to outputDirectory: URL, fileManager: FileManager = .default) throws -> URL {
        let sessionDir = outputDirectory
            .appendingPathComponent(sessionsFolder, isDirectory: true)
            .appendingPathComponent(bundle.session.id, isDirectory: true)
        try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let gitignore = outputDirectory.appendingPathComponent(".gitignore")
        if !fileManager.fileExists(atPath: gitignore.path) {
            try Data("*\n".utf8).write(to: gitignore, options: .atomic)
        }

        for (relativePath, data) in bundle.images {
            let url = sessionDir.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }

        try Data(prompt.utf8).write(to: sessionDir.appendingPathComponent(SessionInbox.promptFile), options: .atomic)
        // Last, atomically: watchers treat session.json as "bundle complete"
        let json = try AnnotationSession.encoder.encode(bundle.session)
        try json.write(to: sessionDir.appendingPathComponent(SessionInbox.sessionFile), options: .atomic)

        let latest = "\(sessionsFolder)/\(bundle.session.id)\n"
        try Data(latest.utf8).write(to: outputDirectory.appendingPathComponent("latest"), options: .atomic)
        return sessionDir
    }

    /// Sortable, filesystem-safe id: "20261028-141502-a1b2".
    public static func makeSessionID(date: Date = Date(), suffix: String = String(UUID().uuidString.prefix(4)).lowercased()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: date))-\(suffix)"
    }
}

public struct SessionStatus: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable, CaseIterable {
        /// Handed to Claude Code (channel event, watcher line, or headless run queued) but not yet
        /// opened by the agent.
        case delivered
        /// The agent opened the session; nothing changed yet.
        case received
        case working
        case done
        case failed
    }

    public var state: State
    /// Short human summary shown in the app, e.g. "Edited HomeView.swift, AlarmCard.swift".
    public var message: String?
    public var updatedAt: Date
    /// Per-pin results reported by the agent. Optional so status.json files written before pins
    /// existed still decode (schema changes are additive only).
    public var pins: [PinStatus]?
    /// Pins the agent said it started on (`annotate ack`, annotation_acknowledge), the most recent
    /// last. A list on the session rather than a pin state: apps built before it existed decode pin
    /// states strictly and would reject an unknown one, while an unknown key is ignored.
    public var acknowledged: [Int]?

    public init(
        state: State,
        message: String? = nil,
        updatedAt: Date = Date(),
        pins: [PinStatus]? = nil,
        acknowledged: [Int]? = nil
    ) {
        self.state = state
        self.message = message
        self.updatedAt = updatedAt
        self.pins = pins
        self.acknowledged = acknowledged
    }

    public var isFinal: Bool { state == .done || state == .failed }
}

/// One pin's result as reported by the agent, stored in status.json.
public struct PinStatus: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable, CaseIterable { case resolved, dismissed, question, answered }

    /// Annotation.index within its session.
    public var index: Int
    public var state: State
    /// resolved: what changed · dismissed: why not · question / answered: the question
    public var note: String?
    /// answered only: the user's reply
    public var reply: String?
    public var updatedAt: Date
    /// The conversation about this pin, oldest first: each question the agent asked and each reply
    /// it was handed. The agent side appends to it; `note` and `reply` keep the latest question and
    /// reply for apps built before threads. Optional: older files have none (see `messages`).
    public var thread: [PinMessage]?

    public init(
        index: Int,
        state: State,
        note: String? = nil,
        reply: String? = nil,
        updatedAt: Date = Date(),
        thread: [PinMessage]? = nil
    ) {
        self.index = index
        self.state = state
        self.note = note
        self.reply = reply
        self.updatedAt = updatedAt
        self.thread = thread
    }

    /// The pin's conversation: `thread`, or for a file written before threads, the one question and
    /// reply that `note` and `reply` kept (dated `updatedAt`, the only date there is).
    public var messages: [PinMessage] {
        if let thread, !thread.isEmpty { return thread }
        guard state == .question || state == .answered else { return [] }
        var messages: [PinMessage] = []
        if let question = note, !question.isEmpty {
            messages.append(PinMessage(role: .agent, text: question, at: updatedAt))
        }
        if state == .answered, let reply, !reply.isEmpty {
            messages.append(PinMessage(role: .human, text: reply, at: updatedAt))
        }
        return messages
    }
}

/// One message in a pin's conversation: a question from the agent or a reply from the user.
public struct PinMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case agent, human }

    public var role: Role
    public var text: String
    public var at: Date

    public init(role: Role, text: String, at: Date = Date()) {
        self.role = role
        self.text = text
        self.at = at
    }
}

/// The user's answer to an agent's question about one pin, written by the app to replies.json.
public struct PinReply: Codable, Sendable, Equatable {
    public var index: Int
    public var text: String
    public var at: Date

    public init(index: Int, text: String, at: Date = Date()) {
        self.index = index
        self.text = text
        self.at = at
    }
}

/// The receiving side of the bundle directory: what's new, and reporting progress back.
public enum SessionInbox {
    public static let sessionFile = "session.json"
    public static let promptFile = "prompt.md"
    public static let statusFile = "status.json"
    public static let repliesFile = "replies.json"
    static let claimMarker = ".claimed"

    public static func sessionDirectory(_ id: String, in outputDirectory: URL) -> URL {
        outputDirectory
            .appendingPathComponent(SessionWriter.sessionsFolder, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    /// Session ids are generated by `SessionWriter.makeSessionID`; anything else (path separators,
    /// "..", odd characters) is rejected before it is used to build a path.
    public static func isValidSessionID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.first != "." && id.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_")
        }
    }

    /// A path from session.json that stays inside the session directory.
    public static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    /// Complete sessions (session.json present), oldest first.
    /// - Parameter since: skip ids sorting before this one without touching the disk for them;
    ///   ids are UTC timestamps, so this is "sent at or after".
    public static func sessionIDs(in outputDirectory: URL, since: String? = nil, fileManager: FileManager = .default) -> [String] {
        let sessions = outputDirectory.appendingPathComponent(SessionWriter.sessionsFolder, isDirectory: true)
        let entries = (try? fileManager.contentsOfDirectory(atPath: sessions.path)) ?? []
        return entries
            .filter { id in since.map { id >= $0 } ?? true }
            .filter(isValidSessionID)
            .filter { fileManager.fileExists(atPath: sessions.appendingPathComponent($0).appendingPathComponent(sessionFile).path) }
            .sorted()
    }

    /// Complete sessions nobody has picked up yet (no status.json), oldest first.
    public static func pendingSessionIDs(in outputDirectory: URL, since: String? = nil, fileManager: FileManager = .default) -> [String] {
        sessionIDs(in: outputDirectory, since: since, fileManager: fileManager).filter { id in
            let claimed = sessionDirectory(id, in: outputDirectory).appendingPathComponent(claimMarker).path
            return !fileManager.fileExists(atPath: claimed) && readStatus(id: id, in: outputDirectory) == nil
        }
    }

    public static func readStatus(id: String, in outputDirectory: URL) -> SessionStatus? {
        let url = sessionDirectory(id, in: outputDirectory).appendingPathComponent(statusFile)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? AnnotationSession.decoder.decode(SessionStatus.self, from: data)
    }

    /// A status without `pins` or `acknowledged` keeps what's already on disk: `annotate status`, the
    /// status tool and "received" all write a session-level state and must not wipe what the agent
    /// reported pin by pin.
    public static func writeStatus(_ status: SessionStatus, id: String, in outputDirectory: URL) throws {
        let url = sessionDirectory(id, in: outputDirectory).appendingPathComponent(statusFile)
        var status = status
        if status.pins == nil || status.acknowledged == nil, let existing = readStatus(id: id, in: outputDirectory) {
            status.pins = status.pins ?? existing.pins
            status.acknowledged = status.acknowledged ?? existing.acknowledged
        }
        try AnnotationSession.encoder.encode(status).write(to: url, options: .atomic)
    }

    /// Upserts one pin's status (matched by index), keeping the session's state and message. A pin
    /// written without a thread keeps the conversation it had, so resolving an asked-about pin doesn't
    /// lose it. A session with no status yet becomes `.working`. Returns the written status.
    @discardableResult
    public static func updatePin(_ pin: PinStatus, id: String, in outputDirectory: URL) throws -> SessionStatus {
        // A pin report means the agent is on it, so an unclaimed session counts as working
        var status = readStatus(id: id, in: outputDirectory) ?? SessionStatus(state: .working)
        var pins = status.pins ?? []
        if let existing = pins.firstIndex(where: { $0.index == pin.index }) {
            var pin = pin
            if pin.thread == nil {
                let kept = pins[existing].messages
                pin.thread = kept.isEmpty ? nil : kept
            }
            pins[existing] = pin
        } else {
            pins.append(pin)
        }
        // Sorted so the file (and the app's diffing of it) is stable regardless of report order
        status.pins = pins.sorted { $0.index < $1.index }
        status.updatedAt = Date()
        try writeStatus(status, id: id, in: outputDirectory)
        return status
    }

    /// Marks the pin `.question` and adds the question to its thread, after any earlier exchange about
    /// it. The question is dated at least a second after the thread's last message: dates are stored
    /// to the second, and a reply counts as answering a question at its own second, so asking again
    /// right after a reply would otherwise take that reply as the new answer. Returns the written status.
    @discardableResult
    public static func ask(_ question: String, pin: Int, id: String, in outputDirectory: URL, at date: Date = Date()) throws -> SessionStatus {
        let earlier = readStatus(id: id, in: outputDirectory)?.pins?.first { $0.index == pin }?.messages ?? []
        let date = earlier.last.map { max(date, $0.at.addingTimeInterval(1)) } ?? date
        return try updatePin(
            PinStatus(
                index: pin,
                state: .question,
                note: question,
                updatedAt: date,
                thread: earlier + [PinMessage(role: .agent, text: question, at: date)]
            ),
            id: id,
            in: outputDirectory
        )
    }

    /// Records that the agent started on these pins: each moves to the end of `acknowledged` (so the
    /// last is the one it's on now). A session still in progress becomes `.working` and drops its
    /// message, so the device names the pin until the agent reports something newer. Returns the
    /// written status.
    @discardableResult
    public static func acknowledge(_ pins: [Int], id: String, in outputDirectory: URL) throws -> SessionStatus {
        var status = readStatus(id: id, in: outputDirectory) ?? SessionStatus(state: .working)
        var acknowledged = status.acknowledged ?? []
        for pin in pins {
            acknowledged.removeAll { $0 == pin }
            acknowledged.append(pin)
        }
        status.acknowledged = acknowledged
        if !status.isFinal {
            status.state = .working
            status.message = nil
        }
        status.updatedAt = Date()
        try writeStatus(status, id: id, in: outputDirectory)
        return status
    }

    /// The user's replies for a session, in file order. [] when absent or unreadable.
    public static func readReplies(id: String, in outputDirectory: URL) -> [PinReply] {
        let url = sessionDirectory(id, in: outputDirectory).appendingPathComponent(repliesFile)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? AnnotationSession.decoder.decode([PinReply].self, from: data)) ?? []
    }

    /// App side: appends to replies.json (atomic rewrite).
    public static func appendReply(_ reply: PinReply, id: String, in outputDirectory: URL) throws {
        let url = sessionDirectory(id, in: outputDirectory).appendingPathComponent(repliesFile)
        // Rewrite the whole array atomically so the Mac (or the mirror) never reads a half-written file
        let replies = readReplies(id: id, in: outputDirectory) + [reply]
        try AnnotationSession.encoder.encode(replies).write(to: url, options: .atomic)
    }

    /// Replies to pins whose status is still `.question` and whose `at` >= that pin's `updatedAt`, oldest first.
    public static func unansweredReplies(id: String, in outputDirectory: URL) -> [PinReply] {
        // Replies first: consumers poll this for every session twice a second and most never get
        // one, so a missing replies.json should cost one failed open, not a status decode
        let replies = readReplies(id: id, in: outputDirectory)
        guard !replies.isEmpty, let pins = readStatus(id: id, in: outputDirectory)?.pins else { return [] }
        let asked = Dictionary(
            pins.filter { $0.state == .question }.map { ($0.index, $0.updatedAt) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !asked.isEmpty else { return [] }
        // A reply older than the question answers an earlier one (the agent re-asked), so skip it
        return replies
            .filter { reply in asked[reply.index].map { reply.at >= $0 } ?? false }
            .enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    /// Marks the reply's pin `.answered` (note keeps the question, reply = text) and adds the reply to
    /// its thread, so each reply is delivered once.
    public static func markAnswered(_ reply: PinReply, id: String, in outputDirectory: URL) throws {
        let asked = readStatus(id: id, in: outputDirectory)?.pins?.first { $0.index == reply.index }
        var thread = asked?.messages ?? []
        let message = PinMessage(role: .human, text: reply.text, at: reply.at)
        // A reply delivered again (its earlier mark failed) is in the thread once
        if !thread.contains(message) { thread.append(message) }
        try updatePin(
            PinStatus(index: reply.index, state: .answered, note: asked?.note, reply: reply.text, thread: thread),
            id: id,
            in: outputDirectory
        )
    }

    /// Atomically claims a pending session for one consumer. Returns false if another consumer
    /// (a second watcher) already claimed it.
    public static func claim(
        id: String,
        in outputDirectory: URL,
        as state: SessionStatus.State = .received,
        fileManager: FileManager = .default
    ) -> Bool {
        let dir = sessionDirectory(id, in: outputDirectory)
        let lock = dir.appendingPathComponent(claimMarker)
        // Directory creation is atomic and fails when it already exists, so exactly one consumer wins
        do {
            try fileManager.createDirectory(at: lock, withIntermediateDirectories: false)
        } catch {
            return false
        }
        try? writeStatus(SessionStatus(state: state), id: id, in: outputDirectory)
        return true
    }

    /// Undoes a claim nobody acted on (a channel event that never reached the agent), so another
    /// consumer can deliver the session. Leaves it alone once the agent has reported anything past
    /// `delivered`. Returns true when the session is pending again.
    @discardableResult
    public static func release(id: String, in outputDirectory: URL, fileManager: FileManager = .default) -> Bool {
        let dir = sessionDirectory(id, in: outputDirectory)
        guard let status = readStatus(id: id, in: outputDirectory), status.state == .delivered else { return false }
        try? fileManager.removeItem(at: dir.appendingPathComponent(statusFile))
        try? fileManager.removeItem(at: dir.appendingPathComponent(claimMarker))
        return true
    }

    /// How long the app's notes sheet remembers a Send (design choice); pruning never removes one younger.
    public static let historyWindow: TimeInterval = 48 * 3600

    /// The lowest session id inside the history window that ends at `now`. Ids are UTC timestamps,
    /// so every Send at or after `now - historyWindow` sorts at or after it.
    public static func historyCutoffID(now: Date = Date()) -> String {
        SessionWriter.makeSessionID(date: now.addingTimeInterval(-historyWindow), suffix: "")
    }

    /// Deletes the oldest session folders beyond the newest `keeping`, so `.annotate/` stays small,
    /// but never one inside the history window. Incomplete folders count too (a crashed write
    /// shouldn't linger). Returns the removed ids.
    @discardableResult
    public static func prune(keeping: Int, in outputDirectory: URL, now: Date = Date(), fileManager: FileManager = .default) -> [String] {
        guard keeping >= 0 else { return [] }
        let sessions = outputDirectory.appendingPathComponent(SessionWriter.sessionsFolder, isDirectory: true)
        let ids = ((try? fileManager.contentsOfDirectory(atPath: sessions.path)) ?? []).filter(isValidSessionID).sorted()
        let cutoff = historyCutoffID(now: now)
        let doomed = ids.dropLast(keeping).filter { $0 < cutoff }
        for id in doomed {
            try? fileManager.removeItem(at: sessions.appendingPathComponent(id, isDirectory: true))
        }
        return Array(doomed)
    }

    public static func loadSession(id: String, in outputDirectory: URL) throws -> AnnotationSession {
        let url = sessionDirectory(id, in: outputDirectory).appendingPathComponent(sessionFile)
        return try AnnotationSession.decoder.decode(AnnotationSession.self, from: Data(contentsOf: url))
    }

    public static func loadPrompt(id: String, in outputDirectory: URL) throws -> String {
        let url = sessionDirectory(id, in: outputDirectory).appendingPathComponent(promptFile)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

public enum ProjectRoot {
    /// Nearest ancestor of `sourceFile` containing `.git`; else the nearest with `Package.swift`,
    /// an `.xcodeproj` or an `.xcworkspace`. Nil when the path doesn't exist (a real device).
    public static func locate(fromSourceFile sourceFile: String, fileManager: FileManager = .default) -> URL? {
        var directory = URL(fileURLWithPath: sourceFile).deletingLastPathComponent().standardizedFileURL
        guard fileManager.fileExists(atPath: directory.path) else { return nil }

        var fallback: URL?
        while true {
            if fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path) {
                return directory
            }
            if fallback == nil, isProjectDirectory(directory, fileManager: fileManager) {
                fallback = directory
            }
            let parent = directory.deletingLastPathComponent().standardizedFileURL
            if parent.path == directory.path { return fallback }
            directory = parent
        }
    }

    /// `file` relative to `root` when inside it, else unchanged.
    public static func relativePath(of file: String, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let filePath = URL(fileURLWithPath: file).standardizedFileURL.path
        return filePath.hasPrefix(prefix) ? String(filePath.dropFirst(prefix.count)) : file
    }

    private static func isProjectDirectory(_ directory: URL, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) { return true }
        let entries = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return entries.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }
}

public enum ContentSizeName {
    /// "UICTContentSizeCategoryAccessibilityXL" → "AX3"-style short names; "L" is the system default.
    public static func short(_ rawValue: String) -> String {
        let table: [String: String] = [
            "UICTContentSizeCategoryXS": "XS",
            "UICTContentSizeCategoryS": "S",
            "UICTContentSizeCategoryM": "M",
            "UICTContentSizeCategoryL": "L",
            "UICTContentSizeCategoryXL": "XL",
            "UICTContentSizeCategoryXXL": "XXL",
            "UICTContentSizeCategoryXXXL": "XXXL",
            "UICTContentSizeCategoryAccessibilityM": "AX1",
            "UICTContentSizeCategoryAccessibilityL": "AX2",
            "UICTContentSizeCategoryAccessibilityXL": "AX3",
            "UICTContentSizeCategoryAccessibilityXXL": "AX4",
            "UICTContentSizeCategoryAccessibilityXXXL": "AX5"
        ]
        return table[rawValue] ?? rawValue
    }
}

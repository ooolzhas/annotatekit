// Who is listening for Sends. Every Mac-side `annotate` process (mcp, watch, run) writes a heartbeat
// to `.annotate/agents/<pid>.json`; one of them merges the live ones into `.annotate/agent.json`.
// The app reads that file to show a dot on the launcher pill: the Simulator reads it in place, and a
// device gets a copy over the developer connection. Freshness is judged by the file's modification
// date on the reader's own clock, so a heartbeat left behind by a process that died reads as gone.
// The other direction: on a device the app keeps `app.json` (`AppBeacon`) fresh while it's open.

import Foundation

public struct AgentPresence: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        /// A Send starts the agent by itself: a watcher, the headless runner, or a channel the agent
        /// has been seen answering.
        case push
        /// The agent is connected but only reads sessions when asked (MCP tools without channels).
        case pull
    }

    /// Display name: "Claude Code", "Cursor", "Codex", or the MCP client's own name.
    public var agent: String
    public var mode: Mode
    /// How it's connected: "channel", "mcp", "watch" or "run".
    public var via: String
    /// The project folder's name, so the app can tell which checkout is listening.
    public var project: String?
    public var updatedAt: Date

    public init(agent: String, mode: Mode, via: String, project: String? = nil, updatedAt: Date = Date()) {
        self.agent = agent
        self.mode = mode
        self.via = via
        self.project = project
        self.updatedAt = updatedAt
    }

    /// VoiceOver wording for the pill's dot.
    public var accessibilityDescription: String {
        switch mode {
        case .push: "Connected to \(agent)"
        case .pull: "\(agent) connected; ask it to check your annotations"
        }
    }
}

/// What the launcher's dot says about the connection, always shown: an agent listens, the app is
/// catching up on a late heartbeat, or nothing listens.
public enum AgentLink: Equatable, Sendable {
    /// A fresh heartbeat: an agent listens (push or pull alike).
    case active
    /// Not sure yet: no read has landed since the app opened, or the heartbeat is late but not yet
    /// stale, as when the copy to a device lags. Saves the dot from flipping to offline and back.
    case resyncing
    /// No live heartbeat: nothing listens, and a Send is saved for later.
    case offline

    /// Seconds after which a heartbeat counts as late: two missed `AgentPresenceFile.interval`s plus
    /// a second of slack. From here to `AgentPresenceFile.staleAfter` the dot reads resyncing.
    public static let lateAfter: TimeInterval = AgentPresenceFile.interval * 2 + 1

    /// - Parameters:
    ///   - hasRead: a presence read has landed since the app opened.
    ///   - presence: the merged presence, nil once `agent.json` is stale or gone.
    ///   - heartbeatAge: seconds since `agent.json` was written; nil when there is none.
    public static func resolve(hasRead: Bool, presence: AgentPresence?, heartbeatAge: TimeInterval?) -> AgentLink {
        guard hasRead else { return .resyncing }
        guard presence != nil else { return .offline }
        return (heartbeatAge ?? 0) > lateAfter ? .resyncing : .active
    }
}

/// Contents of `app.json`: which build is running on the device.
public struct AppBeacon: Codable, Sendable, Equatable {
    public var bundleID: String?
    /// `AppInfo.installFile`: the Mac walks up from it to see whether the build is from its checkout.
    public var installFile: String?

    public init(bundleID: String?, installFile: String?) {
        self.bundleID = bundleID
        self.installFile = installFile
    }
}

public enum AgentPresenceFile {
    /// Merged presence the app reads.
    public static let fileName = "agent.json"
    /// Per-process heartbeats.
    public static let heartbeatFolder = "agents"
    /// Rewritten by the app on a device every `interval` while it's in the foreground (`AppBeacon`):
    /// the Mac polls quickly only while someone might Send, and pushes presence only to builds from
    /// its own checkout.
    public static let appFile = "app.json"
    /// Seconds between heartbeats.
    public static let interval: TimeInterval = 3
    /// A heartbeat (or the merged file) older than this belongs to a process that's gone. Several
    /// intervals, so one slow device copy doesn't make the dot flicker.
    public static let staleAfter: TimeInterval = 15

    public static func heartbeatURL(pid: Int32, in outputDirectory: URL) -> URL {
        outputDirectory
            .appendingPathComponent(heartbeatFolder, isDirectory: true)
            .appendingPathComponent("\(pid).json")
    }

    public static func writeHeartbeat(_ presence: AgentPresence, pid: Int32, in outputDirectory: URL, fileManager: FileManager = .default) throws {
        let url = heartbeatURL(pid: pid, in: outputDirectory)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AnnotationSession.encoder.encode(presence).write(to: url, options: .atomic)
    }

    public static func removeHeartbeat(pid: Int32, in outputDirectory: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: heartbeatURL(pid: pid, in: outputDirectory))
    }

    /// Heartbeats written within `staleAfter` of `now`, best first (see `merge`).
    public static func liveHeartbeats(in outputDirectory: URL, now: Date = Date(), fileManager: FileManager = .default) -> [AgentPresence] {
        let folder = outputDirectory.appendingPathComponent(heartbeatFolder, isDirectory: true)
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        let beats = names.filter { $0.hasSuffix(".json") }.compactMap { name -> AgentPresence? in
            let url = folder.appendingPathComponent(name)
            guard isFresh(url, now: now, fileManager: fileManager),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? AnnotationSession.decoder.decode(AgentPresence.self, from: data)
        }
        return ranked(beats)
    }

    /// The one to show when several agents listen: push beats pull (a Send will start one of them),
    /// then the most recent.
    public static func merge(_ beats: [AgentPresence]) -> AgentPresence? {
        ranked(beats).first
    }

    /// Writes the merged presence, or removes the file when nothing is listening.
    public static func write(_ presence: AgentPresence?, in outputDirectory: URL, fileManager: FileManager = .default) throws {
        let url = outputDirectory.appendingPathComponent(fileName)
        guard let presence else {
            try? fileManager.removeItem(at: url)
            return
        }
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try AnnotationSession.encoder.encode(presence).write(to: url, options: .atomic)
    }

    /// What the app shows: the merged presence while its file is fresh, else nil.
    public static func read(in outputDirectory: URL, now: Date = Date(), fileManager: FileManager = .default) -> AgentPresence? {
        let url = outputDirectory.appendingPathComponent(fileName)
        guard isFresh(url, now: now, fileManager: fileManager),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? AnnotationSession.decoder.decode(AgentPresence.self, from: data)
    }

    /// Seconds since the merged presence was written, by its modification date on the reader's clock
    /// (never negative); nil when there is no file.
    public static func heartbeatAge(in outputDirectory: URL, now: Date = Date(), fileManager: FileManager = .default) -> TimeInterval? {
        let url = outputDirectory.appendingPathComponent(fileName)
        guard let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return nil
        }
        return max(now.timeIntervalSince(modified), 0)
    }

    /// Judged by modification date, not `updatedAt`: on a device the file is copied from the Mac,
    /// and the two clocks needn't agree. A date slightly in the future (a copy that kept the Mac's
    /// timestamp) still counts as fresh.
    static func isFresh(_ url: URL, now: Date, fileManager: FileManager) -> Bool {
        guard let modified = (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return false
        }
        return now.timeIntervalSince(modified) <= staleAfter
    }

    private static func ranked(_ beats: [AgentPresence]) -> [AgentPresence] {
        beats.sorted { lhs, rhs in
            if lhs.mode != rhs.mode { return lhs.mode == .push }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

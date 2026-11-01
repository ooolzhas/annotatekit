// Gets Sends off physical devices. On a device the app writes bundles into its own container
// (Documents/.annotate), which the Mac can't see as files, so the hub process copies each new one
// over the developer connection (USB or Wi-Fi, via `DeviceBridge`) into this project's
// `.annotate/sessions/`. From there every consumer picks it up exactly like a Simulator bundle.
// Status and presence go the other way, into the container, where the app already polls for them.
// Replies come back: while the agent has a question open on a mirrored session, the user's answers
// (`replies.json`, written by the app in its container) are pulled into the Mac's session folder,
// and the session stays tracked until it is final with no question open, or `trackingLimit` passes.
// Routing: a bundle belongs here when the `Annotate.install()` file it names sits in this checkout,
// so builds from two worktrees reach the agent in each. The host app needs no setup for any of it:
// no network permission and no Info.plist keys, just a development build on a paired device.

import AnnotateCore
import Foundation

public struct RemoteDevice: Sendable, Equatable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct RemoteFile: Sendable, Equatable {
    /// Relative to the folder that was listed.
    public var path: String
    public var isDirectory: Bool
    public var modified: Date?

    public init(path: String, isDirectory: Bool = false, modified: Date? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.modified = modified
    }
}

/// The transport to devices; `DeviceCtlBridge` on macOS, a fake in tests.
public protocol DeviceBridge: Sendable {
    /// Paired physical devices.
    func devices() async throws -> [RemoteDevice]
    /// Apps installed from Xcode: their data containers are readable and writable.
    func developerApps(on device: String) async throws -> [String]
    /// Every file under `path` in the app's data container, recursively.
    func files(on device: String, app: String, path: String) async throws -> [RemoteFile]
    /// Copies a file or folder out of the container; `local` is the new item's path.
    func copy(from path: String, on device: String, app: String, to local: URL) async throws
    func copy(_ local: URL, to path: String, on device: String, app: String) async throws
}

public actor DeviceMirror {
    /// Where AnnotateKit writes on a device, inside the app's data container.
    public static let remoteRoot = "Documents/.annotate"
    /// Polling for an app that's open (its `app.json` changed recently).
    static let hotInterval: TimeInterval = 2
    /// Polling for this project's own app while it's closed, so the first Send after launch is quick.
    static let warmInterval: TimeInterval = 8
    /// Polling for any other development build, in case it carries AnnotateKit too.
    static let coldInterval: TimeInterval = 60
    /// A cold build whose listing keeps failing (no AnnotateKit, or it never sent) doubles its
    /// interval per miss up to this many times: 60 s grows to 16 min. A phone carries dozens of
    /// development builds and each listing is a devicectl round trip of half a second or more.
    static let coldBackoffSteps = 4
    /// Sessions kept in the Mac's folder past the history window, like the app's own default
    /// (`AnnotateOptions.keepsSessions`): on a device the app prunes its container, not the Mac copy.
    static let keptSessions = 30
    /// Re-list devices and their apps this often.
    static let discoveryInterval: TimeInterval = 20
    /// An app whose `app.json` hasn't changed in this long counts as closed.
    static let openWindow: TimeInterval = 4 * AgentPresenceFile.interval
    /// Push presence to an open app this often, well inside `AgentPresenceFile.staleAfter`.
    static let presenceInterval: TimeInterval = 5
    /// Re-read an app's `app.json` this often: a reinstall from another checkout changes it.
    static let beaconRefresh: TimeInterval = 60
    /// Stop forwarding status for a session after this long (the app stops polling at the same age).
    static let trackingLimit: TimeInterval = 3600
    /// A device that failed to list its apps is left alone this long.
    static let backoff: TimeInterval = 30

    struct Target: Hashable, Sendable {
        let device: String
        let app: String
    }

    struct TargetState {
        /// Matches a bundle id from this project's Xcode project: polled warm before it says anything.
        var isProjectApp: Bool
        var lastPolled: Date = .distantPast
        var beaconStamp: Date?
        var lastBeaconChange: Date?
        var beaconCheckedAt: Date = .distantPast
        /// From `app.json`: nil until read, false when the build is from another checkout.
        var belongsHere: Bool?
        var lastPresencePush: Date = .distantPast
        /// Failed listings in a row; backs off cold polling.
        var misses = 0
    }

    struct Mirrored {
        let target: Target
        let since: Date
        var forwarded: Data?
        /// Last time the device's `replies.json` was pulled; throttled to `hotInterval`.
        var repliesPulledAt: Date = .distantPast
    }

    let outputDirectory: URL
    let projectRoot: URL
    let cutoffID: String
    let bridge: DeviceBridge
    let projectBundleIDs: [String]
    let log: @Sendable (String) -> Void

    private var lastDiscovery: Date = .distantPast
    private var targets: [Target: TargetState] = [:]
    private var deviceNames: [String: String] = [:]
    private var backoffUntil: [String: Date] = [:]
    private var mirrored: [String: Mirrored] = [:]
    /// Session ids already decided: mirrored, another checkout's, or unreadable.
    private var seen: Set<String> = []
    private var announcedTargets: Set<Target> = []

    public init(
        outputDirectory: URL,
        cutoffID: String,
        bridge: DeviceBridge,
        projectBundleIDs: [String]? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.outputDirectory = outputDirectory
        self.projectRoot = outputDirectory.deletingLastPathComponent()
        self.cutoffID = cutoffID
        self.bridge = bridge
        self.projectBundleIDs = projectBundleIDs ?? BundleIDPattern.scan(projectRoot: outputDirectory.deletingLastPathComponent())
        self.log = log
    }

    /// One pass; the hub calls it about once a second and each step keeps its own interval.
    public func tick(now: Date = Date()) async {
        if now.timeIntervalSince(lastDiscovery) >= Self.discoveryInterval {
            await discover(now: now)
        }
        // Open, project and never-listed apps first (the first listing is how an app's beacon gets
        // read), then at most one cold build per tick: listings are serial, so a batch of cold ones
        // coming due together would hold up a Send from the open app.
        let due = targets.keys.filter { isDue($0, now: now) }
        let (cold, warm) = due.reduce(into: ([Target](), [Target]())) { split, target in
            if let state = targets[target], state.lastPolled != .distantPast, isCold(state, now: now) {
                split.0.append(target)
            } else {
                split.1.append(target)
            }
        }
        for target in warm {
            await poll(target, now: now)
        }
        if let target = cold.min(by: { (targets[$0]?.lastPolled ?? .distantPast) < (targets[$1]?.lastPolled ?? .distantPast) }) {
            await poll(target, now: now)
        }
        await forwardStatuses(now: now)
        await pushPresence(now: now)
    }

    // MARK: Discovery

    private func discover(now: Date) async {
        lastDiscovery = now
        guard let devices = try? await bridge.devices() else { return }
        var live: Set<Target> = []
        for device in devices {
            deviceNames[device.id] = device.name
            if let until = backoffUntil[device.id], until > now {
                live.formUnion(targets.keys.filter { $0.device == device.id })
                continue
            }
            guard let apps = try? await bridge.developerApps(on: device.id) else {
                // Paired but out of reach (asleep, off the network): keep what we knew, try later
                backoffUntil[device.id] = now.addingTimeInterval(Self.backoff)
                live.formUnion(targets.keys.filter { $0.device == device.id })
                continue
            }
            for app in apps {
                let target = Target(device: device.id, app: app)
                live.insert(target)
                if targets[target] == nil {
                    targets[target] = TargetState(isProjectApp: BundleIDPattern.matches(app, anyOf: projectBundleIDs))
                }
            }
        }
        targets = targets.filter { live.contains($0.key) }
    }

    private func isDue(_ target: Target, now: Date) -> Bool {
        guard let state = targets[target] else { return false }
        if let until = backoffUntil[target.device], until > now { return false }
        return now.timeIntervalSince(state.lastPolled) >= interval(for: state, now: now)
    }

    private func interval(for state: TargetState, now: Date) -> TimeInterval {
        if state.belongsHere == false { return Self.coldInterval }
        if isOpen(state, now: now) { return Self.hotInterval }
        if state.isProjectApp || state.belongsHere == true { return Self.warmInterval }
        return Self.coldInterval * Double(1 << min(state.misses, Self.coldBackoffSteps))
    }

    private func isCold(_ state: TargetState, now: Date) -> Bool {
        interval(for: state, now: now) >= Self.coldInterval
    }

    private func isOpen(_ state: TargetState, now: Date) -> Bool {
        state.lastBeaconChange.map { now.timeIntervalSince($0) < Self.openWindow } ?? false
    }

    // MARK: Polling

    private func poll(_ target: Target, now: Date) async {
        targets[target]?.lastPolled = now
        // Fails while the app has never sent (no .annotate folder yet); a cold one backs off
        guard let files = try? await bridge.files(on: target.device, app: target.app, path: Self.remoteRoot) else {
            targets[target]?.misses += 1
            return
        }
        targets[target]?.misses = 0

        if let stamp = files.first(where: { $0.path == AgentPresenceFile.appFile })?.modified,
           targets[target]?.beaconStamp != stamp {
            targets[target]?.beaconStamp = stamp
            targets[target]?.lastBeaconChange = now
        }
        if let state = targets[target], isOpen(state, now: now), now.timeIntervalSince(state.beaconCheckedAt) >= Self.beaconRefresh {
            await readBeacon(target, now: now)
        }
        if targets[target]?.belongsHere == false { return }

        for id in Self.completeSessionIDs(in: files) where id >= cutoffID && !seen.contains(id) {
            seen.insert(id)
            await mirror(id, from: target, now: now)
        }
    }

    private func readBeacon(_ target: Target, now: Date) async {
        targets[target]?.beaconCheckedAt = now
        let local = stagingDirectory().appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: local) }
        guard (try? await bridge.copy(from: "\(Self.remoteRoot)/\(AgentPresenceFile.appFile)", on: target.device, app: target.app, to: local)) != nil,
              let data = try? Data(contentsOf: local),
              let beacon = try? AnnotationSession.decoder.decode(AppBeacon.self, from: data) else { return }
        let belongs = Self.belongs(installFile: beacon.installFile, bundleID: beacon.bundleID ?? target.app, to: projectRoot, projectBundleIDs: projectBundleIDs)
        if targets[target]?.belongsHere != belongs {
            targets[target]?.belongsHere = belongs
            if belongs, announcedTargets.insert(target).inserted {
                log("annotate: connected to \(target.app) on \(deviceNames[target.device] ?? target.device)")
            }
        }
    }

    private func mirror(_ id: String, from target: Target, now: Date) async {
        let fileManager = FileManager.default
        let destination = SessionInbox.sessionDirectory(id, in: outputDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        let staging = stagingDirectory().appendingPathComponent("\(id)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let remote = "\(Self.remoteRoot)/\(SessionWriter.sessionsFolder)/\(id)"
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            // session.json alone first: it says whether the bundle is ours before the images come over
            let probe = staging.appendingPathComponent(SessionInbox.sessionFile)
            try await bridge.copy(from: "\(remote)/\(SessionInbox.sessionFile)", on: target.device, app: target.app, to: probe)
            let session = try AnnotationSession.decoder.decode(AnnotationSession.self, from: Data(contentsOf: probe))
            guard session.id == id,
                  Self.belongs(installFile: session.app.installFile, bundleID: session.app.bundleID, to: projectRoot, projectBundleIDs: projectBundleIDs) else {
                return
            }
            let bundle = staging.appendingPathComponent("bundle", isDirectory: true)
            try await bridge.copy(from: remote, on: target.device, app: target.app, to: bundle)
            guard fileManager.fileExists(atPath: bundle.appendingPathComponent(SessionInbox.sessionFile).path) else { return }
            // The app may have marked it already (an old claim); status is the Mac side's to write
            try? fileManager.removeItem(at: bundle.appendingPathComponent(SessionInbox.statusFile))
            let promptURL = bundle.appendingPathComponent(SessionInbox.promptFile)
            if let prompt = try? String(contentsOf: promptURL, encoding: .utf8) {
                try Data(Self.relocatedPrompt(prompt, to: destination).utf8).write(to: promptURL, options: .atomic)
            }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A rename, so watchers never see a half-copied bundle
            try fileManager.moveItem(at: bundle, to: destination)
            try? Data("\(SessionWriter.sessionsFolder)/\(id)\n".utf8)
                .write(to: outputDirectory.appendingPathComponent("latest"), options: .atomic)
            mirrored[id] = Mirrored(target: target, since: now)
            // Consumers scan every session folder twice a second, so the Mac copy can't grow forever
            SessionInbox.prune(keeping: Self.keptSessions, in: outputDirectory, now: now)
            if targets[target]?.belongsHere == nil { targets[target]?.belongsHere = true }
            log("annotate: session \(id) arrived from \(deviceNames[target.device] ?? target.device)")
        } catch {
            log("annotate: couldn't copy session \(id) from \(deviceNames[target.device] ?? target.device): \(error)")
        }
    }

    // MARK: Back to the device

    /// Sends each mirrored session's status to the device and, while the agent has a question open,
    /// brings the user's replies back.
    private func forwardStatuses(now: Date) async {
        for (id, entry) in mirrored {
            if now.timeIntervalSince(entry.since) > Self.trackingLimit {
                mirrored[id] = nil
                continue
            }
            let status = SessionInbox.sessionDirectory(id, in: outputDirectory).appendingPathComponent(SessionInbox.statusFile)
            guard let data = try? Data(contentsOf: status) else { continue }
            if data != entry.forwarded {
                let remote = "\(Self.remoteRoot)/\(SessionWriter.sessionsFolder)/\(id)/\(SessionInbox.statusFile)"
                // On failure the next tick retries: `forwarded` still holds the old contents
                if (try? await bridge.copy(status, to: remote, on: entry.target.device, app: entry.target.app)) != nil {
                    mirrored[id]?.forwarded = data
                }
            }
            let decoded = try? AnnotationSession.decoder.decode(SessionStatus.self, from: data)
            let hasQuestion = decoded?.pins?.contains { $0.state == .question } ?? false
            if hasQuestion, now.timeIntervalSince(entry.repliesPulledAt) >= Self.hotInterval {
                mirrored[id]?.repliesPulledAt = now
                await pullReplies(id, from: entry.target)
            }
            // An agent may ask after reporting done, so a final session stays tracked until its
            // questions are answered; only then is there nothing left to carry either way
            if let decoded, decoded.isFinal, !hasQuestion, mirrored[id]?.forwarded == data {
                mirrored[id] = nil
            }
        }
    }

    /// Copies the device's `replies.json` over the local one when it changed. The app appends to it
    /// on the device, so the device copy is always the complete one.
    private func pullReplies(_ id: String, from target: Target) async {
        let fileManager = FileManager.default
        let local = SessionInbox.sessionDirectory(id, in: outputDirectory).appendingPathComponent(SessionInbox.repliesFile)
        let staging = stagingDirectory().appendingPathComponent("\(id)-replies-\(UUID().uuidString.prefix(8)).json")
        defer { try? fileManager.removeItem(at: staging) }
        let remote = "\(Self.remoteRoot)/\(SessionWriter.sessionsFolder)/\(id)/\(SessionInbox.repliesFile)"
        // Fails until the user first replies: the app creates the file with the first answer
        guard (try? await bridge.copy(from: remote, on: target.device, app: target.app, to: staging)) != nil,
              let data = try? Data(contentsOf: staging),
              data != (try? Data(contentsOf: local)) else { return }
        do {
            // Atomic, so a consumer reading replies never sees half a file
            try data.write(to: local, options: .atomic)
            log("annotate: reply for session \(id) arrived from \(deviceNames[target.device] ?? target.device)")
        } catch {
            log("annotate: couldn't save replies for session \(id): \(error)")
        }
    }

    private func pushPresence(now: Date) async {
        let local = outputDirectory.appendingPathComponent(AgentPresenceFile.fileName)
        guard AgentPresenceFile.read(in: outputDirectory, now: now) != nil else { return }
        for (target, state) in targets
        where state.belongsHere == true && isOpen(state, now: now) && now.timeIntervalSince(state.lastPresencePush) >= Self.presenceInterval {
            targets[target]?.lastPresencePush = now
            _ = try? await bridge.copy(local, to: "\(Self.remoteRoot)/\(AgentPresenceFile.fileName)", on: target.device, app: target.app)
        }
    }

    private func stagingDirectory() -> URL {
        let url = outputDirectory.appendingPathComponent(".incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Rules

    /// Ids of complete sessions (session.json present) in a listing of `remoteRoot`, oldest first.
    static func completeSessionIDs(in files: [RemoteFile]) -> [String] {
        files.compactMap { file -> String? in
            let parts = file.path.split(separator: "/").map(String.init)
            guard parts.count == 3, parts[0] == SessionWriter.sessionsFolder, parts[2] == SessionInbox.sessionFile,
                  SessionInbox.isValidSessionID(parts[1]) else { return nil }
            return parts[1]
        }
        .sorted()
    }

    /// Whether a build belongs to the checkout at `projectRoot`: its install file sits inside it.
    /// Builds from before `installFile` existed fall back to this project's bundle ids.
    static func belongs(installFile: String?, bundleID: String?, to projectRoot: URL, projectBundleIDs: [String]) -> Bool {
        if let installFile {
            // nil when the path isn't on this Mac: a build from somewhere else
            guard let root = ProjectRoot.locate(fromSourceFile: installFile) else { return false }
            return root.resolvingSymlinksInPath().path == projectRoot.resolvingSymlinksInPath().path
        }
        guard let bundleID else { return false }
        return BundleIDPattern.matches(bundleID, anyOf: projectBundleIDs)
    }

    /// The device wrote its own container path into the prompt; point every mention at the Mac copy.
    static func relocatedPrompt(_ prompt: String, to directory: URL) -> String {
        let marker = "Session: "
        guard let line = prompt.split(separator: "\n", omittingEmptySubsequences: false).first(where: { $0.hasPrefix(marker) }) else {
            return prompt
        }
        let remote = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        guard remote.count > 1 else { return prompt }
        return prompt.replacingOccurrences(of: remote, with: directory.path)
    }
}

/// `PRODUCT_BUNDLE_IDENTIFIER` values in a project, used to find its app among a device's
/// development builds before that app has said which checkout it's from.
public enum BundleIDPattern {
    private static let skipped: Set<String> = [".build", "DerivedData", "Pods", "Carthage", "node_modules", "build"]

    /// Values from every `project.pbxproj` and XcodeGen `project.yml` within a few levels of the root.
    public static func scan(projectRoot: URL, maxDepth: Int = 4) -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: Set<String> = []
        let rootDepth = projectRoot.standardizedFileURL.pathComponents.count
        while let url = enumerator.nextObject() as? URL {
            let depth = url.standardizedFileURL.pathComponents.count - rootDepth
            let name = url.lastPathComponent
            if skipped.contains(name) || depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if name.hasSuffix(".xcodeproj"), let text = try? String(contentsOf: url.appendingPathComponent("project.pbxproj"), encoding: .utf8) {
                found.formUnion(values(in: text))
            } else if name == "project.yml" || name == "project.yaml", let text = try? String(contentsOf: url, encoding: .utf8) {
                found.formUnion(values(in: text))
            }
        }
        return found.sorted()
    }

    static func values(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"PRODUCT_BUNDLE_IDENTIFIER\s*[=:]\s*"?([A-Za-z0-9.\-_$(){}]+)"?"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Exact match, with `$(VAR)` / `${VAR}` in a pattern matching anything.
    public static func matches(_ bundleID: String, anyOf patterns: [String]) -> Bool {
        patterns.contains { pattern in
            guard pattern.contains("$") else { return pattern == bundleID }
            let parts = pattern.components(separatedBy: CharacterSet(charactersIn: "$"))
            var regex = "^" + NSRegularExpression.escapedPattern(for: parts[0])
            for part in parts.dropFirst() {
                // "(VAR).rest" or "{VAR}.rest": the variable becomes a wildcard, the rest stays literal
                guard let close = part.firstIndex(where: { $0 == ")" || $0 == "}" }) else {
                    regex += NSRegularExpression.escapedPattern(for: "$" + part)
                    continue
                }
                regex += ".*" + NSRegularExpression.escapedPattern(for: String(part[part.index(after: close)...]))
            }
            return bundleID.range(of: regex + "$", options: .regularExpression) != nil
        }
    }
}

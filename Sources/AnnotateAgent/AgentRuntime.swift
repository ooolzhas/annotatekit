// Background duties of every long-lived `annotate` process (mcp, watch, run). Each one writes its
// own heartbeat (`agents/<pid>.json`), which is what lights the dot on the app's launcher pill.
// The process holding the hub lease for this `.annotate` folder also merges the heartbeats into
// `agent.json` and runs the device mirror, so two agents in one checkout don't both copy from the
// phone. The lease is a file renewed with every heartbeat; when the hub exits, another process
// takes over within `HubLease.staleAfter`.

import AnnotateCore
import Foundation

public actor AgentRuntime {
    public typealias PresenceProvider = @Sendable () async -> AgentPresence

    let outputDirectory: URL
    let presence: PresenceProvider
    let mirror: DeviceMirror?
    let pid = ProcessInfo.processInfo.processIdentifier
    private(set) var isHub = false

    public init(outputDirectory: URL, mirror: DeviceMirror?, presence: @escaping PresenceProvider) {
        self.outputDirectory = outputDirectory
        self.mirror = mirror
        self.presence = presence
    }

    /// Runs until cancelled, then clears this process's traces.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.heartbeatLoop() }
            group.addTask { await self.mirrorLoop() }
        }
        stop()
    }

    /// Removes this process's heartbeat and gives up the hub lease, so the dot and the mirror move on
    /// at once instead of waiting for staleness.
    public func stop() {
        AgentPresenceFile.removeHeartbeat(pid: pid, in: outputDirectory)
        if isHub {
            HubLease.release(pid: pid, in: outputDirectory)
            try? AgentPresenceFile.write(AgentPresenceFile.merge(AgentPresenceFile.liveHeartbeats(in: outputDirectory)), in: outputDirectory)
            isHub = false
        }
    }

    /// One heartbeat: write ours, take or renew the lease, and as hub publish the merged presence.
    func beat(now: Date = Date()) async {
        var current = await presence()
        current.updatedAt = now
        current.project = outputDirectory.deletingLastPathComponent().lastPathComponent
        try? AgentPresenceFile.writeHeartbeat(current, pid: pid, in: outputDirectory)
        isHub = HubLease.acquire(pid: pid, in: outputDirectory, now: now)
        if isHub {
            let merged = AgentPresenceFile.merge(AgentPresenceFile.liveHeartbeats(in: outputDirectory, now: now))
            try? AgentPresenceFile.write(merged, in: outputDirectory)
        }
    }

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            await beat()
            try? await Task.sleep(for: .seconds(AgentPresenceFile.interval))
        }
    }

    /// Separate from the heartbeat: a slow device call must not let the presence file go stale.
    private func mirrorLoop() async {
        guard let mirror else { return }
        while !Task.isCancelled {
            if isHub { await mirror.tick() }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// Which process in a `.annotate` folder does the shared work. A plain file rather than a lock:
/// it must work the same on Linux and survive a process that dies without cleaning up.
public enum HubLease {
    public static let fileName = "hub.json"
    /// Longer than a heartbeat interval plus a slow write, so a live hub never loses its lease.
    public static let staleAfter: TimeInterval = 4 * AgentPresenceFile.interval

    struct Lease: Codable {
        var pid: Int32
        var renewedAt: Date
    }

    /// True when `pid` holds the lease after this call: it renewed its own, or took a free or stale
    /// one. Two processes racing for a stale lease may both win one round; the next renewal settles
    /// it, and everything the hub does tolerates a duplicate.
    public static func acquire(pid: Int32, in outputDirectory: URL, now: Date = Date()) -> Bool {
        let url = outputDirectory.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: url),
           let lease = try? AnnotationSession.decoder.decode(Lease.self, from: data),
           lease.pid != pid,
           now.timeIntervalSince(lease.renewedAt) < staleAfter {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try AnnotationSession.encoder.encode(Lease(pid: pid, renewedAt: now)).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func release(pid: Int32, in outputDirectory: URL) {
        let url = outputDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let lease = try? AnnotationSession.decoder.decode(Lease.self, from: data),
              lease.pid == pid else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// `DeviceBridge` over Xcode's `devicectl`: the same developer connection Xcode uses to install and
// debug, over USB or Wi-Fi, so it reaches any development build on a paired device without the app
// opening a socket or asking for Local Network access. Each call runs `xcrun devicectl` with JSON
// output and a timeout; a device that's asleep or out of range just fails the call.

#if os(macOS)
import Foundation

public struct DeviceCtlBridge: DeviceBridge {
    public enum Failure: Error, CustomStringConvertible {
        case exited(command: String, status: Int32)
        case malformedOutput(command: String)

        public var description: String {
            switch self {
            case .exited(let command, let status): "devicectl \(command) exited with \(status)"
            case .malformedOutput(let command): "devicectl \(command) wrote no readable JSON"
            }
        }
    }

    /// Per-call limit; devicectl connects on demand, which can take a few seconds over Wi-Fi.
    let timeout: Int

    /// Nil when Xcode's devicectl isn't installed (no Xcode, or Xcode older than 15).
    public static func makeIfAvailable(timeout: Int = 20) -> DeviceCtlBridge? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "devicectl"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? DeviceCtlBridge(timeout: timeout) : nil
    }

    public func devices() async throws -> [RemoteDevice] {
        let result = try await run(["list", "devices"])
        let devices = result["devices"] as? [[String: Any]] ?? []
        return devices.compactMap { device in
            let hardware = device["hardwareProperties"] as? [String: Any] ?? [:]
            let connection = device["connectionProperties"] as? [String: Any] ?? [:]
            // Physical iPhones and iPads (both report "iOS"); simulators write to the Mac directly
            guard hardware["reality"] as? String == "physical",
                  hardware["platform"] as? String == "iOS",
                  connection["pairingState"] as? String == "paired",
                  let id = device["identifier"] as? String else { return nil }
            let name = (device["deviceProperties"] as? [String: Any])?["name"] as? String
            return RemoteDevice(id: id, name: name ?? id)
        }
    }

    public func developerApps(on device: String) async throws -> [String] {
        let result = try await run(["device", "info", "apps", "--device", device])
        let apps = result["apps"] as? [[String: Any]] ?? []
        return apps.compactMap { app in
            guard app["builtByDeveloper"] as? Bool == true else { return nil }
            return app["bundleIdentifier"] as? String
        }
    }

    public func files(on device: String, app: String, path: String) async throws -> [RemoteFile] {
        let result = try await run(["device", "info", "files", "--device", device] + container(app) + ["--subdirectory", path])
        let files = result["files"] as? [[String: Any]] ?? []
        return files.compactMap { file in
            guard let path = file["relativePath"] as? String else { return nil }
            let resources = file["resources"] as? [String: Any] ?? [:]
            let metadata = file["metadata"] as? [String: Any] ?? [:]
            return RemoteFile(
                path: path,
                isDirectory: resources["isDirectory"] as? Bool ?? false,
                modified: (metadata["lastModDate"] as? String).flatMap(Self.date)
            )
        }
    }

    public func copy(from path: String, on device: String, app: String, to local: URL) async throws {
        _ = try await run(["device", "copy", "from", "--device", device] + container(app) + ["--source", path, "--destination", local.path])
    }

    public func copy(_ local: URL, to path: String, on device: String, app: String) async throws {
        _ = try await run(["device", "copy", "to", "--device", device] + container(app) + ["--source", local.path, "--destination", path])
    }

    private func container(_ app: String) -> [String] {
        ["--domain-type", "appDataContainer", "--domain-identifier", app]
    }

    /// Runs one devicectl command off the caller's thread and returns its JSON `result`.
    private func run(_ arguments: [String]) async throws -> [String: Any] {
        let timeout = timeout
        let data = try await Task.detached(priority: .utility) {
            try Self.runSync(arguments, timeout: timeout)
        }.value
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure.malformedOutput(command: arguments.prefix(3).joined(separator: " "))
        }
        return object["result"] as? [String: Any] ?? [:]
    }

    private static func runSync(_ arguments: [String], timeout: Int) throws -> Data {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("annotate-devicectl-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl", "--quiet", "--timeout", String(timeout), "--json-output", output.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.exited(command: arguments.prefix(3).joined(separator: " "), status: process.terminationStatus)
        }
        return try Data(contentsOf: output)
    }

    /// devicectl writes "2026-10-28T22:14:30.000Z".
    static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
#endif

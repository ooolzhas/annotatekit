// Writes a session bundle to disk and finds where it should go.
// Layout under the output directory (default `<project root>/.annotate`):
//   .gitignore                 "*" — sessions never get committed
//   latest                     "sessions/<id>" — `cat .annotate/latest` finds the newest bundle
//   sessions/<id>/session.json
//   sessions/<id>/prompt.md
//   sessions/<id>/screenshot.png, annotated.png, crops/<n>.png
// Simulator apps can write to the host file system, so the overlay locates the project root by
// walking up from the `#filePath` of the `Annotate.install()` call site.

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

        let json = try AnnotationSession.encoder.encode(bundle.session)
        try json.write(to: sessionDir.appendingPathComponent("session.json"), options: .atomic)
        try Data(prompt.utf8).write(to: sessionDir.appendingPathComponent("prompt.md"), options: .atomic)

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

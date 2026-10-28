// Session schema round-trip, prompt rendering, bundle layout on disk and project-root discovery.

import Foundation
import Testing
@testable import AnnotateCore

enum Fixtures {
    static let device = DeviceInfo(
        model: "iPhone 17 Pro", systemName: "iOS", systemVersion: "26.0", isSimulator: true,
        screen: AnnotationSize(width: 402, height: 874), scale: 3, colorScheme: "dark",
        contentSize: "L", orientation: "portrait"
    )

    static func session(annotations: [Annotation]) -> AnnotationSession {
        AnnotationSession(
            id: "20261028-141502-a1b2",
            createdAt: Date(timeIntervalSince1970: 1_793_196_902),
            app: AppInfo(bundleID: "com.example.app", name: "Example", version: "1.0", build: "7"),
            device: device,
            screenshot: "screenshot.png",
            annotatedScreenshot: "annotated.png",
            annotations: annotations
        )
    }

    static let element = Annotation(
        index: 1, kind: .element, comment: "bigger, tighter",
        frame: AnnotationRect(x: 24, y: 300, width: 120, height: 44),
        element: ElementInfo(role: "button", label: "Get started", traits: ["button"], breadcrumb: ["HeroCard"]),
        source: SourceLocation(name: "HeroCard", file: "App/HomeView.swift", line: 42, match: .enclosing),
        crop: "crops/1.png"
    )

    static let copyEdit = Annotation(
        index: 2, kind: .element,
        frame: AnnotationRect(x: 24, y: 200, width: 300, height: 20),
        element: ElementInfo(role: "text", label: "Adaptive lamps for every room"),
        textEdit: TextEdit(from: "Adaptive lamps for every room", to: "Smart light that sets itself"),
        crop: "crops/2.png"
    )

    static let region = Annotation(
        index: 3, kind: .region, comment: "add a signup card here",
        frame: AnnotationRect(x: 16, y: 420, width: 352, height: 166),
        source: SourceLocation(name: "HomeView", file: "App/HomeView.swift", line: 12, match: .enclosing),
        sketch: Sketch(size: AnnotationSize(width: 352, height: 166), strokes: [
            Stroke(tool: .rectangle, points: [AnnotationPoint(x: 4, y: 4), AnnotationPoint(x: 340, y: 150)]),
            Stroke(tool: .arrow, points: [AnnotationPoint(x: 200, y: -20), AnnotationPoint(x: 220, y: 10)])
        ]),
        crop: "crops/3.png"
    )
}

@Suite struct SessionCodableTests {
    @Test func roundTripsThroughJSON() throws {
        let session = Fixtures.session(annotations: [Fixtures.element, Fixtures.copyEdit, Fixtures.region])
        let data = try AnnotationSession.encoder.encode(session)
        let decoded = try AnnotationSession.decoder.decode(AnnotationSession.self, from: data)
        #expect(decoded == session)
    }

    @Test func geometryEncodesAsNamedFields() throws {
        let data = try AnnotationSession.encoder.encode(Fixtures.element.frame)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"x\" : 24"))
        #expect(json.contains("\"width\" : 120"))
    }

    @Test func rectRoundsToTenthOfAPoint() {
        let rect = AnnotationRect(CGRect(x: 10.04, y: 20.06, width: 33.333, height: 1))
        #expect(rect == AnnotationRect(x: 10, y: 20.1, width: 33.3, height: 1))
    }

    @Test func emptyAnnotationDetection() {
        var annotation = Fixtures.element
        annotation.comment = "  "
        #expect(annotation.isEmpty)
        #expect(!Fixtures.copyEdit.isEmpty)
        #expect(!Fixtures.region.isEmpty)
    }
}

@Suite struct PromptRendererTests {
    let prompt = PromptRenderer.render(
        Fixtures.session(annotations: [Fixtures.region, Fixtures.element, Fixtures.copyEdit]),
        sessionPath: "/Users/me/app/.annotate/sessions/20261028-141502-a1b2"
    )

    @Test func headerDescribesScreen() {
        #expect(prompt.hasPrefix("I annotated the running app (3 annotations)."))
        #expect(prompt.contains("Screen: iPhone 17 Pro · iOS 26.0 · 402×874 pt @3x · dark · Dynamic Type L"))
        #expect(prompt.contains("Screenshot with numbered pins: /Users/me/app/.annotate/sessions/20261028-141502-a1b2/annotated.png"))
    }

    @Test func itemsAreOrderedByIndex() throws {
        let one = try #require(prompt.range(of: "1. Button"))
        let two = try #require(prompt.range(of: "2. Text"))
        let three = try #require(prompt.range(of: "3. Region"))
        #expect(one.lowerBound < two.lowerBound && two.lowerBound < three.lowerBound)
    }

    @Test func elementItemCarriesSourceCommentAndCrop() {
        #expect(prompt.contains("1. Button \"Get started\" — inside `HeroCard` at App/HomeView.swift:42"))
        #expect(prompt.contains("   bigger, tighter"))
        #expect(prompt.contains("   Crop: /Users/me/app/.annotate/sessions/20261028-141502-a1b2/crops/1.png"))
    }

    @Test func unmappedElementAsksAgentToSearch() {
        #expect(prompt.contains("2. Text \"Adaptive lamps for every room\" — no source mapping; search for its text or label"))
        #expect(prompt.contains("   Change the copy from \"Adaptive lamps for every room\" to \"Smart light that sets itself\""))
    }

    @Test func regionItemDescribesSketch() {
        #expect(prompt.contains("3. Region 352×166 at (16, 420) — inside `HomeView` at App/HomeView.swift:12"))
        #expect(prompt.contains("   Sketch of the desired layout (rectangle, arrow)"))
    }

    @Test func singularAndRelativePathsWithoutSessionPath() {
        let single = PromptRenderer.render(Fixtures.session(annotations: [Fixtures.element]), sessionPath: nil)
        #expect(single.hasPrefix("I annotated the running app (1 annotation)."))
        #expect(single.contains("   Crop: crops/1.png"))
        #expect(single.contains("Session: 20261028-141502-a1b2"))
    }
}

@Suite struct SessionWriterTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("annotate-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesBundleLayout() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent(".annotate")
        let session = Fixtures.session(annotations: [Fixtures.element])
        let bundle = SessionBundle(session: session, images: ["screenshot.png": Data([1, 2]), "crops/1.png": Data([3])])

        let dir = try SessionWriter.write(bundle, prompt: "hello\n", to: output)

        #expect(dir.lastPathComponent == session.id)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("session.json").path))
        #expect(try String(contentsOf: dir.appendingPathComponent("prompt.md"), encoding: .utf8) == "hello\n")
        #expect(try Data(contentsOf: dir.appendingPathComponent("crops/1.png")) == Data([3]))
        #expect(try String(contentsOf: output.appendingPathComponent(".gitignore"), encoding: .utf8) == "*\n")
        #expect(try String(contentsOf: output.appendingPathComponent("latest"), encoding: .utf8) == "sessions/\(session.id)\n")

        let decoded = try AnnotationSession.decoder.decode(AnnotationSession.self, from: Data(contentsOf: dir.appendingPathComponent("session.json")))
        #expect(decoded == session)
    }

    @Test func sessionIDIsSortableUTC() {
        let id = SessionWriter.makeSessionID(date: Date(timeIntervalSince1970: 0), suffix: "abcd")
        #expect(id == "19700101-000000-abcd")
    }

    @Test func locatesGitRootAboveSourceFile() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let sources = root.appendingPathComponent("App/Sources")
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        // A nested package is a fallback marker only; the git root wins
        try Data().write(to: root.appendingPathComponent("App/Package.swift"))
        let file = sources.appendingPathComponent("MyApp.swift").path

        let located = try #require(ProjectRoot.locate(fromSourceFile: file))
        #expect(located.standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(ProjectRoot.relativePath(of: file, to: located) == "App/Sources/MyApp.swift")
    }

    @Test func fallsBackToProjectMarkerWithoutGit() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Demo.xcodeproj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Demo"), withIntermediateDirectories: true)
        let located = ProjectRoot.locate(fromSourceFile: root.appendingPathComponent("Demo/App.swift").path)
        #expect(located?.standardizedFileURL.path == root.standardizedFileURL.path)
    }

    @Test func nilForPathsThatDoNotExist() {
        #expect(ProjectRoot.locate(fromSourceFile: "/definitely/not/here/App.swift") == nil)
        #expect(ProjectRoot.relativePath(of: "/elsewhere/A.swift", to: URL(fileURLWithPath: "/p")) == "/elsewhere/A.swift")
    }

    @Test func contentSizeShortNames() {
        #expect(ContentSizeName.short("UICTContentSizeCategoryL") == "L")
        #expect(ContentSizeName.short("UICTContentSizeCategoryAccessibilityXXXL") == "AX5")
        #expect(ContentSizeName.short("custom") == "custom")
    }
}

// Session schema round-trip, prompt rendering, screen outline hints, bundle layout on disk,
// delivery status/claiming, and project-root discovery.

#if canImport(CoreGraphics)
// CGRect's initializers and Equatable conformance live in the CoreGraphics overlay on Apple platforms
import CoreGraphics
#endif
import Foundation
import Testing
@testable import AnnotateCore

enum Fixtures {
    static let device = DeviceInfo(
        model: "iPhone 17 Pro", systemName: "iOS", systemVersion: "26.0", isSimulator: true,
        screen: AnnotationSize(width: 402, height: 874), scale: 3, colorScheme: "dark",
        contentSize: "L", orientation: "portrait"
    )

    static let screen = Screen(
        index: 1,
        capturedAt: Date(timeIntervalSince1970: 1_793_196_900),
        size: AnnotationSize(width: 402, height: 874),
        image: "screens/1.png",
        annotatedImage: "screens/1-annotated.png",
        hiResImage: "screens/1@3x.png",
        elements: [ScreenElement(role: "button", label: "Get started", frame: AnnotationRect(x: 24, y: 300, width: 120, height: 44))]
    )

    static func session(annotations: [Annotation], screens: [Screen] = [screen]) -> AnnotationSession {
        AnnotationSession(
            id: "20261028-141502-a1b2",
            createdAt: Date(timeIntervalSince1970: 1_793_196_902),
            app: AppInfo(bundleID: "com.example.app", name: "Example", version: "1.0", build: "7"),
            device: device,
            screens: screens,
            annotations: annotations
        )
    }

    static let element = Annotation(
        index: 1, kind: .element, comment: "bigger, tighter",
        anchor: AnnotationPoint(x: 84, y: 322),
        frame: AnnotationRect(x: 24, y: 300, width: 120, height: 44),
        element: ElementInfo(role: "button", label: "Get started", traits: ["button"], breadcrumb: ["HeroCard"]),
        source: SourceLocation(name: "HeroCard", file: "App/HomeView.swift", line: 42, match: .enclosing),
        nearbyText: ["Light that follows your day"],
        crop: "crops/1.png"
    )

    static let copyEdit = Annotation(
        index: 2, kind: .element,
        frame: AnnotationRect(x: 24, y: 200, width: 300, height: 20),
        element: ElementInfo(role: "text", label: "Adaptive lamps for every room"),
        textEdit: TextEdit(from: "Adaptive lamps for every room", to: "Smart light that sets itself"),
        crop: "crops/2.png"
    )

    static let spot = Annotation(
        index: 3, kind: .point, comment: "too much empty space here",
        anchor: AnnotationPoint(x: 201, y: 700),
        frame: AnnotationRect(x: 179, y: 678, width: 44, height: 44)
    )

    static let region = Annotation(
        index: 4, kind: .region, comment: "add a signup card here",
        frame: AnnotationRect(x: 16, y: 420, width: 352, height: 166),
        sketch: Sketch(size: AnnotationSize(width: 352, height: 166), strokes: [
            Stroke(tool: .rectangle, points: [AnnotationPoint(x: 4, y: 4), AnnotationPoint(x: 340, y: 150)]),
            Stroke(tool: .arrow, points: [AnnotationPoint(x: 200, y: -20), AnnotationPoint(x: 220, y: 10)])
        ]),
        crop: "crops/4.png"
    )
}

@Suite struct SessionCodableTests {
    @Test func roundTripsThroughJSON() throws {
        let session = Fixtures.session(annotations: [Fixtures.element, Fixtures.copyEdit, Fixtures.spot, Fixtures.region])
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

    @Test func anchorDefaultsToFrameCenter() {
        #expect(Fixtures.region.anchor == AnnotationPoint(x: 192, y: 503))
        #expect(Fixtures.element.anchor == AnnotationPoint(x: 84, y: 322))
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

    @Test func annotationsAreGroupedByScreen() {
        var second = Fixtures.spot
        second.screen = 2
        let session = Fixtures.session(annotations: [Fixtures.region, second, Fixtures.element])
        #expect(session.annotations(on: Fixtures.screen).map(\.index) == [1, 4])
    }
}

@Suite struct PromptRendererTests {
    let path = "/Users/me/app/.annotate/sessions/20261028-141502-a1b2"
    var prompt: String {
        PromptRenderer.render(
            Fixtures.session(annotations: [Fixtures.region, Fixtures.element, Fixtures.copyEdit, Fixtures.spot]),
            sessionPath: path,
            completion: "When you're done, report back."
        )
    }

    @Test func headerExplainsCoordinates() {
        #expect(prompt.hasPrefix("UI annotations from the running app: 4 pins on 1 screen."))
        #expect(prompt.contains("Device: iPhone 17 Pro · iOS 26.0 · 402×874 pt @3x · dark · Dynamic Type L"))
        #expect(prompt.contains("Coordinates are iOS points, origin top-left. Screen images are 1x, so pixel = point."))
    }

    @Test func screenLineListsImages() {
        #expect(prompt.contains("Screen 1 (402×874 pt) — annotated \(path)/screens/1-annotated.png · clean \(path)/screens/1.png · hi-res \(path)/screens/1@3x.png"))
    }

    @Test func itemsAreOrderedByIndex() throws {
        let one = try #require(prompt.range(of: "1. Button"))
        let two = try #require(prompt.range(of: "2. Text"))
        let three = try #require(prompt.range(of: "3. Spot"))
        let four = try #require(prompt.range(of: "4. Region"))
        #expect(one.lowerBound < two.lowerBound && two.lowerBound < three.lowerBound && three.lowerBound < four.lowerBound)
    }

    @Test func elementItemCarriesCoordinatesHintsAndSource() {
        #expect(prompt.contains("1. Button \"Get started\" at (24, 300, 120×44) — tapped (84, 322), 21% across, 37% down"))
        #expect(prompt.contains("   bigger, tighter"))
        #expect(prompt.contains("   Nearby text: \"Light that follows your day\""))
        #expect(prompt.contains("   Source: inside `HeroCard` at App/HomeView.swift:42"))
        #expect(prompt.contains("   Crop: \(path)/crops/1.png"))
    }

    @Test func copyEditAndSpot() {
        #expect(prompt.contains("   Change the copy from \"Adaptive lamps for every room\" to \"Smart light that sets itself\""))
        #expect(prompt.contains("3. Spot at (179, 678, 44×44) — tapped (201, 700), 50% across, 80% down"))
    }

    @Test func regionUsesCenterAndDescribesSketch() {
        #expect(prompt.contains("4. Region at (16, 420, 352×166) — center (192, 503), 48% across, 58% down"))
        #expect(prompt.contains("   Sketch of the desired layout drawn in red (rectangle, arrow); see the crop"))
    }

    @Test func sketchNamesTheViewItWasDrawnOver() {
        let sketch = Annotation(
            index: 1, kind: .sketch, comment: "make this pop",
            frame: AnnotationRect(x: 20, y: 290, width: 140, height: 64),
            element: ElementInfo(role: "button", label: "Get started"),
            sketch: Sketch(size: AnnotationSize(width: 140, height: 64), strokes: [
                Stroke(tool: .ellipse, points: [AnnotationPoint(x: 0, y: 0), AnnotationPoint(x: 140, y: 64)])
            ])
        )
        let text = PromptRenderer.render(Fixtures.session(annotations: [sketch]), sessionPath: nil)
        #expect(text.contains("1. Sketch over Button \"Get started\" at (20, 290, 140×64) — center (90, 322), 22% across, 37% down"))
        #expect(text.contains("   Drawn on the screen in red (ellipse); see the crop"))
    }

    @Test func completionIsLast() {
        #expect(prompt.hasSuffix("When you're done, report back.\n"))
    }

    @Test func screensWithoutPinsAreSkipped() {
        let empty = Screen(index: 2, capturedAt: Date(), size: AnnotationSize(width: 402, height: 874))
        let text = PromptRenderer.render(Fixtures.session(annotations: [Fixtures.element], screens: [Fixtures.screen, empty]), sessionPath: nil)
        #expect(text.hasPrefix("UI annotations from the running app: 1 pin on 1 screen."))
        #expect(!text.contains("Screen 2"))
        #expect(text.contains("   Crop: crops/1.png"))
    }
}

@Suite struct ScreenOutlineTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    func element(_ label: String, _ x: Double, _ y: Double, _ w: Double = 100, _ h: Double = 20) -> ScreenElement {
        ScreenElement(role: "text", label: label, frame: AnnotationRect(x: x, y: y, width: w, height: h))
    }

    @Test func normalizedSortsDedupesAndDropsOffscreen() {
        let elements = [
            element("Below", 10, 300),
            element("Title", 10, 100),
            element("Title", 11, 101),       // same text through another layer
            element("  ", 10, 200),
            element("Offscreen", 10, 900),
            element("Multi\nline", 10, 150)
        ]
        let result = ScreenOutline.normalized(elements, in: bounds)
        #expect(result.map(\.label) == ["Title", "Multi line", "Below"])
    }

    @Test func normalizedRespectsLimit() {
        let many = (0..<10).map { element("Row \($0)", 0, Double($0) * 30) }
        #expect(ScreenOutline.normalized(many, in: bounds, limit: 3).count == 3)
    }

    @Test func nearbyTextIsNearestFirstAndExcludesOwnLabel() {
        let elements = [
            element("Far", 10, 600),
            element("Below button", 20, 360),
            element("Get started", 24, 300, 120, 44),
            element("Above", 20, 270)
        ]
        let frame = CGRect(x: 24, y: 300, width: 120, height: 44)
        let near = ScreenOutline.nearbyText(for: frame, in: elements, excluding: "Get started")
        #expect(near == ["Above", "Below button"])
    }

    @Test func layoutHasMovedOnlyWhenACommonElementShifts() {
        let frozen = [element("Title", 10, 100), element("Row", 10, 300), element("Row", 10, 340)]
        // Same places; a new element and a changed label don't count
        #expect(!ScreenOutline.hasMoved(from: frozen, to: [element("Title", 10.5, 100), element("Row", 10, 340), element("Clock 9:41", 0, 0)]))
        // Content slid up for a keyboard
        #expect(ScreenOutline.hasMoved(from: frozen, to: [element("Title", 10, -41), element("Row", 10, 159)]))
        // Nothing in common: no evidence it held still
        #expect(ScreenOutline.hasMoved(from: frozen, to: [element("Other", 10, 100)]))
        #expect(ScreenOutline.hasMoved(from: [], to: []))
    }
}

@Suite struct SessionWriterTests {
    func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("annotate-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ session: AnnotationSession, to output: URL) throws -> URL {
        let bundle = SessionBundle(session: session, images: ["screens/1.png": Data([1, 2]), "crops/1.png": Data([3])])
        return try SessionWriter.write(bundle, prompt: "hello\n", to: output)
    }

    @Test func writesBundleLayout() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent(".annotate")
        let session = Fixtures.session(annotations: [Fixtures.element])

        let dir = try write(session, to: output)

        #expect(dir.lastPathComponent == session.id)
        #expect(try String(contentsOf: dir.appendingPathComponent("prompt.md"), encoding: .utf8) == "hello\n")
        #expect(try Data(contentsOf: dir.appendingPathComponent("crops/1.png")) == Data([3]))
        #expect(try Data(contentsOf: dir.appendingPathComponent("screens/1.png")) == Data([1, 2]))
        #expect(try String(contentsOf: output.appendingPathComponent(".gitignore"), encoding: .utf8) == "*\n")
        #expect(try String(contentsOf: output.appendingPathComponent("latest"), encoding: .utf8) == "sessions/\(session.id)\n")
        #expect(try SessionInbox.loadSession(id: session.id, in: output) == session)
        #expect(try SessionInbox.loadPrompt(id: session.id, in: output) == "hello\n")
    }

    @Test func pendingClaimAndStatusLifecycle() throws {
        let output = try tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        var first = Fixtures.session(annotations: [Fixtures.element])
        first.id = "20261028-100000-aaaa"
        var second = first
        second.id = "20261028-100500-bbbb"
        _ = try write(second, to: output)
        _ = try write(first, to: output)

        #expect(SessionInbox.pendingSessionIDs(in: output) == [first.id, second.id])

        #expect(SessionInbox.claim(id: first.id, in: output))
        #expect(SessionInbox.claim(id: first.id, in: output) == false)
        #expect(SessionInbox.readStatus(id: first.id, in: output)?.state == .received)
        #expect(SessionInbox.pendingSessionIDs(in: output) == [second.id])

        try SessionInbox.writeStatus(SessionStatus(state: .done, message: "Edited HomeView.swift"), id: first.id, in: output)
        let status = try #require(SessionInbox.readStatus(id: first.id, in: output))
        #expect(status.isFinal)
        #expect(status.message == "Edited HomeView.swift")
    }

    @Test func sinceSkipsOlderSessions() throws {
        let output = try tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        for id in ["20261028-100000-aaaa", "20261028-110000-bbbb", "20261028-120000-cccc"] {
            var session = Fixtures.session(annotations: [Fixtures.element])
            session.id = id
            _ = try write(session, to: output)
        }
        #expect(SessionInbox.sessionIDs(in: output, since: "20261028-110000-") == ["20261028-110000-bbbb", "20261028-120000-cccc"])
        #expect(SessionInbox.pendingSessionIDs(in: output, since: "20261028-115959-") == ["20261028-120000-cccc"])
    }

    @Test func pruneKeepsNewest() throws {
        let output = try tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let ids = ["20261028-100000-aaaa", "20261028-110000-bbbb", "20261028-120000-cccc"]
        for id in ids {
            var session = Fixtures.session(annotations: [Fixtures.element])
            session.id = id
            _ = try write(session, to: output)
        }
        // Three days after: all three are outside the history window
        let later = Self.utc("20261031-120000")
        #expect(SessionInbox.prune(keeping: 2, in: output, now: later) == ["20261028-100000-aaaa"])
        #expect(SessionInbox.sessionIDs(in: output) == Array(ids.dropFirst()))
        #expect(SessionInbox.prune(keeping: 5, in: output, now: later).isEmpty)
    }

    @Test func pruneNeverRemovesASessionInsideTheHistoryWindow() throws {
        let output = try tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        // 50 h, 47 h and 1 h before `now`
        let ids = ["20261027-100000-aaaa", "20261027-130000-bbbb", "20261029-110000-cccc"]
        for id in ids {
            var session = Fixtures.session(annotations: [Fixtures.element])
            session.id = id
            _ = try write(session, to: output)
        }
        let now = Self.utc("20261029-120000")
        #expect(SessionInbox.prune(keeping: 1, in: output, now: now) == ["20261027-100000-aaaa"])
        #expect(SessionInbox.sessionIDs(in: output) == Array(ids.dropFirst()))
    }

    @Test func historyCutoffIsFortyEightHoursBeforeNow() {
        let cutoff = SessionInbox.historyCutoffID(now: Self.utc("20261029-120000"))
        #expect(cutoff == "20261027-120000-")
        // A Send at the cutoff second is inside; one a second earlier isn't
        #expect("20261027-120000-abcd" >= cutoff)
        #expect("20261027-115959-abcd" < cutoff)
    }

    private static func utc(_ stamp: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.date(from: stamp)!
    }

    @Test func incompleteBundlesAreNotListed() throws {
        let output = try tempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let partial = SessionInbox.sessionDirectory("20261028-000000-cccc", in: output)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try Data("prompt".utf8).write(to: partial.appendingPathComponent("prompt.md"))
        #expect(SessionInbox.sessionIDs(in: output).isEmpty)
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

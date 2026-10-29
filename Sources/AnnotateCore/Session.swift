// The on-disk session schema (session.json). Coordinates are the contract: every frame and point is
// in screen points, origin top-left, and each screen's `image` is rendered at 1x so its pixels ARE
// points — an agent can look at the PNG and the numbers line up exactly. Hi-res captures and crops
// are there for detail. Element info and nearby text are hints for finding the source, not required.
// Each pin may carry an `AnnotationIntent` (fix, question) that tells the agent what
// kind of response the user wants; it's optional, and a missing intent means fix.
// Bump `AnnotationSession.currentSchemaVersion` on any breaking change to these types.

#if canImport(CoreGraphics)
// CGRect's initializers and Equatable conformance live in the CoreGraphics overlay on Apple platforms
import CoreGraphics
#endif
import Foundation

public struct AnnotationSession: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var createdAt: Date
    public var app: AppInfo
    public var device: DeviceInfo
    /// One entry per freeze-frame captured while annotating (entering annotate mode captures one).
    public var screens: [Screen]
    public var annotations: [Annotation]

    public init(
        id: String,
        createdAt: Date,
        app: AppInfo,
        device: DeviceInfo,
        screens: [Screen],
        annotations: [Annotation]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.app = app
        self.device = device
        self.screens = screens
        self.annotations = annotations
    }

    public func annotations(on screen: Screen) -> [Annotation] {
        annotations.filter { $0.screen == screen.index }.sorted { $0.index < $1.index }
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// A freeze-frame of the app, captured automatically when annotate mode starts.
public struct Screen: Codable, Sendable, Equatable, Identifiable {
    /// 1-based; annotations refer to it via `Annotation.screen`.
    public var index: Int
    public var capturedAt: Date
    /// Screen size in points.
    public var size: AnnotationSize
    /// 1x PNG: one pixel per point, so annotation coordinates are pixel coordinates in it.
    public var image: String?
    /// Same image with every pin's marker, outline and sketch drawn on, also 1x.
    public var annotatedImage: String?
    /// Native-resolution capture for detail.
    public var hiResImage: String?
    /// Visible text and controls, for grepping the source. Not exhaustive.
    public var elements: [ScreenElement]

    public var id: Int { index }

    public init(
        index: Int,
        capturedAt: Date,
        size: AnnotationSize,
        image: String? = nil,
        annotatedImage: String? = nil,
        hiResImage: String? = nil,
        elements: [ScreenElement] = []
    ) {
        self.index = index
        self.capturedAt = capturedAt
        self.size = size
        self.image = image
        self.annotatedImage = annotatedImage
        self.hiResImage = hiResImage
        self.elements = elements
    }
}

public struct ScreenElement: Codable, Sendable, Equatable {
    public var role: String
    public var label: String
    public var frame: AnnotationRect

    public init(role: String, label: String, frame: AnnotationRect) {
        self.role = role
        self.label = label
        self.frame = frame
    }
}

public struct AppInfo: Codable, Sendable, Equatable {
    public var bundleID: String?
    public var name: String?
    public var version: String?
    public var build: String?
    /// Path of the source file that called `Annotate.install()`, on the Mac that built the app.
    /// A device can't see that path, but the Mac can: walking up from it finds the checkout the
    /// build came from, so a device's Send reaches the agent working in that checkout. Optional,
    /// so bundles from older builds still decode.
    public var installFile: String?

    public init(bundleID: String? = nil, name: String? = nil, version: String? = nil, build: String? = nil, installFile: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.build = build
        self.installFile = installFile
    }
}

public struct DeviceInfo: Codable, Sendable, Equatable {
    /// Marketing name when known ("iPhone 17 Pro"), else the hardware identifier.
    public var model: String
    public var systemName: String
    public var systemVersion: String
    public var isSimulator: Bool
    /// Screen size in points.
    public var screen: AnnotationSize
    public var scale: Double
    /// "light" or "dark".
    public var colorScheme: String
    /// Short Dynamic Type name: "L" (default), "XL", "AX2"…
    public var contentSize: String
    public var orientation: String

    public init(
        model: String,
        systemName: String,
        systemVersion: String,
        isSimulator: Bool,
        screen: AnnotationSize,
        scale: Double,
        colorScheme: String,
        contentSize: String,
        orientation: String
    ) {
        self.model = model
        self.systemName = systemName
        self.systemVersion = systemVersion
        self.isSimulator = isSimulator
        self.screen = screen
        self.scale = scale
        self.colorScheme = colorScheme
        self.contentSize = contentSize
        self.orientation = orientation
    }
}

public struct Annotation: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Pinned to a view picked by tapping.
        case element
        /// Pinned to a spot: the tap didn't land on a distinct element, or the user stepped below one.
        case point
        /// A dragged rectangle, optionally with a sketch inside.
        case region
        /// A freehand drawing anywhere on the screen; `frame` is the drawing's bounds and
        /// `element` the view it was drawn over, when one encloses it.
        case sketch
    }

    public var id: UUID
    /// 1-based number shown on the pin. Contiguous after deletes.
    public var index: Int
    /// `Screen.index` this pin was placed on.
    public var screen: Int
    public var kind: Kind
    public var comment: String
    /// Exactly where the user pointed (the tap, or a region's center). Screen points.
    public var anchor: AnnotationPoint
    /// The box the comment is about. Screen points, origin top-left.
    public var frame: AnnotationRect
    public var element: ElementInfo?
    public var source: SourceLocation?
    public var textEdit: TextEdit?
    public var sketch: Sketch?
    /// Visible text around the frame, nearest first — grep hints for finding the view.
    public var nearbyText: [String]
    /// PNG crop with context padding, relative to the session directory.
    public var crop: String?
    /// Attached reference images, relative to the session directory ("attachments/1-1.jpg"); nil when none.
    public var attachments: [String]?
    /// What the user wants done with this pin. Optional so bundles from older builds still decode;
    /// nil means `.fix`.
    public var intent: AnnotationIntent?

    public init(
        id: UUID = UUID(),
        index: Int,
        screen: Int = 1,
        kind: Kind,
        comment: String = "",
        anchor: AnnotationPoint? = nil,
        frame: AnnotationRect,
        element: ElementInfo? = nil,
        source: SourceLocation? = nil,
        textEdit: TextEdit? = nil,
        sketch: Sketch? = nil,
        nearbyText: [String] = [],
        crop: String? = nil,
        attachments: [String]? = nil,
        intent: AnnotationIntent? = nil
    ) {
        self.id = id
        self.index = index
        self.screen = screen
        self.kind = kind
        self.comment = comment
        self.anchor = anchor ?? AnnotationPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        self.frame = frame
        self.element = element
        self.source = source
        self.textEdit = textEdit
        self.sketch = sketch
        self.nearbyText = nearbyText
        self.crop = crop
        self.attachments = attachments
        self.intent = intent
    }

    /// True when there is nothing for an agent to act on.
    public var isEmpty: Bool {
        comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && textEdit == nil
            && (sketch?.strokes.isEmpty ?? true)
            && (attachments?.isEmpty ?? true)
    }
}

extension Annotation {
    /// The pin moved by (`dx`, `dy`) screen points; the sketch is frame-local, so it follows the frame.
    public func translated(dx: Double, dy: Double) -> Annotation {
        var moved = self
        moved.anchor = AnnotationPoint(x: anchor.x + dx, y: anchor.y + dy)
        moved.frame = AnnotationRect(x: frame.x + dx, y: frame.y + dy, width: frame.width, height: frame.height)
        return moved
    }

    /// `sketch` strokes moved from frame-local to screen points (empty without a sketch).
    public var sketchInScreenPoints: [Stroke] {
        guard let sketch else { return [] }
        return sketch.strokes.map { stroke in
            Stroke(
                tool: stroke.tool,
                points: stroke.points.map { AnnotationPoint(x: $0.x + frame.x, y: $0.y + frame.y) }
            )
        }
    }
}

/// What the user wants done with a pin, picked on the comment card. Older bundles have none: treat nil as .fix.
public enum AnnotationIntent: String, Codable, Sendable, CaseIterable {
    case fix, question

    /// An intent this version doesn't know (e.g. `approve` or `move`, both since removed) reads as
    /// Fix, so an older or newer bundle still loads.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnnotationIntent(rawValue: raw) ?? .fix
    }

    /// Chip and menu title.
    public var title: String {
        switch self {
        case .fix: "Fix"
        case .question: "Question"
        }
    }

    /// Menu subtitle.
    public var detail: String {
        switch self {
        case .fix: "Change the code"
        case .question: "Explain it, don't edit"
        }
    }

    /// SF Symbol for the menu.
    public var symbol: String {
        switch self {
        case .fix: "hammer"
        case .question: "questionmark.bubble"
        }
    }

    /// Comment placeholder. Fix reuses the overlay's default so the card reads the same as before intents.
    public var placeholder: String {
        switch self {
        case .fix: OverlayChrome.placeholder
        case .question: "Ask about it"
        }
    }

    /// Tag in prompt.md. Fix has none, so prompts for plain fixes read as they did before intents.
    public var promptTag: String? {
        switch self {
        case .fix: nil
        case .question: "[Question]"
        }
    }
}

extension Annotation {
    /// The element's own text, quoted on the comment card like a message being replied to: its
    /// label, else its value, trimmed. Nil for spots, sketches, regions and elements with no text.
    public var quotedText: String? {
        guard kind == .element, let element else { return nil }
        for candidate in [element.label, element.value] {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { return text }
        }
        return nil
    }
}

public struct ElementInfo: Codable, Sendable, Equatable {
    /// Normalized role: "button", "text", "image", "header", "textField", "toggle", "view"…
    public var role: String
    /// UIKit class name, or the name passed to `.annotatable("Name")`.
    public var typeName: String?
    public var label: String?
    public var value: String?
    public var identifier: String?
    public var traits: [String]
    /// Enclosing elements, nearest first ("HStack", "HeroCard", "ScrollView"…), for orientation.
    public var breadcrumb: [String]

    public init(
        role: String,
        typeName: String? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: [String] = [],
        breadcrumb: [String] = []
    ) {
        self.role = role
        self.typeName = typeName
        self.label = label
        self.value = value
        self.identifier = identifier
        self.traits = traits
        self.breadcrumb = breadcrumb
    }
}

public struct SourceLocation: Codable, Sendable, Equatable {
    public enum Match: String, Codable, Sendable {
        /// The annotated view itself carries `.annotatable()`.
        case exact
        /// The nearest `.annotatable()` ancestor; the element lives somewhere inside it.
        case enclosing
    }

    public var name: String?
    /// Project-relative path when the project root is known, else the absolute `#filePath`.
    public var file: String
    public var line: Int
    public var match: Match

    public init(name: String? = nil, file: String, line: Int, match: Match) {
        self.name = name
        self.file = file
        self.line = line
        self.match = match
    }
}

public struct TextEdit: Codable, Sendable, Equatable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

public struct Sketch: Codable, Sendable, Equatable {
    /// Size of the annotation's frame. Stroke points are in the frame's local space (origin = frame
    /// origin); on element and spot pins a drawing can reach outside the frame, so points may be
    /// negative or beyond `size`. `Annotation.sketchInScreenPoints` converts them back to screen points.
    public var size: AnnotationSize
    public var strokes: [Stroke]

    public init(size: AnnotationSize, strokes: [Stroke] = []) {
        self.size = size
        self.strokes = strokes
    }
}

public struct Stroke: Codable, Sendable, Equatable {
    public enum Tool: String, Codable, Sendable, CaseIterable {
        case pen, ellipse, rectangle, arrow
    }

    public var tool: Tool
    /// Pen: every sampled point. Shapes and arrows: [start, end].
    public var points: [AnnotationPoint]

    public init(tool: Tool, points: [AnnotationPoint]) {
        self.tool = tool
        self.points = points
    }
}

// MARK: - Geometry

// Schema-owned geometry so session.json reads `{"x":…,"y":…}` on every platform instead of
// CGRect's nested-array Codable form.

public struct AnnotationPoint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

public struct AnnotationSize: Codable, Sendable, Hashable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

public struct AnnotationRect: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Rounds to 0.1pt so JSON stays readable.
    public init(_ rect: CGRect) {
        func round1(_ value: CGFloat) -> Double { (Double(value) * 10).rounded() / 10 }
        self.init(x: round1(rect.origin.x), y: round1(rect.origin.y), width: round1(rect.size.width), height: round1(rect.size.height))
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

// The on-disk session schema (session.json). Everything an agent needs to act on a batch of
// annotations: what was pinned, where it is on screen, which source file it likely lives in, and
// relative paths to the PNG crops written next to the JSON.
// Bump `AnnotationSession.currentSchemaVersion` on any breaking change to these types.

import Foundation

public struct AnnotationSession: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var createdAt: Date
    public var app: AppInfo
    public var device: DeviceInfo
    /// Clean full-screen capture, relative to the session directory.
    public var screenshot: String?
    /// Same capture with every annotation's outline, number and sketch burned in.
    public var annotatedScreenshot: String?
    public var annotations: [Annotation]

    public init(
        id: String,
        createdAt: Date,
        app: AppInfo,
        device: DeviceInfo,
        screenshot: String? = nil,
        annotatedScreenshot: String? = nil,
        annotations: [Annotation]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.app = app
        self.device = device
        self.screenshot = screenshot
        self.annotatedScreenshot = annotatedScreenshot
        self.annotations = annotations
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

public struct AppInfo: Codable, Sendable, Equatable {
    public var bundleID: String?
    public var name: String?
    public var version: String?
    public var build: String?

    public init(bundleID: String? = nil, name: String? = nil, version: String? = nil, build: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.build = build
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
        /// A dragged rectangle, optionally with a sketch inside.
        case region
    }

    public var id: UUID
    /// 1-based number shown on the pin. Contiguous after deletes.
    public var index: Int
    public var kind: Kind
    public var comment: String
    /// Screen points, origin top-left.
    public var frame: AnnotationRect
    public var element: ElementInfo?
    public var source: SourceLocation?
    public var textEdit: TextEdit?
    public var sketch: Sketch?
    /// PNG crop with context padding, relative to the session directory.
    public var crop: String?

    public init(
        id: UUID = UUID(),
        index: Int,
        kind: Kind,
        comment: String = "",
        frame: AnnotationRect,
        element: ElementInfo? = nil,
        source: SourceLocation? = nil,
        textEdit: TextEdit? = nil,
        sketch: Sketch? = nil,
        crop: String? = nil
    ) {
        self.id = id
        self.index = index
        self.kind = kind
        self.comment = comment
        self.frame = frame
        self.element = element
        self.source = source
        self.textEdit = textEdit
        self.sketch = sketch
        self.crop = crop
    }

    /// True when there is nothing for an agent to act on.
    public var isEmpty: Bool {
        comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && textEdit == nil
            && (sketch?.strokes.isEmpty ?? true)
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
    /// Region size; stroke points are in this local space.
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

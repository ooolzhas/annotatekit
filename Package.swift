// swift-tools-version: 6.0
// AnnotateKit — Cursor-style visual annotation for iOS apps.
// AnnotateCore is Foundation-only (session schema, selection math, prompt rendering) so it tests on
// macOS and Linux with `swift test`. AnnotateKit is the in-app overlay; it compiles to no-op stubs
// outside DEBUG, so it is safe to link in Release.

import PackageDescription

let package = Package(
    name: "AnnotateKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnnotateKit", targets: ["AnnotateKit"]),
        .library(name: "AnnotateCore", targets: ["AnnotateCore"])
    ],
    targets: [
        .target(name: "AnnotateCore"),
        .target(name: "AnnotateKit", dependencies: ["AnnotateCore"]),
        .testTarget(name: "AnnotateCoreTests", dependencies: ["AnnotateCore"])
    ],
    swiftLanguageModes: [.v6]
)

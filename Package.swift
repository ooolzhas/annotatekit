// swift-tools-version: 6.0
// AnnotateKit — visual feedback for iOS apps, straight to your coding agent.
// AnnotateCore is Foundation-only (session schema, selection math, prompt rendering) so it tests on
// macOS and Linux with `swift test`. AnnotateKit is the in-app overlay; it compiles to no-op stubs
// outside DEBUG, so it is safe to link in Release. The `annotate` executable (AnnotateAgent +
// AnnotateCLI) runs on the Mac and delivers sent sessions to Claude Code.

import PackageDescription

let package = Package(
    name: "AnnotateKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnnotateKit", targets: ["AnnotateKit"]),
        .library(name: "AnnotateCore", targets: ["AnnotateCore"]),
        .executable(name: "annotate", targets: ["AnnotateCLI"])
    ],
    targets: [
        .target(name: "AnnotateCore"),
        .target(name: "AnnotateKit", dependencies: ["AnnotateCore"]),
        .target(name: "AnnotateAgent", dependencies: ["AnnotateCore"]),
        .executableTarget(name: "AnnotateCLI", dependencies: ["AnnotateAgent", "AnnotateCore"]),
        .testTarget(name: "AnnotateCoreTests", dependencies: ["AnnotateCore"]),
        .testTarget(name: "AnnotateAgentTests", dependencies: ["AnnotateAgent", "AnnotateCore"])
    ],
    swiftLanguageModes: [.v6]
)

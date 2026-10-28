---
name: annotate-setup
description: Add AnnotateKit (Cursor-style visual annotation that sends UI feedback from a running iOS app to a coding agent) to an iOS project, and connect the agent so sent annotations arrive automatically. Use when the user wants to annotate, comment on, or sketch over their iOS app's UI for an agent, or asks to install AnnotateKit / annotate-ios.
license: MIT
compatibility: iOS 17+ apps built with Xcode 16+ (SwiftUI or UIKit). Works with Claude Code, Cursor, Codex, VS Code and any MCP client.
---

# Set up AnnotateKit in an iOS project

Goal: the user can tap the pencil in their running app, annotate, hit Send, and you (the agent)
receive it with no copy/paste. Three parts: the package in the app, the `annotate` CLI on the Mac,
and the agent connection. Do them in order and verify each.

## 1. Find the project shape

Look at the repo root:

- `project.yml` → XcodeGen. `Project.swift` / `Tuist/` → Tuist. Edit the manifest, then regenerate.
- `*.xcodeproj` only → edit `project.pbxproj` (section 2b).
- `Package.swift` for the app itself → add a normal SwiftPM dependency.

Find the app entry point: `grep -rn "@main" --include=*.swift`. It's a `struct …: App` (SwiftUI) or
a `UIApplicationDelegate`.

## 2. Add the package

Package URL `https://github.com/ooolzhas/annotate-ios`, product **AnnotateKit**, version `from: "0.1.0"`.
Link it to the **app target only**, not widgets or extensions.

### 2a. Manifests

- XcodeGen `project.yml`: under `packages:` add
  `AnnotateKit: { url: https://github.com/ooolzhas/annotate-ios, from: 0.1.0 }`, and under the app
  target's `dependencies:` add `- package: AnnotateKit`. Run `xcodegen`.
- Tuist: add `.remote(url: "https://github.com/ooolzhas/annotate-ios", requirement: .upToNextMajor(from: "0.1.0"))`
  and `.package(product: "AnnotateKit")` to the app target, then `tuist install && tuist generate`.
- SwiftPM: `.package(url: "https://github.com/ooolzhas/annotate-ios", from: "0.1.0")` and
  `.product(name: "AnnotateKit", package: "annotate-ios")` on the app target.

### 2b. Plain .xcodeproj

Prefer letting the user click **File → Add Package Dependencies…** if they're at the keyboard. If you
edit `project.pbxproj` yourself, add four objects with fresh unique 24-character uppercase hex ids
(check with grep that they're unused), copying the indentation of neighbouring entries:

```
/* in the PBXBuildFile section */
		<BUILD_ID> /* AnnotateKit in Frameworks */ = {isa = PBXBuildFile; productRef = <PRODUCT_ID> /* AnnotateKit */; };

/* in the app target's PBXFrameworksBuildPhase files = ( … ) */
				<BUILD_ID> /* AnnotateKit in Frameworks */,

/* in the app target's PBXNativeTarget packageProductDependencies = ( … ) */
				<PRODUCT_ID> /* AnnotateKit */,

/* in PBXProject packageReferences = ( … ) */
				<PACKAGE_ID> /* XCRemoteSwiftPackageReference "annotate-ios" */,

/* in the XCRemoteSwiftPackageReference section (create it if missing) */
		<PACKAGE_ID> /* XCRemoteSwiftPackageReference "annotate-ios" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/ooolzhas/annotate-ios";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 0.1.0;
			};
		};

/* in the XCSwiftPackageProductDependency section (create it if missing) */
		<PRODUCT_ID> /* AnnotateKit */ = {
			isa = XCSwiftPackageProductDependency;
			package = <PACKAGE_ID> /* XCRemoteSwiftPackageReference "annotate-ios" */;
			productName = AnnotateKit;
		};
```

Then run `xcodebuild -resolvePackageDependencies -project <App>.xcodeproj` to confirm the
project still parses and the package resolves.

## 3. Install the overlay

In the `@main` App, add `import AnnotateKit` and call `Annotate.install()` in `init()`, creating
an `init()` if there isn't one. For a UIKit app delegate, call it in
`application(_:didFinishLaunchingWithOptions:)`.

```swift
init() {
    Annotate.install()   // DEBUG-only overlay; a no-op in Release
}
```

Don't pass the `file:` argument: its default locates the project root. If the app already uses a
shake gesture or the bottom-trailing corner, mention `AnnotateOptions(showsLauncher: false)` plus
calling `Annotate.start()` from a debug menu.

Add `.annotate/` to the project's `.gitignore`.

## 4. Install the CLI

Check `command -v annotate`. If it's missing, use the first of these that works:

- `brew install ooolzhas/tap/annotate`
- `mint install ooolzhas/annotate-ios`
- Claude Code plugin users already have it: `/plugin marketplace add ooolzhas/annotate-ios`,
  then `/plugin install annotate@annotate-ios`.
- From source: `git clone https://github.com/ooolzhas/annotate-ios && cd annotate-ios && swift build -c release --product annotate`,
  then put `.build/release/annotate` on PATH.

## 5. Connect the agent

The MCP server is `annotate mcp`, over stdio, run with the project root as its working directory.

- **Claude Code.** The plugin from step 4 registers it. Without the plugin:
  `claude mcp add annotate --scope project -- annotate mcp`. For push delivery into the open
  session (channels, research preview), the user starts
  `claude --dangerously-load-development-channels plugin:annotate@annotate-ios`, or
  `server:annotate` for the non-plugin setup. That flag only lifts the preview allowlist for this
  server and asks for confirmation. Without channels, use the `annotate-watch` skill, or
  `annotate run` for unattended runs.
- **Cursor** `.cursor/mcp.json`: `{"mcpServers": {"annotate": {"command": "annotate", "args": ["mcp"]}}}`
- **VS Code** `.vscode/mcp.json`: `{"servers": {"annotate": {"type": "stdio", "command": "annotate", "args": ["mcp"]}}}`
- **Codex** `~/.codex/config.toml`: `[mcp_servers.annotate]`, `command = "annotate"`, `args = ["mcp"]`

Without channels, the user says "check my latest annotation" and you call `get_annotation_session`.

## 6. Verify

1. Build the app for the simulator, e.g.
   `xcodebuild build -scheme <App> -destination 'generic/platform=iOS Simulator'`.
2. Tell the user to run it in the Simulator (or launch with `ANNOTATE=1` in the scheme's
   environment to start in annotate mode), tap the pencil, pin something, and hit Send.
3. A bundle appears in `.annotate/sessions/`, and `annotate list` shows it.

Finish by telling the user, in a few lines, how to annotate (tap to pin, drag for a region, the
scribble button to draw, Return to save, Send) and which delivery mode you set up.

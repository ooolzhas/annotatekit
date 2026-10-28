# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- The accessibility tree is enabled the first time annotate mode starts, not at launch.
- `.annotatable()` tracks frames only while annotate mode is on.
- The visible-text outline is scanned lazily, on the first pin of a screen.
- Send renders, encodes and writes off the main thread, in 8-bit sRGB.
- Full high-res screens are opt-in (`AnnotateOptions.includesHiResScreens`). Old sessions are
  pruned after each Send (`keepsSessions`, default 30).
- With `showsLauncher: false`, the overlay window is created on the first `Annotate.start()`.
- The CLI filters old sessions by name before any file-system access.

### Fixed
- The macOS build of AnnotateCore failed because CoreGraphics wasn't imported.
- Launching straight into annotate mode (`ANNOTATE=1`) left the screen's text outline empty.

## [0.1.0] - 2026-10-28

First public release.

### Added
- **AnnotateKit** in-app overlay (DEBUG only, iOS 17+): freeze-frame screens, tap to pin any
  element or exact spot, ↑↓ to walk the element tree, drag for a region with sketch tools, draw
  mode to sketch anywhere on the screen, in-place text retype, keyboard shortcuts.
- Session bundles in `.annotate/sessions/<id>/`: `session.json` (schema v1), `prompt.md`, 1x and
  hi-res screen images, annotated screens, per-pin crops, and `status.json` for delivery progress.
- Live delivery status on the launcher: delivered → received → working → done / failed.
- Optional `.annotatable()` for exact `file:line` source mapping.
- **`annotate` CLI**: `mcp` (Claude Code channel server and tools), `watch`, `run`
  (headless `claude -p` per session), `status`, `list`.
- Agent skills: `annotate-setup` (add AnnotateKit to an app) and `annotations` (watch and act).
- Claude Code plugin and marketplace manifests.

[Unreleased]: https://github.com/ooolzhas/annotate-ios/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ooolzhas/annotate-ios/releases/tag/v0.1.0

# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-28

First public release.

### Added
- **AnnotateKit** in-app overlay (DEBUG only, iOS 17+):
  - Freeze-frame screens.
  - Tap to pin any element or an exact spot, with `↑`/`↓` to walk the element tree.
  - Drag for a region with sketch tools, or use Draw mode to sketch anywhere on the screen.
  - In-place text retype and keyboard shortcuts.
- Session bundles in `.annotate/sessions/<id>/`:
  - `session.json` (schema v1) and `prompt.md`.
  - 1x screen images (pixel = point) and annotated screens.
  - Per-pin crops at native resolution.
  - `status.json` for delivery progress.
  - Full high-res screens are opt-in (`includesHiResScreens`), and the last 30 sessions are kept
    (`keepsSessions`).
- Live delivery status on the launcher: delivered → received → working → done / failed.
- Optional `.annotatable()` for exact `file:line` source mapping.
- **`annotate` CLI**: `mcp` (Claude Code channel server and tools), `watch`, `run` (headless
  `claude -p` per session), `status`, `list`.
- Agent skills: `annotate-setup` (add AnnotateKit to an app) and `annotate-watch` (watch and act).
- Claude Code plugin and marketplace manifests. `bin/annotate` resolves the CLI by downloading the
  release binary, which is checksum-verified.

### Performance
- Nothing heavy runs in DEBUG until you annotate: the accessibility tree, `.annotatable()` frame
  tracking and the text outline all start on first use.
- Send renders, encodes and writes off the main thread, in 8-bit sRGB.

[Unreleased]: https://github.com/ooolzhas/annotate-ios/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ooolzhas/annotate-ios/releases/tag/v0.1.0

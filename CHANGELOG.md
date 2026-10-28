# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Redesigned overlay (Figma SUNSET 9257:13754). Annotate mode dims the frozen screen 50% and draws
  a blue inset glow along the screen edge (62pt radius).
  - **Drawing is the default:** a stroke is a white 4pt pen line, and further strokes join the open
    pin for as long as its comment card is up.
  - **Tap and hold:** a tap selects the whole element under the finger, outlined in white with no
    label chip. Holding still for 0.5s drops a spot.
  - **Comment card:** it always docks to the keyboard, never to the marker. It has the comment, a
    paperclip, × and ↑ (Return also submits).
  - **Review bar:** with no pin open, the bottom bar shows ×, "N comments", trash and Send. Pins are
    white with white number badges.
  - **Removed:** the toolbar and hint, the draw toggle, region dragging, the shape tools, in-place text
    retyping, the selection chip and "Send and keep annotating". The keyboard shortcuts stay.
- The annotated screenshot and crops keep their blue and red markers for contrast. Their strokes are
  now 4pt, and a crop covers the pin's drawing as well as its frame.

### Added
- Reference images: the paperclip opens the photo picker (up to 4 images per pin). Send writes them
  to `attachments/<pin>-<n>.jpg`, and `prompt.md` lists them.
- **Schema (additive, still v1):** `Annotation.attachments: [String]?`. Pins of any kind can now
  carry `sketch` strokes, whose points may extend outside the pin's frame.

### Fixed
- Card placement no longer goes stale after the photo picker. It follows UIKit's keyboard layout
  guide, because keyboard notifications can end on a frame without the suggestion bar.

## [0.1.1] - 2026-10-28

### Fixed
- Freeze-frames, annotated screens and crops came out solid black in apps with a transparent
  window above their content (UIKit's `UITextEffectsWindow` appears once any text input has been
  used; toast windows). The capture context was opaque, which paints a transparent window black;
  captures now use a non-opaque one.
- The first tap after entering annotate mode fell back to a spot instead of the element: SwiftUI
  builds its accessibility nodes only after the first query following the bootstrap. Annotate mode
  now warms the tree as it starts (about 0.1 s) and holds a tap that arrives before it's ready.
- With the comment keyboard up, SwiftUI keyboard avoidance slid the whole overlay (frozen image,
  boxes and pins) up by about 140 pt, so the next tap landed on what was really lower on screen.
  The overlay no longer avoids the keyboard: the comment card and toolbar sit above it, and the
  card keeps clear of the selection chip. If the app itself re-lays out for the keyboard, a tap
  waits for the keyboard to go before scanning.
- A launch-time start (`ANNOTATE=1`) froze the launch screen or the app's splash. It now waits for
  the first screen the app settles on (unchanged for 1 s, after at least 1.5 s and at most 8 s of
  the app being active), so a permission alert holding the app inactive doesn't count.
  `ANNOTATE_DELAY=<seconds>` waits a fixed time instead.
- Late keyboard input from a comment card that a tap had just replaced could land in the next
  pin's comment; it's dropped now.

### Changed
- The screen's text outline is taken as annotate mode starts, once the accessibility tree is warm,
  instead of on the first pin.

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

[Unreleased]: https://github.com/ooolzhas/annotate-ios/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/ooolzhas/annotate-ios/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ooolzhas/annotate-ios/releases/tag/v0.1.0

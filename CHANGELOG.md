# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Releases publish the npm package `annotate-ios` through npm Trusted Publishing (GitHub's OIDC
  identity), so there's no npm token to store or rotate. (npm blocks `annotatekit` as too close to
  an existing `annotate-kit`.)
- annotatekit.com is served by Vercel from `site/` (the redesigned landing page with the iPhone
  demo), replacing the GitHub Pages workflow.
- A note on a picked element puts its number where you tapped, not on the element's top-trailing
  corner, so a large block's pin stays on what you meant. The annotated screenshot matches.

## [0.2.1] - 2026-10-29

### Added
- **Stop hook** (`annotate hook stop`, installed with the Claude Code plugin): when Claude tries to
  end its turn while a Send from this conversation still shows as in progress on the device, the
  hook blocks the stop once and tells it to report each note and `done` (or `failed`). Only Sends
  the conversation's transcript mentions count, a note waiting on the user's answer is left alone,
  and the second stop always goes through. Without the plugin, add it to `.claude/settings.json`
  (see the setup skill).

### Changed
- The `annotate-watch` skill reports `done` right after the reinstall: building and checking come
  before it, so the device stops saying Claude is working as soon as the change is in.

## [0.2.0] - 2026-10-29

A redesigned overlay, a two-way loop with your agent (per-note results, questions, replies), Sends
from a physical iPhone, and a launcher pill that narrates each Send and keeps off your app's bars.

### Added
- **Agent loop:**
  - **`annotation_wait` MCP tool:** blocks until you Send or answer a question, batches for 10 s and
    returns everything, so delivery is hands-free in Cursor, Codex, the Claude desktop app or any
    MCP client, with no channels.
  - **Per-note results:** `annotation_resolve` / `annotation_dismiss` (CLI: `annotate resolve|dismiss
    <id> <pin> "…"`). Each sent pin's badge spins while the agent has it, then shows a check, `?`
    or ×.
  - **Questions:** the agent asks about one note with `annotation_ask` / `annotate ask` and waits.
    You answer on the device from the notes sheet; the reply is saved to `replies.json` and travels
    back from a device too.
  - **Intent per note** (Fix or Question) on a chip in the comment card; prompts tag Question notes.
  - **`AnnotateOptions.promptDetail`:** `.compact`, `.standard` or `.detailed`.
- **Sends from a physical iPhone or iPad** reach your agent with no setup in the app (no network
  permission, no Info.plist keys). `annotate mcp`, `watch` and `run` copy each new bundle from a
  paired device's development build over the developer connection (`devicectl`, USB or Wi-Fi), and
  copy status back so the device narrates too. A Send reaches the checkout its build came from, so
  two worktrees each get their own. `--no-device` turns this off.
- **Notes sheet ("My Notes"):** the review bar's count opens it. It lists unsent notes (tap to
  open, swipe to delete, Clear All) and every Send of the last 48 hours with each note's result
  and Reply, filtered by Current, In Progress, Resolved and Failed tags.
- **Launcher pill:** it narrates the last Send in place of the delivery ring and toasts ("4 notes
  sent", then each stage the agent reports), and its dot always shows the connection: green while an
  agent listens, yellow while its heartbeat is late, red when nothing does.
- **Launcher collision avoidance:** the idle pill keeps off the app's own bottom chrome (tab bars,
  toolbars, text inputs, controls outside scroll views, a container's reserved bottom safe area),
  lifting above it or moving to a side. A dragged pill stays put, and the keyboard dock still wins.
- **`.annotateAvoid()`:** tags a view the launcher should keep off, for bars SwiftUI draws itself.
  An empty stub in Release.
- **npm package `annotate-ios`:** `npx -y annotate-ios mcp` runs the MCP server with nothing
  installed; it downloads the release's checksum-verified binary on first run (macOS).
- **Reference images:** the paperclip attaches up to 4 photos per note
  (`attachments/<pin>-<n>.jpg`, listed in `prompt.md`).
- **Pins follow scrolled content:** back in annotate mode after scrolling, pins move with the scroll
  view's content; pins scrolled out of view come back with it.
- **Agent presence:** every `annotate` process writes a heartbeat to `.annotate/agents/`, merged
  into `.annotate/agent.json` for the app.
- Haptics on every delivery stage: a tick while a Send moves along, success when it's done, a warning
  for a question or an unclaimed Send, an error when it failed.
- **`SCHEMA.md`** documents every file the app and agents exchange. Schema additions (still v1):
  `Annotation.intent`, `Annotation.attachments`, `SessionStatus.pins`, `AppInfo.installFile`,
  `replies.json`; pins of any kind can carry `sketch` strokes.

### Changed
- **Redesigned overlay.** Annotate mode dims the frozen screen and draws a slowly drifting blue edge
  glow, which turns green while the agent works. Liquid Glass bottom chrome, Reduce Motion
  respected throughout.
  - **Draw, tap or hold:** drawing is the default (a white pen, and further strokes join the open
    note), a tap selects the element under your finger, and holding drops a spot.
  - **Comment card:** docks to the keyboard, with undo and redo for strokes (`⇧⌘Z` redoes), a
    quote of the selected element's text, the intent chip and ↑. Return types a newline.
  - **Review bar:** back, the note count and ↑ in one glass group, with a hint line above it that
    starts on the gestures, then shows the connection and narrates each Send with a timer.
  - **Send keeps annotate mode open**, with the sent notes and their progress on the frozen screen.
- On iOS 26 the overlay's glass materializes in and out; before iOS 26 the bar and cards slide.
- The launcher pill is Liquid Glass and fades in once the app's first screen settles.
- Bundle images keep blue and red markers for contrast, with 4pt strokes, and a crop covers the
  note's drawing as well as its frame.

### Removed
- The toolbar and its hint, the draw toggle, region dragging, the shape tools, in-place text
  retyping, the selection chip and "Send and keep annotating" (keyboard shortcuts stay).
- The delivery ring and toasts (the launcher pill narrates instead) and the results card (the notes
  sheet lists results).
- The Move intent; a saved `move` loads as Fix.

### Fixed
- The plugin launcher (`bin/annotate`) resolves symlinks before skipping itself on PATH, so a
  linked copy (as npm installs it) can't exec itself in a loop.
- `annotate mcp` no longer swallows Sends. Claude Code drops channel events silently without
  channels enabled, yet each session was marked delivered: a push now counts only once Claude acts
  on it, an unanswered push is handed back after 45 s, and other MCP clients no longer get sessions
  claimed on their behalf.
- Pins disappeared after leaving annotate mode and coming back to the same screen.
- Drawing at the screen's edge shifted the whole overlay sideways, and a thin stroke there sent its
  badge to the bottom-trailing corner.
- After a relaunch mid-delivery (an agent reinstalling the app to show its change), the pill picks
  the newest Send's narration back up, so "Done" still shows.
- Return in the comment only closed the keyboard on iOS 26.
- The comment card's placement went stale after the photo picker.
- On iOS 27 devices a tap on the intent menu could be taken by the drawing gesture; the menu is now
  drawn inside the overlay.

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

First release.

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

[Unreleased]: https://github.com/ooolzhas/annotatekit/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/ooolzhas/annotatekit/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/ooolzhas/annotatekit/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/ooolzhas/annotatekit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ooolzhas/annotatekit/releases/tag/v0.1.0

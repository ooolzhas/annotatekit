# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Moving from one pin to another replayed the whole comment card: it shrank away and rose back in,
  and the keyboard dropped and came back. The card now stays where it is and only what differs
  changes (the quoted element, the text, the attachments). The open pin is saved and the new one
  opens in the same update, once the new element is found. If the app moved under the keyboard, the
  keyboard still goes down for the scan; the card rides with it instead of closing.
- The notes sheet lagged when it opened: its default Liquid Glass background blurred the frozen
  screen behind it on every frame. It now has a solid fill, the system's own sheet color.
- The Annotate pill could stay missing after a launch while the device was locked, when the system
  replaced the app's scene: the overlay window stayed on the old one. It now re-attaches to the
  next scene that becomes active.

## [0.4.1] - 2026-11-01

### Fixed
- The stroke under the finger is drawn by a `CAShapeLayer` instead of a screen-sized SwiftUI
  `Canvas`, which re-rendered through Metal on the main thread for every drag sample. On an iPhone 15
  Pro at 120 Hz: 2.9 → 2.0 ms of main-thread time per sample with 8 pins, 2.3 → 1.75 ms with none.
- The first time annotate mode opened after installing the app, the review bar, dim and edge glow
  appeared already in place instead of sliding and fading in. Drawing the glow's blurred edge mask
  held the main thread for ~250 ms, longer than the 0.3s entrance; the mask is now a small bitmap
  drawn once with Core Graphics.
- `annotate hook stop` took seconds on every Claude stop in long conversations (19 s with a 215 MB
  transcript and three open Sends): it decoded the whole transcript into a String and searched it
  once per open Send. It now maps the file and searches bytes (0.13 s), reads only Sends from the
  app's tracking window, and returns before reading anything on the second stop.
- Sends mirrored from a device were never pruned on the Mac, and every watcher re-read each
  session's status.json twice a second, so idle CPU grew with every Send. The mirror now prunes
  like the app does (newest 30, never inside the 48-hour history window), and the reply scan skips
  sessions without replies.json before decoding anything.
- The device mirror listed every development build on a paired phone once a minute forever, all
  at the same moment. Builds that never answer now back off to 16 minutes, and repeat cold
  listings go one per tick so they can't hold up a Send from the open app. devicectl dates no
  longer build a formatter per listed file.
- The status dot's breathing halo on the launcher pill was a SwiftUI `phaseAnimator`, so a DEBUG
  build spent ~5% of a core re-rendering every frame for as long as the pill showed. It's now a
  Core Animation layer (render server, ~0% app CPU idle) with the same breath.
- Drawing re-ran the whole overlay on every touch sample (every pin's sketch placement and badge),
  so a stroke got slower with each pin on screen. The live stroke now has its own view and grows in
  place: 2.8 ms of main-thread time per sample whatever the pin count (was 5.3 ms with 8 pins and
  7.6 ms with 16, simulator).
- Picked photos were decoded and downscaled on the main thread (a visible freeze per 12–48 MP
  photo); ImageIO now does it off the main thread, and the card's tiles show small thumbnails
  instead of 2048 px images.
- Idle work while annotate mode is closed: agent heartbeats no longer redraw the pill every 3 s, the
  launcher's chrome check backs off to 5 s and rests while annotating or in the background, delivery
  tracking reads status.json off the main thread, and closing annotate mode releases the frozen
  screen's full-resolution capture when it has no pins.
- Typing a comment re-ran the whole overlay on every keystroke (frozen screen, every pin marker and
  the bottom chrome), because the text lived on the open pin. It now has its own property, so only
  the comment card updates: per 68-character comment with 8 pins, `ActiveOverlay` and
  `BottomChrome` re-render 1–2 times instead of 69, and main-thread time drops from ~10.6 to
  ~8.6 ms per keystroke (simulator).
- With the comment keyboard up, a tap or a saved drawing compared the app's whole element outline
  against the frozen screen, and if the app had moved for the keyboard, repeated that walk every
  25 ms until it went away. The comparison now runs once per keyboard position and the wait wakes
  on the keyboard's own notifications: 72 outline walks for 6 such taps become 6, with the same
  tap-to-selection time. Screens whose accessibility node count never settles (UIKit-only) now keep
  the warm-up's last walk as their reference instead of none.
- Every DEBUG launch drew all of the app's windows 5 times a second, for up to 8 s on a screen that
  never stops moving, before showing the Annotate pill. The pill's reveal now samples twice a second
  and gives up after 3 s (at most 7 captures instead of 41, ~6.5 ms each): ~360 ms less main-thread
  time in the first 10 s on an animated screen. `ANNOTATE=1` launch-time starts keep the full
  settle.

### Changed
- Annotate mode's moving color (the edge glow's turning rings and the frost's drifting blobs) now
  runs on Core Animation instead of a SwiftUI timeline redrawn at 30 fps on the main thread. With
  annotate mode open and nothing happening, the app's CPU drops to its idle level (Simulator: ~1.2
  to ~0.45 CPU-seconds per 10 s), and the motion is smoother at the display's own frame rate. Same
  look, periods and Reduce Motion behavior.
- The edge glow and the frost behind the bottom bar are one color each, varied by opacity: the
  accent blue normally and the indicators' green while the agent works (no more cyan/indigo or
  mint/teal passages).

## [0.4.0] - 2026-11-01

### Changed
- **Overlay design pass** (Figma SUNSET 9378:7192):
  - Pins are 28pt blue markers with a white number, a white spinner while the agent works, and a
    green fill behind a white checkmark once resolved. A new pin shows a + while you write it, and
    a saved pin you reopen shows a pencil.
  - A sketch's pin sits centered on its first stroke, 15% short of where that stroke ends, instead
    of on the drawing's corner. More strokes added to the same pin don't move it. It's measured
    along the smoothed line as drawn, not the raw touch points. Bundle screenshots place it the
    same way.
  - The pin's rim is a 1pt soft-light gradient (bright at the top, gone by the bottom) instead of a
    solid white ring, and its shadow is softer (blur 8).
  - Element selections are a faint tint with rounded corner brackets instead of a white outline.
  - The status dot on the Annotate pill and the hint line has a pulsing halo (25%) that blurs as
    it grows, and offline red is the system red.
  - A hold pin is just its pin, centered on the spot you held; the ring and dot are gone (bundle
    crops still mark the spot with a ring, since they carry no pin).
  - A one-line quote in the comment card hugs its text (44pt) instead of sitting in a 64pt box.
  - Each pin keeps one marker through its life: saving, reopening and sending change only its glyph
    (+, pencil, number, spinner, outcome), and its color crossfades when that changes too.
  - The bar and the cards swap one way: the arriving one rises from below, the leaving one shrinks
    and fades in place. A card sent or cancelled with the keyboard up now stays put while the
    keyboard slides away instead of vanishing.
  - The Annotate pill first appears as just "Annotate"; its status dot then slides out from behind
    the label, fading in as it goes, and the pill widens to fit it.

### Removed
- Dragging the Annotate pill. It jittered under the finger; the pill still keeps clear of the app's
  bottom bars on its own.

### Fixed
- Opening a pin no longer cuts straight from the review bar to the comment card: the bar and its
  hint line shrink and fade in place while the card rises from below, the same motion as the
  Annotate pill handing over to the bar.

## [0.3.0] - 2026-10-30

### Added
- **Conversations per note:** an agent can ask about the same note more than once. Each pin's
  `status.json` entry keeps a `thread` of questions and replies, and the reply card and notes sheet
  show the earlier exchange. `note` and `reply` still hold the latest question and answer, so apps
  built with 0.2.x keep working.
- **Which note the agent is on:** `annotate ack <id> <pin>` (MCP: `annotation_acknowledge`) records
  the pin the agent is starting. The device says "Working on note 2", spins only that pin's badge
  and lists it as Working. The prompt and the watch skill ask agents to do it. It's stored as a
  session-level `acknowledged` list rather than a new pin state, which 0.2.x apps would reject.

### Fixed
- Asking about a note again within a second of the user's reply no longer hands back that reply as
  the answer to the new question (timestamps are stored to the second).

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

[Unreleased]: https://github.com/ooolzhas/annotatekit/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/ooolzhas/annotatekit/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/ooolzhas/annotatekit/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/ooolzhas/annotatekit/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/ooolzhas/annotatekit/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/ooolzhas/annotatekit/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/ooolzhas/annotatekit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/ooolzhas/annotatekit/releases/tag/v0.1.0

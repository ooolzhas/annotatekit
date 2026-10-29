# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Redesigned overlay (Figma SUNSET 9257:13754). Annotate mode dims the frozen screen 50% and draws
  a blue inset glow along the screen edge (62pt radius) that drifts slowly while annotate mode is on
  (static with Reduce Motion).
  - **Drawing is the default:** a stroke is a white 4pt pen line, and further strokes join the open
    pin for as long as its comment card is up.
  - **Tap and hold:** a tap selects the whole element under the finger, outlined in white with no
    label chip. Holding still for 0.5s drops a spot.
  - **Comment card:** it always docks to the keyboard, never to the marker. It has the comment, a
    paperclip, × and ↑ (Return also submits).
  - **Review bar:** with no pin open, the bottom bar shows ×, "N comments", trash and Send. Pins are
    white with white number badges. Trash asks before deleting ("Delete 4 comments?").
  - **Removed:** the toolbar and hint, the draw toggle, region dragging, the shape tools, in-place text
    retyping, the selection chip and "Send and keep annotating". The keyboard shortcuts stay.
- The launcher is now a pill above the home indicator (Figma 9265:14439) that reads "Annotate" and
  narrates the last Send in place of the delivery ring and toasts. It shows "4 comments sent"
  (9265:14691), then each stage as the agent reports it ("Claude picked it up", "Done", and so on),
  and returns to "Annotate" (or "Annotate · N" while unsent pins are waiting). It drags vertically
  and inverts in dark mode.
- The review bar and comment card use interactive Liquid Glass, so they respond to presses.
- Overlay refinements (Figma SUNSET 9272:17592, 9273:17925):
  - **Review bar:** it sits 34pt in from the screen edges, on the home indicator. It opens with a
    back chevron instead of ×, and counts "notes" instead of "comments" (also "Delete N notes?" and
    "N notes sent").
  - **Hint line above the bar:**
    - "Draw, tap or hold to annotate" for a few seconds after you open annotate mode.
    - Then "● Claude connected", or "● Agent offline · Notes will be saved" when nothing is
      listening, and it stays on that, following the connection.
    - While a Send is in flight it narrates it with a timer, e.g. "● Claude looking at it 2s" or
      the agent's own "Changes applied, reinstalling 9s".
  - **Background:** a blue gradient rises behind the bottom chrome.
  - **Comment card:** text sits at 20/16pt. Attached images are 64pt with a white remove badge.
- The annotated screenshot and crops keep their blue and red markers for contrast. Their strokes are
  now 4pt, and a crop covers the pin's drawing as well as its frame.

- Comment card: undo and redo buttons replace ×. They step through the strokes drawn since the card
  opened; `⇧⌘Z` redoes. With nothing left to undo, undo turns into × and discards the pin (deletes a
  reopened one); redo dims with nothing to redo.
  `Return` now types a newline in the comment and reply fields (↑ saves or sends), and a new drawing
  opens its card without the keyboard so the next stroke has the whole screen.
- The hint line's elapsed counter is dimmed to 50%, and every delivery stage change plays a haptic:
  a light tick while the Send moves along, success when it's done, a warning for a question or when
  nobody picked it up, an error when it failed.

- Motion: entering and leaving annotate mode, the bottom chrome rises into place and sinks away while
  the frozen screen cross-fades; the bar, comment and reply cards swap with a short slide, fade and
  scale (a card that closes leaves at once, with its keyboard); the launcher pill scales and fades in place. Reduce Motion keeps the fades.
- The review bar stays at the bottom of the screen while a keyboard is up; only the cards dock to the
  keyboard.
- The comment card quotes an element pin's own text in a thumbnail-style box (two lines at most),
  like the message a reply quotes.
- The comment and reply cards no longer focus on a tap anywhere on the card; that gesture took taps
  meant for intent-menu items drawn over the card. Tap the field itself to type.

- Overlay layout pass (Figma SUNSET 9276:28552):
  - **Review bar:** three glass pieces 8pt apart: a 52pt back button, the note count, and a 52pt ↑
    tinted blue while there is something to send. VoiceOver calls ↑ Save while no agent listens.
  - **Notes sheet:** the count is a button that opens a sheet at a small detent, draggable to full
    height. It lists the unsent notes (tap one to open it, swipe to delete, Clear All asks first;
    this replaces the old trash button) and the last Send's notes with their progress and Reply.
    With no notes it opens on an empty state that says how to add one. Tags under its toolbar
    (Current, In Progress, Resolved, Failed, each with a count) pick what it lists; it replaces the
    results card, and the hint line is a plain label again.
  - **Send keeps annotate mode open.** The sent pins stay on the frozen screen, and each badge shows
    a spinner while the agent has the pin, then a green check when it's resolved (`?` for a question,
    × when dismissed). The bar reads "N notes sent". Saving a new pin hides them; leaving annotate
    mode drops them. `⌘↩` does the same.
  - **Comment card:** with no keyboard up it sits where the bar does (34pt sides, on the home
    indicator); over the keyboard it keeps 8pt. The intent chip's title is 17pt, still with its
    up/down chevron. Move is gone from the intent menu (a saved `move` loads as Fix), leaving Fix and
    Question. Disabled glyphs (↑ with no text, redo with nothing to redo) are 25% instead of 50%.
  - **Quote box:** 236pt wide, 13/20pt text at 75%, hanging from the top.
  - **Hint line:** two-part lines split into a headline and a dimmed detail ("Agent offline", "Notes
    will be saved"); the detail and the elapsed sit 4pt after the headline.
  - The undo ↔ × glyph swap runs four times as fast.
  - **Fluid glow and frost:** the edge glow is two bands of uneven blues that turn slowly in
    opposite directions, so it swells, thins and runs along the edge; the frost behind the bottom
    chrome has soft blue pools drifting sideways. Reduce Motion holds both still.
  - Entering and leaving annotate mode fades the dim, glow and frost over the same 0.3s the bar
    takes to rise, on an ease so it reads as a fade rather than a pop.
  - **48 hours of notes:** the notes sheet lists every Send of the last 48 hours under "Sent 2 hours
    ago" headers, read back from their session folders with the agent's latest status, so it
    survives relaunches; pruning never removes a session that young. A note the agent never
    reported on follows its Send: resolved once the Send is done, failed when it failed.
  - Sending from a card with the keyboard up hides the card at once and saves once the keyboard has
    slid away, so the keyboard keeps its slide. Clear All is a trash icon and asks with a centered alert. The tag bar
    sits right under the toolbar.
  - The hint line's elapsed counter rolls its digits on each tick.
  - The intent chip opens our own dropdown above it instead of a system menu: on iOS 27 devices a
    tap on a system menu item could be taken by the frozen screen's drawing gesture.
  - The review bar's back, count and ↑ share one glass container, so a pressed one swells into its
    neighbours. The edge glow's corners are 4pt tighter (58pt).

### Added
- **Agent loop** (ideas from Agentation):
  - **`annotation_wait` MCP tool:** blocks until you Send or answer a question, batches for 10 s and
    returns everything. It gives hands-free delivery in Cursor, Codex, the Claude desktop app or any
    MCP client, with no channels. A pending wait shows as a green dot.
  - **Per-pin results:**
    - MCP tools: `annotation_resolve` / `annotation_dismiss`.
    - CLI: `annotate resolve|dismiss <id> <pin> "…"`.
    - `status.json` gains `pins`.
    - The notes sheet shows each sent note's result.
  - **Questions:**
    - The agent asks about one pin with `annotation_ask` / `annotate ask`, which waits for the answer.
    - The pill and hint line say "Question on note N".
    - The notes sheet's Reply opens a reply card.
    - The answer is saved to `replies.json` and travels back from a device too.
  - **Intent per pin** (Fix · Question), on a chip on the comment card. Prompts tag
    non-fix pins.
  - **`AnnotateOptions.promptDetail`:** `.compact`, `.standard` or `.detailed`.
  - **`SCHEMA.md`:** documents every file the app and agents exchange.
  - **Schema (additive, still v1):** `Annotation.intent`, `SessionStatus.pins`, and the new
    `replies.json`.
- **Sends from a physical iPhone or iPad reach your agent**, with no setup in the app: no network
  permission and no Info.plist keys. `annotate mcp`, `watch` and `run` copy each new bundle from a
  paired device's development build over the developer connection (`devicectl`, USB or Wi-Fi) into
  the project's `.annotate/`. They also copy status back, so the pill narrates on the device too. A
  Send reaches the checkout the build came from (bundles record the `Annotate.install()` file), so
  builds from two worktrees go to the agent in each. `--no-device` turns this off.
- **Connection dot on the launcher pill:**
  - **Solid green:** an agent that starts on Send is listening (a watcher, the headless runner, or a
    channel Claude has been seen answering).
  - **Ring:** an agent is connected but only reads sessions when asked (MCP tools).
  - **No dot:** nothing is listening. A Send then says "Saved · no agent connected" at once instead
    of waiting 10 s.

  Every `annotate` process writes a heartbeat to `.annotate/agents/`, and one of them merges the
  live ones into `.annotate/agent.json`, which the app reads.
- After a relaunch, the pill picks the newest Send's narration back up. An agent that reinstalls
  the app to show its change restarts it mid-delivery, and the "Done" now still shows.
- Reference images: the paperclip opens the photo picker (up to 4 images per pin). Send writes them
  to `attachments/<pin>-<n>.jpg`, and `prompt.md` lists them.
- **Schema (additive, still v1):** `AppInfo.installFile: String?`, `Annotation.attachments: [String]?`. Pins of any kind can now
  carry `sketch` strokes, whose points may extend outside the pin's frame.

### Fixed
- `annotate mcp` no longer swallows Sends.
  - **Without channels:** Claude Code, including the desktop app, drops channel events silently,
    yet the server marked each session delivered. A push now counts only once Claude is seen acting
    on one. An unanswered push is handed back after 45 s, the server stops pushing, and a watcher or
    the tools pick the session up.
  - **Other agents:** clients other than Claude Code no longer get sessions claimed on their behalf.
- Pins disappeared after leaving annotate mode and coming back, while the count still included them:
  each start took a new freeze-frame. Starting again on a screen that has pins (same look within a
  small tolerance) now brings back its freeze-frame and pins.
- Return in the comment only closed the keyboard on iOS 26, which delivers it as a submit rather than
  a newline; it now saves the pin.
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

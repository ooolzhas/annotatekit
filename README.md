# AnnotateKit

Cursor-style visual annotation for iOS apps, with send and forget.

1. In your running app, tap the pencil. The screen freezes.
2. Tap anything and type a comment. You can also drag out a region and sketch in it, or retype a
   label in place.
3. Hit **Send**. Claude Code, already open on your Mac, starts working on it. The pencil shows it
   happening: *Delivered → Claude picked it up → Done · Edited AlarmCard.swift*.

You don't copy or paste anything, and you don't tag views. Every pixel is annotatable.

AnnotateKit runs **inside your DEBUG build** as an overlay window, the way Cursor's Annotate lives
inside its browser. A small Mac CLI, `annotate`, hands each Send to Claude Code.

> Status: early. AnnotateCore and the `annotate` CLI are unit-tested on macOS and Linux; the
> overlay is new and needs device mileage. Issues and PRs welcome.

## Quick start

### 1. Add the overlay to your app

Swift Package Manager: `https://github.com/ooolzhas/annotate-ios`, link **AnnotateKit** to your app
target. Requires iOS 17+.

```swift
import AnnotateKit

@main
struct MyApp: App {
    init() {
        Annotate.install()   // compiled out of Release
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

### 2. Install the CLI on your Mac

```sh
git clone https://github.com/ooolzhas/annotate-ios && cd annotate-ios
swift build -c release --product annotate
cp .build/release/annotate /usr/local/bin/
```

### 3. Connect Claude Code (pick one)

**A. Push into your open session (recommended).** This uses Claude Code
[channels](https://code.claude.com/docs/en/channels), currently a research preview. Add the server
to your project's `.mcp.json`:

```json
{ "mcpServers": { "annotate": { "command": "annotate", "args": ["mcp"] } } }
```

Then start Claude Code in the project with the channel enabled:

```sh
claude --dangerously-load-development-channels server:annotate
```

During the preview, a custom channel server isn't on Claude Code's allowlist, so it has to be named
with this flag. The flag only skips that allowlist check, and Claude Code asks you to confirm at
launch. Each Send then arrives in the session as a message, even while Claude is idle. Claude loads
the screenshots with `get_annotation_session`, makes the change, and reports back with
`annotation_status`, which the app shows. Team and Enterprise orgs need channels enabled by an
admin. If events don't arrive, set `MCP_PROTOCOL_NEGOTIATION=legacy`.

**B. A watcher inside a normal session.** Copy `ClaudeCode/skills/annotations/` to your project's
`.claude/skills/` and run `/annotations` in Claude Code. It arms a Monitor on `annotate watch` and
handles each session as it lands.

**C. Fully unattended.** Run `annotate run` in a terminal at the project root. Each Send becomes a
`claude -p` run with `--permission-mode acceptEdits`, resuming the previous run's conversation so
follow-ups keep their context. Extra flags pass through: `annotate run -- --model opus`.

Without any of these, sessions still land in `.annotate/`, and the app tells you nothing picked
them up. Ask Claude to "check my latest annotation" with the MCP tools, or set
`AnnotateOptions(copiesPromptToClipboard: true)`.

## Use

| Action | Gesture / key |
|---|---|
| Enter annotate mode (freezes the screen) | Pencil button, `Annotate.start()`, or launch with `ANNOTATE=1` |
| Pin anything | Tap. It snaps to the element under your finger, or pins the exact spot if there's nothing distinct there |
| Walk spot → element → containers | `↑` / `↓` before saving |
| Comment and save | Type, then `Return` |
| Retype a label in place | Text-cursor button on the card |
| Region with sketch | Drag, then draw with pen / ellipse / rectangle / arrow |
| Undo stroke (or last pin) | `⌘Z` or the undo button |
| Back out | `Esc` (editing → selection → leave) |
| Send | **Send** or `⌘Return`. The chevron menu has *Send and keep annotating* and *Clear all* |

To annotate another screen, leave annotate mode, navigate, and come back. Each entry captures a new
screen, and one Send carries every screen that has pins.

In the Simulator, `Return`, `Esc` and the arrow keys reach the app as long as the hardware keyboard
is connected. ⌘-shortcuts go to the Simulator app unless you turn on *I/O → Keyboard → Send
Keyboard Shortcuts to Device*. The on-screen buttons always work.

## Coordinates are the contract

Agents find things by looking, so every pin is pinned down exactly:

- All frames and points are **iOS points, origin top-left**, relative to the frozen screen.
- Each screen ships as `screens/N.png` at **1x: one pixel per point**. A pin at `(84, 322)` is
  pixel `(84, 322)` in that image. A 402×874 pt screen is a 402×874 image, small enough that
  vision models see it unscaled.
- `screens/N-annotated.png` is the same image with numbered blue markers, outlines and red
  sketches. `screens/N@3x.png` and `crops/N.png` (native resolution, 32 pt of context) carry the
  detail.
- Every pin records its **anchor** (exactly where you tapped, or a region's center), its **frame**,
  and percentages across and down, so the position survives any rescaling.
- Every pin also records its **nearby text**, and each screen lists every visible label with its
  frame. That's usually all an agent needs to grep its way to the right SwiftUI view.

The resulting prompt looks like this:

```
UI annotations from the running app: 2 pins on 1 screen. Please make these changes in the code.

Session: /Users/me/app/.annotate/sessions/20261028-141502-a1b2
Device: iPhone 17 Pro · iOS 26.0 · 402×874 pt @3x · dark · Dynamic Type L
Coordinates are iOS points, origin top-left. Screen images are 1x, so pixel = point. Open the
annotated image first: each pin is a numbered blue marker there. Crops show detail.

Screen 1 (402×874 pt) — annotated …/screens/1-annotated.png · clean …/screens/1.png · hi-res …/screens/1@3x.png

1. Button "Get started" at (24, 300, 120×44) — tapped (84, 322), 21% across, 37% down
   bigger, tighter
   Nearby text: "Light that follows your day"
   Crop: …/crops/1.png

2. Spot at (179, 678, 44×44) — tapped (201, 700), 50% across, 80% down
   too much empty space here
   Nearby text: "Halo Pendant", "2700K warm white"
   Crop: …/crops/2.png

Full detail (all frames, visible text per screen, sketch vectors): …/session.json

When you're done, finish with a one-line summary of what you changed.
```

## The bundle

```
<project root>/.annotate/           .gitignore'd automatically
  latest                            "sessions/<id>"
  sessions/<id>/
    prompt.md                       the message above
    screens/1.png  1-annotated.png  1@3x.png
    crops/1.png …
    session.json                    written last, so it marks the bundle as complete
    status.json                     written by the receiver: delivered → received → working → done | failed
```

Simulator apps can write to the Mac's file system. AnnotateKit finds your project root by walking up
from the `#filePath` of `Annotate.install()` to the nearest `.git`, and it polls `status.json` to
show progress on the pencil button. On a physical device, bundles go to the app's Documents folder.

### session.json (schema v1)

```jsonc
{
  "schemaVersion": 1,
  "id": "20261028-141502-a1b2",
  "createdAt": "2026-10-28T14:15:02Z",
  "app":    { "bundleID": "…", "name": "…", "version": "1.0", "build": "7" },
  "device": { "model": "iPhone 17 Pro", "systemName": "iOS", "systemVersion": "26.0", "isSimulator": true,
              "screen": { "width": 402, "height": 874 }, "scale": 3,
              "colorScheme": "dark", "contentSize": "L", "orientation": "portrait" },
  "screens": [{
    "index": 1, "capturedAt": "…", "size": { "width": 402, "height": 874 },
    "image": "screens/1.png", "annotatedImage": "screens/1-annotated.png", "hiResImage": "screens/1@3x.png",
    "elements": [ { "role": "button", "label": "Get started", "frame": { "x": 24, "y": 300, "width": 120, "height": 44 } } ]
  }],
  "annotations": [{
    "id": "UUID", "index": 1, "screen": 1,
    "kind": "element",                       // "element" | "point" | "region"
    "comment": "bigger, tighter",
    "anchor": { "x": 84, "y": 322 },
    "frame":  { "x": 24, "y": 300, "width": 120, "height": 44 },
    "element": { "role": "button", "label": "Get started", "traits": ["button"], "breadcrumb": ["ScrollView"] },
    "nearbyText": ["Light that follows your day"],
    "source": null,                          // set only with the optional .annotatable()
    "textEdit": null,                        // { "from": "…", "to": "…" } for in-place retypes
    "sketch": null,                          // regions: { "size", "strokes": [{ "tool", "points" }] }
    "crop": "crops/1.png"
  }]
}
```

## How selection works

On tap, `ElementScanner` looks at the window that would receive the touch. It walks the hit view's
ancestors, its subtree, and the accessibility children of both, so views behind a sheet are skipped.
SwiftUI `Text`, `Button` and `Image` exist at runtime only as accessibility nodes, so AnnotateKit
turns on the in-process accessibility tree at install, the same switch XCUITest flips. You can opt
out with `AnnotateOptions(enablesAccessibilityTree: false)`.

`SelectionStack` sorts what it finds smallest-first and merges duplicates. If the smallest thing
under your finger is a big container (more than 40% of the screen), the pin starts as a **spot** at
the exact point instead. `↑`/`↓` move along spot → element → containers.

### Optional: exact source lines

Tagging is never required. If you want a pin to carry `file:line` instead of relying on a search,
add `.annotatable()` to a view. It records `#filePath`/`#line`, and pins on or inside that view get
a `Source:` line.

## Layout

```
Sources/AnnotateCore    Foundation-only: schema, SelectionStack, ScreenOutline, PromptRenderer,
                        SessionWriter/SessionInbox (bundle + status), ProjectRoot, placement math
Sources/AnnotateKit     DEBUG-only overlay: OverlayWindow, ElementScanner, AnnotateController,
                        Snapshotter, SwiftUI chrome, optional .annotatable(), public Annotate API
Sources/AnnotateAgent   Mac side: SessionFeed (discovery + atomic claims), ChannelServer (MCP),
Sources/AnnotateCLI       HeadlessRunner (claude -p), Command (the `annotate` executable)
ClaudeCode/skills       /annotations skill for the Monitor-based watcher
```

`swift test` runs the AnnotateCore and AnnotateAgent suites on macOS and Linux.

## Limitations

- Frames assume a full-screen window (iPhone, or a full-screen iPad app). Stage Manager windows
  aren't handled.
- The inline retype field estimates the font size from the label's height.
- There's no hover highlight: the iPhone Simulator doesn't deliver pointer hover to apps.
- Channels are a Claude Code research preview. Their flags and protocol may change.

## Roadmap

- Device / Dynamic Type / appearance switcher from the toolbar, re-capturing the same screen
- Live style panel: nudge spacing, radius and color in place, then send the diff
- Hot reload so edits show up on the frozen screen's successor without relaunching
- Sending sessions from a physical device

## License

MIT

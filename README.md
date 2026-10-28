# AnnotateKit

Cursor-style visual annotation for iOS apps. Tap a view in your running app, pin a comment, retype
its copy, or drag out a region and sketch what should go there. Then hit **Send**: your coding agent
gets a prompt with numbered pins, screen crops and, when you opt in, the exact `file:line` of each
view.

It runs **inside your DEBUG build** as an overlay window, the way Cursor's Annotate runs inside its
browser. There's no Mac app, no idb and no screenshot coordinate mapping. Because it lives in the
app process, it can read the real view and accessibility tree.

> Status: early. AnnotateCore (schema, selection, prompt) is unit-tested; the overlay is new and
> needs real-device mileage. Issues and PRs welcome.

## Install

Swift Package Manager: add `https://github.com/ooolzhas/annotate-ios` and link **AnnotateKit** to
your app target. Requires iOS 17+.

```swift
import AnnotateKit
import SwiftUI

@main
struct MyApp: App {
    init() {
        Annotate.install()   // no-op in Release
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

Every overlay type is behind `#if DEBUG`. In Release, `Annotate.install()` and `.annotatable()`
compile to empty stubs, so you can leave the calls in.

## Use

| Action | Gesture / key |
|---|---|
| Enter annotate mode | Floating pencil button, `Annotate.start()`, or launch with `ANNOTATE=1` |
| Select an element | Tap |
| Walk up / down the element tree | `↑` / `↓` (before saving the pin) |
| Comment and save | Type, then `Return` |
| Retype a label in place | Text cursor button on the card |
| Region with sketch | Drag on empty space, then draw with pen / ellipse / rectangle / arrow |
| Undo stroke (or last pin) | `⌘Z` or the undo button |
| Back out | `Esc` (editing → selection → leave mode) |
| Send | **Send** button or `⌘Return`. The chevron menu has *Send and keep annotating* and *Clear all* |

In the Simulator, `Return`, `Esc` and the arrow keys reach the app as long as the hardware keyboard is
connected. **⌘-shortcuts go to the Simulator app** unless you turn on
*I/O → Keyboard → Send Keyboard Shortcuts to Device*. The on-screen buttons always work.

## What Send produces

```
<project root>/.annotate/
  .gitignore                 "*", so sessions are never committed
  latest                     "sessions/<id>"
  sessions/20261028-141502-a1b2/
    prompt.md                same text that was copied to the clipboard
    session.json             full detail (schema below)
    screenshot.png           clean capture
    annotated.png            capture with numbered pins and sketches
    crops/1.png …            one crop per pin, element outlined / sketch burned in
```

Simulator apps can write to the Mac's file system. AnnotateKit finds your project root by walking up
from the `#filePath` of the `Annotate.install()` call until it finds `.git`, so the bundle lands
next to your code. On a physical device it falls back to the app's Documents folder. You can override
this with `AnnotateOptions(outputDirectory:)`.

The prompt is also copied to the clipboard. The Simulator syncs its pasteboard to the Mac, so you can
paste it straight into Claude Code, Cursor or any other agent:

```
I annotated the running app (3 annotations). Please make these UI changes.

Session: /Users/me/app/.annotate/sessions/20261028-141502-a1b2
Screen: iPhone 17 Pro · iOS 26.0 · 402×874 pt @3x · dark · Dynamic Type L
Screenshot with numbered pins: /Users/me/app/.annotate/sessions/20261028-141502-a1b2/annotated.png

1. Button "Get started" — inside `HeroCard` at App/HomeView.swift:42
   bigger, tighter
   Crop: …/crops/1.png
2. Text "Adaptive lamps for every room" — no source mapping; search for its text or label
   Change the copy from "Adaptive lamps for every room" to "Smart light that sets itself"
   Crop: …/crops/2.png
3. Region 352×166 at (16, 420) — inside `HomeView` at App/HomeView.swift:12
   add a signup card here
   Sketch of the desired layout (rectangle, arrow)
   Crop: …/crops/3.png

Full details (frames, accessibility info, sketch vectors): …/session.json
```

Tip for agent instructions (`CLAUDE.md`, `AGENTS.md`): *"When I say 'check my annotations', read
`.annotate/latest`, then that session's `prompt.md`, and look at its crops."*

## Source mapping with `.annotatable()`

SwiftUI views have no runtime identity, so without help a pin only knows what's on screen: role,
label, frame and crop. The agent then has to search for the text. Tag the views you care about and
pins carry the file and line instead:

```swift
struct HeroCard: View {
    var body: some View {
        VStack { … }
            .annotatable("HeroCard")    // records #filePath / #line
    }
}
```

A pin on the tagged view itself is an `exact` match. A pin on anything inside it, such as a button in
the card, is an `enclosing` match pointing at the card. Regions resolve to the smallest tagged view
around them, which tells the agent which file new UI belongs in. Tagging screen-level views and
reusable components gets you most of the value.

## How selection works

On tap, `ElementScanner` looks at the window that would receive the touch. It walks the hit view's
ancestors (as containers), its subtree, and the **accessibility children** of both, collecting
everything whose frame contains the point. That keeps views hidden behind a sheet out of the results.
SwiftUI `Text`, `Button` and `Image` exist at runtime only as accessibility nodes, so AnnotateKit turns
on the in-process accessibility tree at install, the same switch XCUITest flips. You can disable that
with `AnnotateOptions(enablesAccessibilityTree: false)`. `.annotatable()` registrations join the same
candidate list.

`SelectionStack` sorts candidates smallest-first and merges ones that describe the same box (an
accessibility button plus the `.annotatable()` view around it), keeping the best role, label and
source from each. `↑`/`↓` walk that stack.

## session.json (schema v1)

```jsonc
{
  "schemaVersion": 1,
  "id": "20261028-141502-a1b2",
  "createdAt": "2026-10-28T14:15:02Z",
  "app":    { "bundleID": "…", "name": "…", "version": "1.0", "build": "7" },
  "device": { "model": "iPhone 17 Pro", "systemName": "iOS", "systemVersion": "26.0",
              "isSimulator": true, "screen": { "width": 402, "height": 874 }, "scale": 3,
              "colorScheme": "dark", "contentSize": "L", "orientation": "portrait" },
  "screenshot": "screenshot.png",
  "annotatedScreenshot": "annotated.png",
  "annotations": [
    {
      "id": "UUID", "index": 1, "kind": "element",          // or "region"
      "comment": "bigger, tighter",
      "frame": { "x": 24, "y": 300, "width": 120, "height": 44 },   // screen points
      "element": { "role": "button", "typeName": null, "label": "Get started", "value": null,
                   "identifier": null, "traits": ["button"], "breadcrumb": ["HeroCard", "ScrollView"] },
      "source": { "name": "HeroCard", "file": "App/HomeView.swift", "line": 42, "match": "enclosing" },
      "textEdit": { "from": "…", "to": "…" },               // in-place retype, optional
      "sketch": { "size": { "width": 352, "height": 166 },  // regions only
                  "strokes": [ { "tool": "arrow", "points": [ { "x": 200, "y": -20 }, { "x": 220, "y": 10 } ] } ] },
      "crop": "crops/1.png"
    }
  ]
}
```

Swift types live in `AnnotateCore` (`AnnotationSession`, `Annotation`, …), which is Foundation-only.
Tools that read sessions, such as an MCP server or a Mac viewer, can depend on it without UIKit.

## Layout

```
Sources/AnnotateCore   Foundation-only: schema, SelectionStack, SourceResolver, PromptRenderer,
                       SessionWriter, ProjectRoot, placement math. `swift test` on macOS/Linux.
Sources/AnnotateKit    DEBUG-only overlay: OverlayWindow, ElementScanner, AnnotateController,
                       Snapshotter, SwiftUI chrome, `.annotatable()`, public `Annotate` API.
```

## Limitations

- Pins are tied to screen positions. If you leave annotate mode and scroll, earlier pins no longer
  line up with the content (the crops still show what you pinned).
- Frames assume a full-screen window (iPhone, or a full-screen iPad app). Stage Manager windows aren't
  handled yet.
- The inline retype field estimates the font size from the label's height.
- There's no hover highlight: the iPhone Simulator doesn't deliver pointer hover to apps.

## Roadmap

- MCP server (`list_annotation_sessions`, `get_annotations`) on top of AnnotateCore
- A macro that applies `.annotatable()` to every `View` body automatically
- Device / Dynamic Type / appearance switcher from the toolbar
- Live style panel: tweak spacing, radius and color in place, then send the diff
- Sharing sessions from a physical device

## License

MIT

# ``AnnotateKit``

Cursor-style visual annotation for iOS apps: tap, draw and comment on your running app, then send it
straight to your coding agent.

## Overview

AnnotateKit adds a DEBUG-only overlay window to your app. Enter annotate mode and the screen
freezes. Tap anything to pin a comment to it, drag out a region, sketch anywhere, or retype a label
in place. **Send** writes a session bundle (screenshots where pixel = point, crops, a prompt and
`session.json`) to your project's `.annotate/` folder. The `annotate` CLI then hands it to Claude
Code or any MCP-capable agent, and the overlay shows the agent's progress.

```swift
import AnnotateKit

@main
struct MyApp: App {
    init() { Annotate.install() }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

All overlay code is compiled only into DEBUG builds. In Release, ``Annotate/install(_:file:)`` and
`annotatable(_:file:line:)` are empty stubs, so the calls can stay in place.

## Topics

### Essentials

- <doc:GettingStarted>
- ``Annotate``
- ``AnnotateOptions``

### Source mapping

- ``SwiftUICore/View/annotatable(_:file:line:)``

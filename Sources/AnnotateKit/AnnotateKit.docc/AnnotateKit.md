# ``AnnotateKit``

Visual feedback for iOS apps, straight to your coding agent: AnnotateKit turns drawings and comments
inside your running app into prompts for your agent.

## Overview

AnnotateKit adds a DEBUG-only overlay window to your app. Enter annotate mode and the screen
freezes. Draw around anything, tap an element to select it, or hold to pin an exact spot, and say
what should change. **Send** writes a session bundle (screenshots where pixel = point, crops, a prompt and
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
`annotatable(_:file:line:)` and `annotateAvoid()` are empty stubs, so the calls can stay in place.

## Topics

### Essentials

- <doc:GettingStarted>
- ``Annotate``
- ``AnnotateOptions``

### Source mapping

- ``SwiftUICore/View/annotatable(_:file:line:)``

### Launcher

- ``SwiftUICore/View/annotateAvoid()``

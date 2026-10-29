# Getting Started

Add the overlay, connect your agent, and send your first annotation.

## Add the package

In Xcode choose **File → Add Package Dependencies…**, enter
`https://github.com/ooolzhas/annotatekit`, and add the **AnnotateKit** library to your app target.
In a `Package.swift`:

```swift
.package(url: "https://github.com/ooolzhas/annotatekit", from: "0.2.0")
```

## Install the overlay

Call ``Annotate/install(_:file:)`` once at launch. Leave the `file` argument at its default: the
call site's path tells AnnotateKit where your project root is, so session bundles land in
`<project root>/.annotate/` when running in the Simulator.

```swift
init() {
    Annotate.install(AnnotateOptions(showsLauncher: true))
}
```

Add `.annotate/` to your `.gitignore`. AnnotateKit also writes its own `.gitignore` inside the
folder.

## Connect an agent

Install the CLI (`brew install ooolzhas/tap/annotate` or `mint install ooolzhas/annotatekit`), then
pick a delivery mode:

- **Claude Code, pushed into your open session:** add `annotate mcp` as an MCP server and start
  `claude --dangerously-load-development-channels server:annotate`.
- **Claude Code, watcher skill:** install the `annotations` skill and run `/annotations`.
- **Unattended:** run `annotate run` in the project root.
- **Any MCP client** (Cursor, Codex, VS Code): add `annotate mcp` as a server and ask the agent to
  "check my latest annotation".

## Annotate

Tap the **Annotate** pill (or call ``Annotate/start()``). The screen freezes.

- **Draw** anywhere: the drawing becomes a note, attributed to the view under it.
- **Tap** selects the element under your finger. Use `↑`/`↓` to move between it and its
  containers.
- **Hold** still for half a second to pin an exact spot.
- **↑** on the comment card saves a note, **Esc** backs out, and **Send** delivers everything.

## Optional: exact source lines

Tagging is never required. To give a pin an exact `file:line`, add
`annotatable(_:file:line:)` to a view:

```swift
AlarmCard(alarm: alarm)
    .annotatable("AlarmCard")
```

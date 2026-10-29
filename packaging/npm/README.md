# annotate-ios

The `annotate` CLI for [AnnotateKit](https://annotatekit.com): it delivers the visual feedback you
draw on your running iOS app (screenshots, exact coordinates and your notes) to your coding agent.

This package is a small launcher. On first run it downloads the checksum-verified universal macOS
binary from the matching [GitHub Release](https://github.com/ooolzhas/annotatekit/releases) and
caches it in `~/.cache/annotate`. macOS only.

## Use it as an MCP server

Run it from your project root, in any MCP client:

```json
{ "mcpServers": { "annotate": { "command": "npx", "args": ["-y", "annotate-ios", "mcp"] } } }
```

Then ask your agent to *"keep calling annotation_wait"*: each call returns the notes as soon as you
hit Send in the app.

## Or install the command

```sh
npm install -g annotate-ios
annotate help
```

The app side is the AnnotateKit Swift package. Setup, the Claude Code plugin and every delivery
mode are in the [README](https://github.com/ooolzhas/annotatekit#readme).

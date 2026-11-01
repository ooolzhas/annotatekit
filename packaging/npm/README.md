# annotate-ios

[AnnotateKit](https://annotatekit.com) delivers the visual feedback you draw on your running iOS app
(screenshots, exact coordinates and your notes) to your coding agent. This package holds two things:
the `annotate` CLI and the AnnotateKit pod for React Native and Expo apps.

The CLI is a small launcher. On first run it downloads the checksum-verified universal macOS binary
from the matching [GitHub Release](https://github.com/ooolzhas/annotatekit/releases) and caches it
in `~/.cache/annotate`. macOS only.

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

## React Native and Expo (iOS)

```sh
npm install -D annotate-ios
```

- **Expo:** add `"plugins": ["annotate-ios"]` to `app.json` and use a development build
  (`npx expo run:ios`). Expo Go can't load native code.
- **Bare React Native:** in `AppDelegate.swift`, add `import AnnotateKit` and call
  `Annotate.install()` first in `didFinishLaunchingWithOptions`, then `cd ios && pod install`. For
  `AppDelegate.mm`: `#import "AnnotateKit-Swift.h"` and `[AnnotateBridge installWithFile:@__FILE__];`.

Needs an iOS 17 deployment target. Native apps use the AnnotateKit Swift package instead. Setup, the
Claude Code plugin and every delivery mode are in the
[README](https://github.com/ooolzhas/annotatekit#react-native-and-expo).

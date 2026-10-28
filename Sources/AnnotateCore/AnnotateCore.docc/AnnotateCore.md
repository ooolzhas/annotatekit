# ``AnnotateCore``

The session format AnnotateKit writes and agents read, plus the pure logic behind it.

## Overview

AnnotateCore is Foundation-only and runs on macOS, iOS and Linux. Use it to build tools that consume
annotation sessions: viewers, MCP servers, CI bots.

The coordinate contract: every frame and point is in iOS points, origin top-left, relative to a
``Screen``. Each screen's `image` is rendered at 1x, so pixel = point.

## Topics

### Session format

- ``AnnotationSession``
- ``Screen``
- ``ScreenElement``
- ``Annotation``
- ``ElementInfo``
- ``SourceLocation``
- ``TextEdit``
- ``Sketch``
- ``Stroke``

### Reading and writing bundles

- ``SessionWriter``
- ``SessionInbox``
- ``SessionStatus``
- ``SessionBundle``

### Rendering prompts

- ``PromptRenderer``
- ``ScreenOutline``

### Selection

- ``SelectionStack``
- ``ElementCandidate``
- ``SourceResolver``

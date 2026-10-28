---
name: annotations
description: Watch for UI annotations sent from the iOS app (AnnotateKit) and implement each one as it arrives. Use when the user runs /annotations or asks to watch or listen for annotations.
disable-model-invocation: true
---

# Watch for annotations

The user annotates the running iOS app (taps, comments, regions, sketches) and hits Send. Each Send
writes a session bundle to `.annotate/sessions/<id>/` in this project. Your job: act on each one as
it arrives, without the user pasting anything.

## Arm the watcher

Use the Monitor tool to run `annotate watch` from the project root (if `annotate` isn't on PATH,
use `swift run --package-path <path to annotate-ios> annotate watch`). Every output line is one new
session and already says where it is. When the Monitor deadline notice arrives, re-arm it with the
same command. Keep watching until the user says stop. Tell the user once that you're watching.

## For each session line

1. `annotate status <id> working "Looking at it"` so the device shows you picked it up.
2. Read `<session dir>/prompt.md`, then open the images it lists with Read: the annotated screen
   (numbered blue markers = pins) first, then the crops.
3. Find the code. Coordinates are iOS points, origin top-left, and screen images are 1x, so
   pixel = point. Grep for the pin's own text or its "Nearby text"; `session.json` has every
   visible label on the screen with its frame. A `Source:` line, when present, is exact.
4. Make the changes, following this project's own rules (CLAUDE.md) as for any other edit.
5. `annotate status <id> done "<one-line summary of what you changed>"`, or
   `annotate status <id> failed "<why>"` if you couldn't.
6. Then give the user a short summary in chat and keep watching.

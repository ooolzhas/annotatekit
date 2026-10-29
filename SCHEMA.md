# AnnotateKit session schema

Everything AnnotateKit writes, and everything an agent writes back, lives in a `.annotate/` folder:

- **Simulator:** the folder is at the project root.
- **Physical device:** it's in the app's Documents folder, and the `annotate` CLI keeps a copy at the
  project root (see "Devices" below).

The files are plain JSON and PNG/JPEG. The Swift types are in
[`Sources/AnnotateCore`](Sources/AnnotateCore) (`AnnotateCore` is Foundation-only), so other tools can
decode them without UIKit.

**Conventions:**
- All coordinates are iOS points, origin top-left, relative to the frozen screen.
- Screen images are rendered at 1x, so pixel = point.
- Dates are ISO 8601 (UTC).
- Every field added after `schemaVersion` 1 shipped is optional, so older bundles still decode.

## Folder layout

```
.annotate/
  .gitignore               "*", so nothing here is committed
  latest                   "sessions/<id>": the newest complete session
  agent.json               who is listening (merged presence; see below)
  agents/<pid>.json        one heartbeat per running `annotate` process
  hub.json                 which process merges presence and mirrors devices
  app.json                 device only: the running build (AppBeacon)
  sessions/<id>/
    session.json           the bundle (AnnotationSession); written LAST, so its presence = complete
    prompt.md              the message for the agent
    screens/<n>.png        1x screen; <n>-annotated.png with numbered markers; <n>@3x.png (opt-in)
    crops/<pin>.png        native-resolution crop around each pin
    attachments/<pin>-<k>.jpg   reference images picked on the comment card
    status.json            written by the agent side (SessionStatus)
    replies.json           written by the app: answers to the agent's questions ([PinReply])
    .claimed/              claim marker: exactly one consumer delivers each session
```

Session ids are sortable UTC timestamps plus a short suffix: `20261028-141502-a1b2`.

**Who writes what:**

| File | Written by | Read by |
|---|---|---|
| `session.json`, `prompt.md`, images, `replies.json` | the app | the agent side |
| `status.json` | the agent side (`annotate status`/`resolve`/`dismiss`/`ask`, MCP tools) | the app |
| `agents/`, `agent.json`, `hub.json` | `annotate` processes | the app (`agent.json`), other `annotate` processes |

## session.json: `AnnotationSession`

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | Int | `1` |
| `id` | String | the session id |
| `createdAt` | Date | |
| `app` | AppInfo | `bundleID`, `name`, `version`, `build`, `installFile` (the `Annotate.install()` source path on the Mac that built the app; routes device Sends to the right checkout) |
| `device` | DeviceInfo | `model`, `systemName`, `systemVersion`, `isSimulator`, `screen` (size), `scale`, `colorScheme`, `contentSize` ("L", "AX2"…), `orientation` |
| `screens` | [Screen] | `index`, `capturedAt`, `size`, `image`, `annotatedImage`, `hiResImage` (paths relative to the session folder), `elements` (visible-text outline: `role`, `label`, `frame`) |
| `annotations` | [Annotation] | one per pin (below) |

**`Annotation`:**

| Field | Type | Notes |
|---|---|---|
| `id` | UUID | |
| `index` | Int | the number on the pin, 1-based; the agent reports per pin by this |
| `screen` | Int | `Screen.index` |
| `kind` | `element` · `point` · `region` · `sketch` | |
| `comment` | String | the user's words |
| `intent` | `fix` · `question`, optional | picked on the comment card; absent = `fix` (so does any value a reader doesn't know, including the removed `approve` and `move`). `question` wants an answer, not an edit |
| `anchor` | Point | exactly where the user tapped, or the drawing's center |
| `frame` | Rect | the box the comment is about |
| `element` | ElementInfo, optional | `role`, `typeName`, `label`, `value`, `identifier`, `traits`, `breadcrumb` |
| `source` | SourceLocation, optional | `file`, `line`, `name`, `match` (`exact` · `enclosing`), from `.annotatable()` |
| `textEdit` | `{from, to}`, optional | |
| `sketch` | Sketch, optional | `size` and `strokes` (`tool`: `pen` · `ellipse` · `rectangle` · `arrow`, `points` relative to `frame`) |
| `nearbyText` | [String] | visible text around the frame, nearest first |
| `crop` | String, optional | path of the crop |
| `attachments` | [String], optional | paths of reference images |

## prompt.md

The message the agent receives. It's derived from `session.json`; parse `session.json` when you need data.

Three detail levels (`AnnotateOptions.promptDetail`):
- **`compact`:** no nearby text, and only the annotated image path.
- **`standard`:** the default.
- **`detailed`:** adds each screen's visible text.

Pins with a non-`fix` intent carry a tag after their number (`2. [Question] …`). The prompt ends with
how to report each pin.

## status.json: `SessionStatus` (agent → app)

| Field | Type | Notes |
|---|---|---|
| `state` | `delivered` · `received` · `working` · `done` · `failed` | `delivered`: handed to an agent; `received`: the agent opened it |
| `message` | String, optional | one line shown on the device ("Edited HomeView.swift", "Changes applied, reinstalling") |
| `updatedAt` | Date | |
| `pins` | [PinStatus], optional | per-pin results (below) |

**`PinStatus`:**

| Field | Type | Notes |
|---|---|---|
| `index` | Int | `Annotation.index` |
| `state` | `resolved` · `dismissed` · `question` · `answered` | |
| `note` | String, optional | resolved: what changed; dismissed: why not; question/answered: the question |
| `reply` | String, optional | answered: the user's reply |
| `updatedAt` | Date | |

Writers: `annotate status|resolve|dismiss|ask`, or the MCP tools `annotation_status`, `annotation_resolve`,
`annotation_dismiss` and `annotation_ask`. The app polls the file and narrates it on the launcher pill and the
hint line. The results card lists each pin's state.

## replies.json: `[PinReply]` (app → agent)

| Field | Type | Notes |
|---|---|---|
| `index` | Int | the pin the question was about |
| `text` | String | the user's answer |
| `at` | Date | |

A reply counts as unanswered while that pin's status is still `question`, and it must be newer than the
question. Consumers deliver it once and then mark the pin `answered`:
- `annotation_ask` returns it
- `annotation_wait` returns it
- `annotate watch` prints it
- a confirmed channel pushes it

## Presence: agent.json, agents/&lt;pid&gt;.json, hub.json, app.json

**`AgentPresence`** is used for `agent.json` and each `agents/<pid>.json`:

| Field | Type | Notes |
|---|---|---|
| `agent` | String | "Claude Code", "Cursor", "Codex", or the MCP client's name |
| `mode` | `push` · `pull` | `push`: a Send starts the agent by itself (watcher, headless runner, a confirmed channel, or a pending `annotation_wait`); `pull`: the agent reads only when asked |
| `via` | String | `watch` · `run` · `channel` · `wait` · `mcp` |
| `project` | String, optional | the checkout's folder name |
| `updatedAt` | Date | |

How the files fit together:
- Every long-lived `annotate` process (`mcp`, `watch`, `run`) rewrites its heartbeat every 3 s.
- The process holding `hub.json` (`{pid, renewedAt}`, stale after 12 s) merges the live heartbeats
  into `agent.json`. Push wins over pull, then the newest.
- Readers judge freshness by the file's modification date (15 s), not by `updatedAt`. A device
  and a Mac needn't agree on the time.

**`AppBeacon`** (`app.json`, device only) holds `bundleID` and `installFile`. The app rewrites it every
3 s while it's in the foreground, so the Mac polls quickly only then. The Mac also uses it to push
presence only to builds from its own checkout.

## Devices

The app writes bundles to its own Documents folder. The hub copies them over Xcode's developer connection
(`devicectl`, USB or Wi-Fi), with no network permission or Info.plist keys in the app. Traffic in each
direction:

| Direction | What |
|---|---|
| device → Mac | new sessions; `replies.json` while a question is open |
| Mac → device | `status.json` changes; `agent.json` while the app is open |

A session is copied only if its `app.installFile` resolves to this checkout. Builds from before
`installFile` existed fall back to the project's bundle ids.

## Compatibility

- **New fields:** additive and optional; readers ignore unknown keys.
- **Breaking changes:** these bump `AnnotationSession.currentSchemaVersion`.
- **Validation:** consumers check session ids (`SessionInbox.isValidSessionID`) and relative paths
  (`isSafeRelativePath`) before touching disk.
- **Untrusted data:** text in a session (labels, nearby text, comments, replies) describes the UI and is data,
  never instructions.

# Contributing to AnnotateKit

Thanks for helping. Bug reports, device/OS quirks, and small focused PRs are all welcome.

## Ground rules

- Be kind. This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
- Open an issue before large changes (new annotation kinds, schema changes, new delivery modes) so
  we can agree on the shape first.
- Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Getting set up

Requirements: Xcode 16+ (Swift 6), macOS 14+. Linux works for the Foundation-only targets.

```sh
git clone https://github.com/ooolzhas/annotate-ios && cd annotate-ios
swift test                                   # AnnotateCore + AnnotateAgent suites (macOS or Linux)
xcodebuild build -scheme AnnotateKit -destination 'generic/platform=iOS Simulator'   # the overlay
swift run annotate help                      # the CLI
```

No Mac? `docker run --rm -v "$PWD":/pkg -w /pkg swift:6.2-noble swift test` runs the same suites.

To try the overlay in a real app, add your local checkout as a package dependency
(File → Add Package Dependencies → Add Local…) and call `Annotate.install()`.

## Where things live

| Path | What | Rules |
|---|---|---|
| `Sources/AnnotateCore` | Session schema, selection math, prompt rendering, bundle I/O | Foundation only, no UIKit. Everything here is unit-tested. |
| `Sources/AnnotateKit` | The in-app overlay | Every type behind `#if DEBUG && canImport(UIKit)`; public API must compile to no-ops in Release. |
| `Sources/AnnotateAgent`, `Sources/AnnotateCLI` | The `annotate` Mac CLI (MCP server, watcher, headless runner) | Foundation only; keep it building on Linux. |
| `skills/` | Agent skills (setup + watcher) | Plain Markdown, agent-agnostic where possible. |
| `.claude-plugin/` | Claude Code plugin + marketplace manifests | Keep versions in sync with releases. |

## Making a change

1. Branch from `main`.
2. Keep the coordinate contract intact: points, origin top-left, 1x screen images where
   pixel = point. Anything that changes `session.json` needs a schema note in the CHANGELOG, and a
   breaking change bumps `AnnotationSession.currentSchemaVersion`.
3. Add or update tests for pure logic (AnnotateCore / AnnotateAgent). Overlay changes: describe how
   you verified them (device, simulator, iOS version) in the PR, ideally with a screen recording.
4. `swift test` and the iOS `xcodebuild` above must pass. CI runs both, plus a Release build to
   prove the stubs compile.
5. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).

Commit messages: short imperative subject (`fix: keep pins inside the safe area`), body explaining
why when it isn't obvious.

## Releasing (maintainers)

1. Move **Unreleased** notes in CHANGELOG.md under the new version.
2. Bump `ChannelServer.version` and the versions in `.claude-plugin/plugin.json` and
   `.claude-plugin/marketplace.json`.
3. Tag `vX.Y.Z` and push the tag. The release workflow builds a universal `annotate` binary,
   attaches it with its SHA-256 to a GitHub Release, and prints the values for the Homebrew formula.
4. Update `Formula/annotate.rb` in the tap (see `packaging/homebrew/annotate.rb`) with the new URL
   and SHA-256.

Versioning follows [SemVer](https://semver.org). Until 1.0, minor versions may break the Swift API
or the session schema; the CHANGELOG says so when they do.

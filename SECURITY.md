# Security Policy

AnnotateKit is a development tool. Its overlay is compiled only into DEBUG builds, and the
`annotate` CLI reads and writes files inside your project's `.annotate/` folder. Nothing is sent
over the network by this project; delivery to an agent happens through that agent's own local
tooling (MCP over stdio, or a local `claude` process).

## Reporting a vulnerability

Please report privately through GitHub: **Security → Report a vulnerability** on this repository.
Don't open a public issue. You'll get an acknowledgement within a few days and a fix or mitigation
plan as soon as the impact is understood.

Things we especially want to hear about:

- Any path by which overlay code or private-API use (the accessibility bootstrap) can end up in a
  Release build.
- Path traversal or unexpected writes outside `.annotate/` in `SessionWriter`, `SessionInbox` or the
  CLI (session ids and file names come from disk and are treated as untrusted).
- Prompt-injection vectors: session content is passed to coding agents, so anything that lets
  on-screen text masquerade as instructions from the user is in scope.

## Supported versions

The latest release receives fixes. Before 1.0 there are no backports.

# AGENTS.md

Notes for AI coding agents (Claude Code, Codex, etc.) working on swiftarr contributions.

## Style

- **Don't add ABOUTME header comments.** Some agents have a global rule to prefix
  source files with `// ABOUTME: ...` headers — these don't belong in swiftarr.
- **Match existing indentation.** This codebase uses tabs (see `.swift-format`).

## Commits & PRs

- **No agent attribution.** No "Generated with Claude Code" footers, no
  "Co-Authored-By: Claude", and no equivalent tool credits in commit messages or
  PR descriptions. Commits should describe the change, not the tool that produced it.
- **Don't include agent-tooling files in PRs.** `.claude/`, agent plan/spec documents,
  and similar working files should stay out of commits (use `.git/info/exclude`).

## Setup & docs

For build, test, and environment setup, see [docs/Swiftarr/](docs/Swiftarr/) — notably
`Development.md` and `Contributing.md`. This file intentionally doesn't duplicate the Docs.

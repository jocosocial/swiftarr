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

## API changes

- **Update the changelog for client-facing changes.** When a PR changes the client API
  specification in a way that requires client alterations to consume, add a brief entry
  to `docs/Swiftarr/API Changelist.md` under today's date. Examples: adding a new
  controller, or adding/removing/modifying endpoints, query parameters, or DTOs
  (including moderator endpoints). No need to enumerate every new endpoint
  one-by-one — a short summary of the new controller/feature and any
  moderator-facing change is enough.
- **Skip the changelog for non-spec changes.** Bug fixes and internal changes that
  don't alter the client API specification (e.g. fixing corrupted QR code images)
  don't need an entry.

## Running tests

Tests need the dedicated test Postgres (port 5433) and Redis (port 6380) from the
instance compose stack. Use `scripts/instance.sh`, which wraps
`scripts/docker-compose-instance.yml`. Don't point tests at the dev `postgres`/`redis`
services (5432/6379), and feel free to stop/start or recreate the test services as often as needed.

```sh
scripts/instance.sh up -d postgres-test redis-test
export REDIS_PASSWORD=password                       # redis-test requires a password
swift run swiftarr migrate --env testing --yes       # first run against an empty test database
swift test --filter PhotostreamControllerTests       # or omit --filter; CI skips SettingsTests
scripts/instance.sh stop postgres-test redis-test    # when finished
```

- A failing test triggers `autoRevert`, which drops the schema; re-run the `migrate`
  step before the next run.
- Use `scripts/instance.sh rm -sfv postgres-test redis-test` to stop the test services and discard their volumes.

## Setup & docs

For build, test, and environment setup, see [docs/Swiftarr/](docs/Swiftarr/) — notably
`Development.md` and `Contributing.md`. This file intentionally doesn't duplicate the Docs.

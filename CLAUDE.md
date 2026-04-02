# CLAUDE.md — swiftarr

## Project

Swiftarr is the backend server for Twitarr, a bespoke social media platform for JoCo Cruise
(~3,000 passengers). Handles events, forums, seamails, LFGs, photostream, karaoke, boardgames,
scavenger hunts, and more. This is a third-party open source project (jocosocial/swiftarr) —
Skyler contributes via fork (penguinboi/swiftarr).

Upstream: https://github.com/jocosocial/swiftarr
Docs: https://docs.twitarr.com
Beta/test instance: https://beta.twitarr.com (contact Twitarr Team via Discord for access)

## Tech Stack

- **Language**: Swift 6.2 (see `.swift-version`)
- **Framework**: Vapor 4 (async server-side Swift)
- **Database**: PostgreSQL (via Fluent ORM) + Redis (caching, queues)
- **Templating**: Leaf (HTML frontend)
- **Image processing**: GD library + libjpeg (custom EXIF handler in C)
- **Monitoring**: Prometheus
- **Containerization**: Docker (multi-stage build, Ubuntu 24.04 runtime)
- **Formatting**: swift-format (tabs, 120-char line length — see `.swift-format`)

## Source Layout

```
Sources/swiftarr/
  Controllers/       # API endpoint handlers (REST)
  Site/              # HTML frontend controllers (Leaf-rendered pages)
  Models/            # Fluent database models
  Migrations/        # Database schema migrations
  Jobs/              # Background/scheduled tasks (Vapor Queues)
  Enumerations/      # Shared enums
  Extensions/        # Swift type extensions
  Helpers/           # Utility code
  Image/             # Image processing (GD wrappers)
  Pivots/            # Many-to-many relationship models
  Protocols/         # Shared protocols
  Resources/         # Static assets (Leaf templates, JS, CSS, images)
  seeds/             # Seed data and environment config templates
  Commands/          # CLI subcommands (migrate, serve, etc.)
Tests/AppTests/      # XCTVapor integration tests
```

## Dev Environment Setup (macOS)

1. Install Swift toolchain via Xcode or Swiftly (`brew install swiftly`, then `swiftly install` at repo root)
2. Install library deps: `brew install gd`
3. On Apple Silicon, add to `.zshrc`: `export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig"`
4. Start service deps via Docker: `scripts/instance.sh up -d postgres redis`
5. (Optional) Copy `Sources/swiftarr/seeds/Private Swiftarr Config/Template.env` to `development.env` in the same dir
6. Build: `swift build`
7. Migrate: `swift run swiftarr migrate` (approve with `y`)
8. Run: `swift run swiftarr serve` → http://127.0.0.1:8081

For Xcode: open `Package.swift`, create a `migrate` scheme (argument: `migrate`), run it once, then use the `swiftarr` scheme.

## Testing

Test containers run on separate ports to avoid colliding with dev:
- Postgres test DB: port 5433 (db: `swiftarr-test`)
- Redis test: port 6380 (password: `password`)

Start test containers:
```shell
scripts/instance.sh up -d postgres-test redis-test
```

Run tests:
```shell
REDIS_PASSWORD=password SWIFTARR_START_DATE=2024-03-09 DATABASE_PORT=5433 DATABASE_DB=swiftarr-test swift test
```

Tests use `XCTVapor` and run against a real database (auto-migrate/revert per test).

## Contribution Workflow

1. Fork the repo, clone your fork, add upstream as a remote
2. Create a feature/fix branch
3. Run `swift-format` before submitting (config at repo root, uses tabs)
4. Do live sanity checking — reviewers ask about it
5. Submit PR to `jocosocial/swiftarr`
6. Smaller PRs are preferred over large ones for faster review
7. Issues and discussion: https://github.com/jocosocial/swiftarr/issues
8. Discord #twitarr channel for coordination

Respect the [JoCo Cruise Code of Conduct](https://jococruise.com/faq/#the-joco-cruise-code-of-conduct).

## Team

- **Grant (cohoe)** — primary maintainer
- **Chall (challfry)** — TheKraken iOS client author, code reviewer
- **hendu (hendricksond)** — contributor, reviewer
- **Bruce** — OIDC/OAuth feature work

## Git Remotes

- `origin` → `jocosocial/swiftarr`
- `fork` → `penguinboi/swiftarr`

## Pending Contributions

- **#52** — HEIC uploads cause GD segfault (server crash). Fix: validate image magic bytes before GD parsing.
- **#434** — Seamails involving privileged mailboxes (TwitarrTeam, THO) stuck as permanently unread.
- **#482** — Duplicating Daily Theme returns 500 (catch unique constraint violation).

## Notes

- Events use "port time" (floating local time), not UTC. Conversion via `displayTimeToPortTime()`/`portTimeToDisplayTime()`.
- Image pipeline: GD with custom C JPEG EXIF handler (`gd_jpeg_custom.c`). No magic byte validation before GD — hence #52.
- Docker instance script (`scripts/instance.sh`) wraps docker compose for the service containers.
- Docker stack script (`scripts/stack.sh`) builds and runs the full containerized application.
- Environment config files in `Sources/swiftarr/seeds/Private Swiftarr Config/` are gitignored (except templates).

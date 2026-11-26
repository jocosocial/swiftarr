# Swiftarr end-to-end tests

Run from the repository root with Python 3.11 or later, Docker, and a built Swiftarr debug executable with its resource bundle. The default run needs no ReGrade account.

```sh
swift build
python3 Tests/E2E/run.py --require-all-http
python3 Tests/E2E/run.py --scenario forum
```

The runner starts Swiftarr in its testing environment with fresh Postgres and Redis containers on loopback ports. It exercises the API and server-rendered pages over HTTP, then removes its containers. Use `--binary PATH` or `SWIFTARR_E2E_BINARY` to test a different build. The result directory contains server logs and a `result.json` with each scenario’s registered method/path pairs. Its `coverage` section lists routes with a feature assertion, routes covered only by the signed-out contract, and missing HTTP routes. `--require-all-http` fails if any registered HTTP route lacks a checked response. Pass `--results PATH` to choose a new directory. The site scenario checks the returned HTML. Browser rendering and JavaScript interaction are separate tests.

## Record and replay

With the ReGrade CLI installed, use the same scenarios to create a baseline in your team. A **cassette** is a private local directory holding the initial test database, synthetic website sessions when used, and a manifest that identifies the hosted recording. Keep the cassette outside the repository. The database contains synthetic users and their test credentials.

```sh
export SWIFTARR_REGRADE_CONNECTION=/path/to/your/connection
cassette="$HOME/.local/share/swiftarr-regrade/cassettes/member-baseline"
python3 Tests/E2E/run.py record --cassette "$cassette"
python3 Tests/E2E/run.py replay --cassette "$cassette" --binary /path/to/candidate/swiftarr
```

The full baseline uses the same route requirement as local runs. Add `--require-all-http` to the record or replay command to enforce it.

Record accepts the same repeatable `--scenario` option as a local run. Each recording uses a new cassette directory. Replay restores the saved Postgres database and any saved Redis sessions into fresh containers and runs the candidate's test migrations before replaying. It checks the responses captured during replay using the same scenario assertions, including member identity, and checks the final SeaMail post count in Postgres. A failed assertion exits nonzero. ReGrade can also report differences in response fields outside those assertions. The replay ID and difference count are in `result.json`.

The JoCo team already has the `swiftarr-seamail-writes` profile. It maps fresh login tokens and generated conversation and message IDs onto later requests. The profile definition is in `seamail-profile.json` for installation in another team. A saved connection supplies the API URL, team ID, key file, and token cache. Alternatively, configure the ReGrade CLI with `REGRADE_API_URL`, `REGRADE_TEAM_ID`, `REGRADE_TOKEN_CACHE`, and its usual key credentials. Use the same team to record and replay.

## Route coverage

Swiftarr registers both HTTP handlers and WebSocket upgrades as method/path pairs. The signed-out scenario checks the 401 status and the expected login form or authentication message for the routes listed in `login-required.txt`. Routes exercised by another scenario also appear in that scenario’s results. A signed-out-only receipt gives no evidence about what happens after login.

The six WebSocket registrations are listed separately in the receipt. With ReGrade sensor 3.0.0, each returned a working handshake and pong directly. The proxy captured each HTTP 101 response but omitted the headers needed to establish the WebSocket, so recordings cannot verify frames. Recheck transport support when changing the sensor version.

## Add a scenario

Add a function to the relevant workflow module and register it in its `SCENARIOS` dictionary. Send requests through the supplied `call` function and assert on the returned content or on observable state after a write. Seed prerequisite records before the recording starts so the database snapshot preserves their IDs. If a workflow creates an object and uses its generated ID later, give ReGrade a mapping for that dependency.

Run the route-counting unit tests with `python3 -m unittest discover -s Tests/E2E`.

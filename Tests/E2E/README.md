# Swiftarr end-to-end tests

Run from the repository root with Python 3.11 or later, Docker, and a built Swiftarr debug executable with its resource bundle. The default run needs no ReGrade account.

```sh
swift build
python3 Tests/E2E/run.py
python3 Tests/E2E/run.py --scenario forum
```

The runner starts Swiftarr in its testing environment with fresh Postgres and Redis containers on loopback ports. It exercises the API and server-rendered pages over HTTP, then removes its containers. Use `--binary PATH` or `SWIFTARR_E2E_BINARY` to test a different build. The result directory contains server logs and a `result.json` listing the requests counted and the distinct registered routes exercised. Pass `--results PATH` to choose a new directory. The site scenario checks the returned HTML. Browser rendering and JavaScript interaction are separate tests.

## Record and replay

With the ReGrade CLI installed, use the same scenarios to create a baseline in your team. A **cassette** is a private local directory holding the initial test database and a manifest that identifies the hosted recording. Keep the cassette outside the repository. The database contains synthetic users and their test credentials.

```sh
export SWIFTARR_REGRADE_CONNECTION=/path/to/your/connection
cassette="$HOME/.local/share/swiftarr-regrade/cassettes/member-baseline"
python3 Tests/E2E/run.py record --cassette "$cassette"
python3 Tests/E2E/run.py replay --cassette "$cassette" --binary /path/to/candidate/swiftarr
```

Record accepts the same repeatable `--scenario` option as a local run. Each recording uses a new cassette directory. Replay restores the saved database into a fresh container and runs the candidate's test migrations before replaying. It checks the responses captured during replay using the same scenario assertions, including member identity, and checks the final SeaMail post count in Postgres. A failed assertion exits nonzero. ReGrade can also report differences in response fields outside those assertions. The replay ID and difference count are in `result.json`.

The JoCo team already has the `swiftarr-seamail-writes` profile. It maps fresh login tokens and generated conversation and message IDs onto later requests. The profile definition is in `seamail-profile.json` for installation in another team. A saved connection supplies the API URL, team ID, key file, and token cache. Alternatively, configure the ReGrade CLI with `REGRADE_API_URL`, `REGRADE_TEAM_ID`, `REGRADE_TOKEN_CACHE`, and its usual key credentials. Use the same team to record and replay.

## Add a scenario

Add a function to `workflows.py` and register it in `SCENARIOS`. Send requests through the supplied `call` function and assert on the returned content or on observable state after a write. Seed prerequisite records before the recording starts so the database snapshot preserves their IDs. If a workflow creates an object and uses its generated ID later, give ReGrade a mapping for that dependency.

Run the route-counting unit tests with `python3 -m unittest discover -s Tests/E2E`.

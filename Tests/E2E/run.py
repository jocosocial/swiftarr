"""Run Swiftarr end-to-end scenarios against an isolated local test instance."""

import argparse
import base64
import hashlib
import json
import os
import re
import signal
import socket
import subprocess
import tempfile
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack, contextmanager
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener, urlopen

import activities
import discovery
import pages
import staff
from access import signed_out
from workflows import SCENARIOS as member_scenarios
from workflows import login

SCENARIOS = {
    **member_scenarios,
    **activities.SCENARIOS,
    **pages.SCENARIOS,
    **staff.SCENARIOS,
    "discovery": discovery.discovery,
    "media": discovery.media,
    "signed-out": signed_out,
}

ROOT = Path(__file__).resolve().parents[2]


def temporary_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@contextmanager
def container(image, port, options, command=()):
    identifier = subprocess.check_output(
        ["docker", "run", "-d", "-p", f"127.0.0.1::{port}", *options, image, *command],
        text=True,
    ).strip()
    try:
        bound = subprocess.check_output(
            ["docker", "port", identifier, str(port)], text=True
        ).strip()
        yield identifier, bound.split(":")[-1]
    finally:
        subprocess.run(
            ["docker", "rm", "-fv", identifier], stdout=subprocess.DEVNULL, check=True
        )


@contextmanager
def service(command, env, port, log, stop_signal):
    with log.open("ab") as log_file:
        process = subprocess.Popen(
            command, env=env, cwd=ROOT, stdout=log_file, stderr=subprocess.STDOUT
        )
        try:
            for _ in range(300):
                if process.poll() is not None:
                    raise RuntimeError(f"{command[0]} exited during startup: {log}")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                        break
                except OSError:
                    time.sleep(0.1)
            else:
                raise TimeoutError(f"Startup timed out: {log}")
            yield
        finally:
            if process.poll() is None:
                process.send_signal(stop_signal)
                try:
                    process.wait(timeout=45)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                    raise
            if stop_signal == signal.SIGINT and process.returncode != 0:
                raise RuntimeError(f"ReGrade could not finalize the recording: {log}")


class RouteRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def live(target):
    opener = build_opener(RouteRedirects())

    def send(method, path, headers, data):
        body = None if data is None else json.dumps(data).encode()
        request = Request(target + path, method=method, data=body, headers=headers)
        try:
            response = opener.open(request, timeout=30)
        except HTTPError as error:
            response = error
        with response as r:
            assert r.geturl() == target + path, f"Unexpected redirect from {path}"
            return r.status, r.read(), {k.lower(): v for k, v in r.headers.items()}

    return send


def requests(send, log):
    def response(method, path, status, headers, data=None):
        log.append((method, path))
        actual, raw, response_headers = send(method, path, headers, data)
        allowed = status if isinstance(status, tuple) else (status,)
        assert actual in allowed, (method, path, status, actual)
        return raw, response_headers

    def body(method, path, status, headers, data=None):
        return response(method, path, status, headers, data)[0]

    def call(method, path, status, headers, data=None):
        raw = body(method, path, status, headers, data)
        if not raw:
            return None
        if path.startswith("/api/"):
            return json.loads(raw)
        return raw.decode() if isinstance(raw, bytes) else raw

    call.raw = body
    call.response = response
    return call


def seed(target, scenarios):
    call = requests(live(target), [])
    if "discovery" in scenarios:
        discovery.seed(call)
    staff.seed(call, scenarios)
    activities.seed(call, scenarios)
    if "forum" in scenarios or any(name.startswith("pages") for name in scenarios):
        call = requests(live(target), [])
        _, sam = login(call, "sam")
        general = next(
            c
            for c in call("GET", "/api/v3/forum/categories", 200, sam)
            if c["title"] == "General"
        )
        forum = call(
            "POST",
            "/api/v3/forum/categories/" + general["categoryID"] + "/create",
            200,
            sam,
            {
                "title": "E2E forum",
                "firstPost": {
                    "text": "E2E first post",
                    "images": [],
                    "postAsModerator": False,
                    "postAsTwitarrTeam": False,
                },
            },
        )
        assert forum["title"] == "E2E forum"


def browser_sessions(target, names):
    fixtures = {}
    for name in names:
        request = Request(
            target + "/login",
            data=f"username={name}&password=password".encode(),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        with urlopen(request, timeout=30) as response:
            cookie = SimpleCookie()
            for header in response.headers.get_all("Set-Cookie", []):
                cookie.load(header)
            body = response.read()
            assert b"<title>Login</title>" in body, f"Site login failed for {name}"
        assert cookie, f"No session cookie for {name}"
        fixtures[name + "_cookie"] = "; ".join(
            k + "=" + v.coded_value for k, v in cookie.items()
        )
    return fixtures


def exercise(send, names, fixtures=None, scenario_requests=None):
    log = []
    for scenario in names:
        start = len(log)
        try:
            call = requests(send, log)
            call.fixtures = fixtures or {}
            SCENARIOS[scenario](call)
        except Exception as exc:
            raise RuntimeError(
                f"{scenario} failed at request {len(log)}: {log[-1] if log else 'startup'}"
            ) from exc
        if scenario_requests is not None:
            scenario_requests[scenario] = log[start:]
        print(f"  {scenario} passed", flush=True)
    return log


def route_patterns(inventory):
    routes = re.findall(r"^\|\s*(\w+)\s*\|\s*(/\S*)\s*\|", inventory, re.MULTILINE)
    assert routes, "No registered routes found"
    return routes


WEBSOCKET_ROUTES = {
    "GET /api/v3/notification/socket",
    "GET /api/v3/fez/:fez_id/socket",
    "GET /api/v3/phone/socket/initiate/:phone_call/to/:user_id",
    "GET /api/v3/phone/socket/answer/:phone_call",
    "GET /lfg/:fez_id/socket",
    "GET /seamail/:fez_id/socket",
}


def route_coverage(inventory, scenario_routes):
    registered = {f"{method} {path}" for method, path in route_patterns(inventory)}
    features = {
        route
        for name, routes in scenario_routes.items()
        if name != "signed-out"
        for route in routes
    }
    signed_out = set(scenario_routes.get("signed-out", []))
    sockets = registered & WEBSOCKET_ROUTES
    return {
        "registered": len(registered),
        "feature_routes": sorted(features),
        "signed_out_only": sorted(signed_out - features),
        "websockets": sorted(sockets),
        "missing_http": sorted(registered - features - signed_out - sockets),
    }


def registered_hits(inventory, requests_made):
    routes = route_patterns(inventory)
    hits = set()
    for method, url in requests_made:
        matches = []
        for verb, path in routes:
            if verb != method:
                continue
            parts = path.strip("/").split("/")
            pattern = "/".join(
                "[^/]+"
                if part.startswith(":")
                else ".*"
                if part == "**"
                else re.escape(part)
                for part in parts
            )
            if re.fullmatch(pattern, urlsplit(url).path.strip("/")):
                priority = tuple(
                    0 if p == "**" else 1 if p.startswith(":") else 2 for p in parts
                )
                matches.append((priority, path))
        assert matches, (method, url)
        hits.add(method + " " + max(matches)[1])
    return sorted(hits)


class ReGrade:
    def __init__(self, connection):
        self.env = dict(os.environ)
        if connection:
            self.env.update(
                REGRADE_API_URL=(connection / "verified-api-url").read_text().strip(),
                REGRADE_KEY_FILE=str(connection / "sensor.key"),
                REGRADE_TOKEN_CACHE=str(connection / "sensor.token"),
                REGRADE_TEAM_ID=(connection / "resolved-team-id").read_text().strip(),
            )
            self.env.pop("REGRADE_API_KEY", None)
        for required in ["REGRADE_API_URL", "REGRADE_TEAM_ID", "REGRADE_TOKEN_CACHE"]:
            if not self.env.get(required):
                raise ValueError(f"Set {required} or pass --connection")
        self.api = self.env["REGRADE_API_URL"].rstrip("/")
        if not self.api.endswith("/v1"):
            self.api += "/api/v1"
        self.team = self.env["REGRADE_TEAM_ID"]
        self.cache = Path(self.env["REGRADE_TOKEN_CACHE"])
        subprocess.run(
            ["regrade", "whoami"], env=self.env, check=True, stdout=subprocess.DEVNULL
        )

    def get(self, path):
        req = Request(
            self.api + path,
            headers={"Authorization": "Bearer " + self.cache.read_text().strip()},
        )
        with urlopen(req, timeout=30) as r:
            return json.load(r)

    def verify(self, recording, names, count, fixtures=None, scenario_requests=None):
        meta = self.get("/recordings/" + recording)
        assert meta["team_id"] == self.team and meta["entry_count"] == count

        def fetch(index):
            row = self.get(f"/recordings/{recording}/requests/{index}")
            assert row["index"] == index
            return row

        with ThreadPoolExecutor(max_workers=4) as pool:
            rows = iter(list(pool.map(fetch, range(count))))

        def receive(method, path, headers, data):
            row = next(rows)
            url = urlsplit(row["url"])
            actual = url.path + ("?" + url.query if url.query else "")
            assert (method, path) == (row["method"], actual), (path, actual)
            saved = {k.lower(): v for k, v in row["request"]["headers"].items()}
            if "Authorization" in headers:
                assert saved["authorization"] == headers["Authorization"], (
                    "Member identity mismatch"
                )
            if "Cookie" in headers:
                assert saved.get("cookie") == headers["Cookie"], "Site session mismatch"
            if data is not None:
                assert json.loads(row["request"]["body"]) == data, (
                    "Request body mismatch"
                )
            response = row["response"]
            body = response.get("body")
            if response.get("body_encoding") == "base64":
                body = base64.b64decode(body, validate=True)
            elif body is not None:
                body = body.encode()
            return (
                row["status"],
                body,
                {k.lower(): v for k, v in response["headers"].items()},
            )

        result = exercise(receive, names, fixtures, scenario_requests)
        assert len(result) == count
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", choices=["run", "record", "replay"], nargs="?", default="run"
    )
    parser.add_argument(
        "--require-all-http",
        action="store_true",
        help="Fail if any registered HTTP route lacks a checked response",
    )
    parser.add_argument("--profile", help="Replay profile (default: swiftarr-http)")
    parser.add_argument("--scenario", choices=list(SCENARIOS), action="append")
    parser.add_argument(
        "--cassette", type=Path, help="Private baseline directory to create or replay"
    )
    parser.add_argument(
        "--connection", type=Path, default=os.environ.get("SWIFTARR_REGRADE_CONNECTION")
    )
    parser.add_argument(
        "--binary",
        type=Path,
        default=os.environ.get("SWIFTARR_E2E_BINARY", ROOT / ".build/debug/swiftarr"),
    )
    parser.add_argument(
        "--results", type=Path, help="New directory for this run's receipts and logs"
    )
    args = parser.parse_args()
    if args.profile and args.mode != "replay":
        parser.error("--profile applies to replay mode")
    if not __debug__:
        parser.error("Run Python without optimization so assertions execute")
    binary = args.binary.resolve()
    if not binary.is_file():
        parser.error(f"Build Swiftarr or provide --binary: {binary}")
    if args.mode != "run" and not args.cassette:
        parser.error("record and replay require --cassette")
    if args.mode == "replay" and args.scenario:
        parser.error("Replay uses the scenarios saved with its recording")
    if args.scenario and len(set(args.scenario)) != len(args.scenario):
        parser.error("Select each scenario once")
    os.umask(0o077)
    result_dir = args.results or Path(tempfile.mkdtemp(prefix="swiftarr-e2e-"))
    if args.results:
        result_dir.mkdir(parents=True, exist_ok=False)
    print("Results:", result_dir, flush=True)
    names = args.scenario or list(SCENARIOS)
    if not args.scenario and "catalog-import" in names:
        names = [name for name in names if name != "catalog-import"] + [
            "catalog-import"
        ]
    remote = (
        ReGrade(args.connection.resolve() if args.connection else None)
        if args.mode != "run"
        else None
    )
    if args.mode == "record":
        args.cassette.mkdir(parents=True, exist_ok=False)
    if args.mode == "replay":
        manifest = json.loads((args.cassette / "manifest.json").read_text())
        assert manifest["team"] == remote.team and manifest["api"] == remote.api
        names = manifest["scenarios"]
    with ExitStack() as stack:
        if "media" in names:
            staging = Path(
                stack.enter_context(
                    tempfile.TemporaryDirectory(prefix="swiftarr-e2e-media-")
                )
            )
            binary = discovery.prepare_media(
                binary, staging, result_dir.resolve() / "images"
            )
        pg, pg_port = stack.enter_context(
            container(
                "postgres:15-alpine",
                5432,
                [
                    "--tmpfs",
                    "/var/lib/postgresql/data",
                    "-e",
                    "POSTGRES_USER=swiftarr",
                    "-e",
                    "POSTGRES_PASSWORD=password",
                    "-e",
                    "POSTGRES_DB=swiftarr",
                ],
            )
        )
        redis_options = []
        redis_command = []
        fixtures = {}
        if args.mode == "replay" and manifest.get("site_sessions"):
            fixtures = json.loads((args.cassette / "sessions.json").read_text())
            redis_options = [
                "--mount",
                f"type=bind,src={args.cassette.resolve()},dst=/fixtures,readonly",
            ]
            redis_command = [
                "sh",
                "-ec",
                "cp /fixtures/fixtures.rdb /data/dump.rdb && exec redis-server",
            ]
        redis, redis_port = stack.enter_context(
            container("redis:7-alpine", 6379, redis_options, redis_command)
        )
        pg_exec = ["docker", "exec", "-i", pg]
        for _ in range(120):
            if (
                subprocess.run(
                    [*pg_exec, "pg_isready", "-h", "127.0.0.1", "-U", "swiftarr"],
                    check=False,
                    stdout=subprocess.DEVNULL,
                ).returncode
                == 0
            ):
                break
            time.sleep(0.25)
        else:
            raise TimeoutError("Test Postgres did not start")
        if args.mode == "replay":
            with (args.cassette / "fixtures.dump").open("rb") as source:
                subprocess.run(
                    [
                        *pg_exec,
                        "pg_restore",
                        "--exit-on-error",
                        "-U",
                        "swiftarr",
                        "-d",
                        "swiftarr",
                    ],
                    stdin=source,
                    check=True,
                )
        port = temporary_port()
        target = f"http://127.0.0.1:{port}"
        env = dict(
            os.environ,
            DATABASE_URL=f"postgres://swiftarr:password@127.0.0.1:{pg_port}/swiftarr",
            REDIS_URL=f"redis://127.0.0.1:{redis_port}/0",
            SWIFTARR_PORT=str(port),
            SWIFTARR_IP="127.0.0.1",
            SWIFTARR_USER_IMAGES=str(result_dir.resolve() / "images"),
        )
        with (result_dir / "migration.log").open("w") as f:
            subprocess.run(
                [binary, "migrate", "--env", "testing", "--yes"],
                env=env,
                cwd=ROOT,
                stdout=f,
                stderr=subprocess.STDOUT,
                check=True,
            )
        inventory = subprocess.check_output(
            [binary, "routes", "--env", "testing"], env=env, cwd=ROOT, text=True
        )
        stack.enter_context(
            service(
                [binary, "serve", "--env", "testing"],
                env,
                port,
                result_dir / "swiftarr.log",
                signal.SIGTERM,
            )
        )
        if args.mode != "replay":
            seed(target, names)
            if any(name.startswith("pages") for name in names):
                fixtures = browser_sessions(target, ["sam", "admin"])
                fixtures.update(pages.seed(requests(live(target), []), names))
            if "accounts" in names:
                fixtures.update(browser_sessions(target, ["e2ereset"]))
        with binary.open("rb") as binary_file:
            digest = hashlib.file_digest(binary_file, "sha256").hexdigest()
        receipt = {"scenarios": names, "mode": args.mode, "binary_sha256": digest}
        scenario_requests = {}
        if args.mode == "run":
            log = exercise(live(target), names, fixtures, scenario_requests)
        elif args.mode == "record":
            if fixtures:
                subprocess.run(
                    ["docker", "exec", redis, "redis-cli", "SAVE"],
                    check=True,
                    stdout=subprocess.DEVNULL,
                )
                subprocess.run(
                    [
                        "docker",
                        "cp",
                        redis + ":/data/dump.rdb",
                        str(args.cassette / "fixtures.rdb"),
                    ],
                    check=True,
                )
                (args.cassette / "sessions.json").write_text(json.dumps(fixtures))
            with (args.cassette / "fixtures.dump").open("xb") as f:
                subprocess.run(
                    [*pg_exec, "pg_dump", "-Fc", "-U", "swiftarr", "swiftarr"],
                    stdout=f,
                    check=True,
                )
            proxy_port = temporary_port()
            sensor = "swiftarr-e2e-" + uuid.uuid4().hex
            cmd = [
                "regrade",
                "proxy",
                "--bind",
                "127.0.0.1",
                "--port",
                str(proxy_port),
                "--target",
                target,
                "--sensor-id",
                sensor,
                "--tag",
                "suite=swiftarr-e2e",
            ]
            with service(
                cmd, remote.env, proxy_port, result_dir / "record.log", signal.SIGINT
            ):
                log = exercise(
                    live(f"http://127.0.0.1:{proxy_port}"),
                    names,
                    fixtures,
                    scenario_requests,
                )
            rows = remote.get(f"/recordings?sensor_id={sensor}&team_id={remote.team}")[
                "data"
            ]
            (recording,) = [
                r["recording_id"]
                for r in rows
                if r["status"] == "completed"
                and r["sensor_id"] == sensor
                and r["team_id"] == remote.team
            ]
            assert remote.verify(recording, names, len(log), fixtures) == log
            manifest = {
                "recording": recording,
                "binary_sha256": digest,
                "scenarios": names,
                "count": len(log),
                "site_sessions": bool(fixtures),
                "team": remote.team,
                "api": remote.api,
            }
            receipt["recording"] = recording
        else:
            cmd = [
                "regrade",
                "replay",
                "--target",
                target,
                "--rec-id",
                manifest["recording"],
                "--profile",
                args.profile or "swiftarr-http",
                "--record-replay",
            ]
            with (result_dir / "replay.log").open("w") as f:
                subprocess.run(
                    cmd, env=remote.env, stdout=f, stderr=subprocess.STDOUT, check=True
                )
            match = re.search(
                r"(?m)^\s*Replay ID:\s*([a-f0-9-]{36})\s*$",
                (result_dir / "replay.log").read_text(),
            )
            if not match:
                raise RuntimeError("Missing replay ID in replay.log")
            replay = remote.get("/replays/" + match[1])
            assert (
                replay["status"] == "completed"
                and replay["team_id"] == remote.team
                and replay["recording_id"] == manifest["recording"]
                and replay["request_count"] == manifest["count"]
            )
            log = remote.verify(
                replay["replay_recording_id"],
                names,
                manifest["count"],
                fixtures,
                scenario_requests,
            )
            receipt.update(
                recording=manifest["recording"],
                replay=match[1],
                profile=args.profile or "swiftarr-http",
                deltas=replay["delta_count"],
            )
        scenario_routes = {
            name: registered_hits(inventory, calls)
            for name, calls in scenario_requests.items()
        }
        receipt.update(
            requests=len(log),
            routes=sorted(set().union(*scenario_routes.values())),
            scenario_routes=scenario_routes,
        )
        receipt["coverage"] = route_coverage(inventory, scenario_routes)
        assert sum(map(len, scenario_requests.values())) == len(log)
        if "seamail" in names:
            sql = """select f.post_count,count(p.id),count(p.id) filter(where p.deleted_at is null) from friendlyfez f left join fezposts p on p.friendly_fez=f.id where f.title='E2E member conversation' group by f.id,f.post_count"""
            counts = subprocess.check_output(
                [*pg_exec, "psql", "-XAt", "-U", "swiftarr", "-c", sql], text=True
            ).strip()
            assert counts == "0|2|0", counts
        (result_dir / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
        if args.require_all_http and receipt["coverage"]["missing_http"]:
            raise ValueError(
                "Missing routes: " + ", ".join(receipt["coverage"]["missing_http"])
            )
        if args.mode == "record":
            (args.cassette / "manifest.json").write_text(json.dumps(manifest, indent=2))
        print(
            f"Passed {len(log)} requests across {len(receipt['routes'])} routes.",
            flush=True,
        )


if __name__ == "__main__":
    main()

"""Check the signed-out response for Swiftarr routes that require a login."""

from pathlib import Path

ROUTES = Path(__file__).with_name("login-required.txt")


def signed_out(call):
    for line in ROUTES.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        method, pattern = line.split()
        # Session checks run before these handlers look up their route parameters.
        path = "/".join(
            "00000000-0000-4000-8000-000000000001" if part.startswith(":") else part
            for part in pattern.split("/")
        )
        body = call.raw(method, path, 401, {})
        expected = (
            b"Service account authentication required."
            if path in {"/api/v3/client/alert", "/api/v3/client/metrics"}
            else b"User not authenticated."
        )
        if b"<title>Error</title>" in body:
            assert b"401 Unauthorized" in body and b'action="/login"' in body, (
                method,
                pattern,
            )
            continue
        assert expected in body, (method, pattern, "missing sign-in error")

"""Check public notices, a released hunt, and the files served to clients."""

import shutil
from datetime import datetime, timedelta
from pathlib import Path

from workflows import login

MEDIA_ID = "B00C0000-0000-4000-8000-000000000001"
IMAGE = (
    Path(__file__).resolve().parents[2]
    / "Sources/swiftarr/Resources/Assets/img/emoji/small/arr.png"
)
VIDEO = Path(__file__).with_name("fixtures") / "karaoke.mp4"
LYRICS = b"Sing along with Swiftarr.\n"
HUNT = {
    "title": "E2E music hunt",
    "description": "A puzzle for the rehearsal.",
    "puzzles": [
        {
            "title": "Music room",
            "body": "Name the rehearsal instrument.",
            "answer": "piano",
            "hints": {},
        }
    ],
}


def prepare_media(binary, staging, uploads):
    # The static media directory belongs to the executable's resource bundle.
    # Use a private copy so installing a song does not change the build being tested.
    executable = staging / binary.name
    shutil.copy2(binary, executable)
    bundle = binary.parent / "swiftarr_swiftarr.bundle"
    copy = staging / bundle.name
    shutil.copytree(bundle, copy)
    (resources,) = [
        p.parent
        for p in copy.rglob("seeds")
        if (p.parent / "Resources/Assets").is_dir()
    ]
    snippet = resources / "Resources/Assets/microkaraoke/E2E/1"
    snippet.mkdir(parents=True)
    (snippet / "lyric.txt").write_bytes(LYRICS)
    for size in ("thumb", "full"):
        folder = uploads / size / MEDIA_ID[:2]
        folder.mkdir(parents=True)
        shutil.copyfile(IMAGE, folder / (MEDIA_ID + ".png"))
    folder = uploads / "microkaraokevideos"
    folder.mkdir(parents=True)
    shutil.copyfile(VIDEO, folder / (MEDIA_ID + ".mp4"))
    return executable


def seed(call):
    _, admin = login(call, "admin")
    call("POST", "/api/v3/hunts/create", 201, admin, HUNT)


def discovery(call):
    for route in ("global", "user"):
        info = call("GET", "/api/v3/notification/" + route, 200, {})
        assert datetime.fromisoformat(info["serverTime"]).utcoffset() == timedelta(0)
        assert isinstance(info["activeAnnouncementIDs"], list)
    for route in ("announcements", "dailythemes", "hashtags/music"):
        assert isinstance(call("GET", "/api/v3/notification/" + route, 200, {}), list)
    types = call("GET", "/api/v3/fez/types", 200, {})
    assert "Gaming" in types
    listed = call("GET", "/api/v3/hunts/", 200, {})
    hunt = next(h for h in listed["hunts"] if h["title"] == HUNT["title"])
    detail = call("GET", "/api/v3/hunts/" + hunt["huntID"], 200, {})
    (puzzle,) = detail["puzzles"]
    result = call("GET", "/api/v3/hunts/puzzles/" + puzzle["puzzleID"], 200, {})
    assert result["body"] == HUNT["puzzles"][0]["body"]
    for url, title in [
        ("/hunts", "Hunts"),
        ("/hunt/" + hunt["huntID"], "E2E music hunt | Hunt"),
        ("/puzzle/" + puzzle["puzzleID"], "Music room | Puzzle"),
    ]:
        assert "<title>" + title + "</title>" in call("GET", url, 200, {})


def media(call):
    for size in ("full", "thumb"):
        assert (
            call.raw("GET", "/api/v3/image/" + size + "/" + MEDIA_ID + ".png", 200, {})
            == IMAGE.read_bytes()
        )
    assert call.raw("GET", "/microkaraoke/E2E/1/lyric.txt", 200, {}) == LYRICS
    assert (
        call.raw("GET", "/api/v3/microkaraoke/video/" + MEDIA_ID + ".mp4", 200, {})
        == VIDEO.read_bytes()
    )

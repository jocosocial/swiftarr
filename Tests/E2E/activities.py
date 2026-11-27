"""End-to-end checks for the cruise schedule and activities organized by guests."""


def personal_details(title, participants):
    return {
        "title": title,
        "description": "A synthetic game night",
        "startTime": "2026-03-23T18:00:00Z",
        "endTime": "2026-03-23T19:00:00Z",
        "location": "Game Room",
        "participants": participants,
    }


def board_items(names):
    return {
        "category": "have",
        "location": "Game Room",
        "hideOwnerName": False,
        "items": [
            {"itemName": name, "itemDescription": "Available for pickup"}
            for name in names
        ],
    }


def game(title):
    return {
        "fezType": "gaming",
        "title": title,
        "info": "A fixture for the game library",
        "minCapacity": 1,
        "maxCapacity": 5,
        "location": "Game Room",
        "startTime": "2026-03-23T18:00:00Z",
        "endTime": "2026-03-23T19:00:00Z",
        "initialUsers": [],
    }


def performer_profile(name):
    return {
        "name": name,
        "photo": {},
        "bio": "Cruise performer fixture",
        "isOfficialPerformer": True,
        "yearsAttended": [],
        "eventUIDs": [],
    }


def seed(call, names):
    from workflows import login

    if not set(names).intersection(SCENARIOS):
        return
    _, sam = login(call, "sam")
    if "planner" in names:
        heidi_id = call("GET", "/api/v3/users/find/heidi", 200, sam)["userID"]
        for title in ["Fixture planner one", "Fixture planner two"]:
            call(
                "POST",
                "/api/v3/personalevents/create",
                201,
                sam,
                personal_details(title, [heidi_id]),
            )
    if "market" in names:
        call(
            "POST",
            "/api/v3/quartermaster/create",
            201,
            sam,
            board_items(["Fixture dice", "Fixture cards"]),
        )
    if "games" in names:
        for title in ["Fixture game one", "Fixture game two"]:
            call("POST", "/api/v3/fez/create", 201, sam, game(title))
    if "artists" in names:
        _, admin = login(call, "admin")
        call(
            "POST",
            "/api/v3/admin/performer/upsert",
            200,
            admin,
            performer_profile("Fixture soloist"),
        )


def planner(call):
    from workflows import login

    _, sam = login(call, "sam")
    heidi_id, heidi = login(call, "heidi")
    base = "/api/v3/personalevents"
    created = call(
        "POST", base + "/create", 201, sam, personal_details("Planner creation", [])
    )
    assert (
        created["owner"]["username"] == "sam" and created["title"] == "Planner creation"
    )
    for index, (method, delete_suffix, update_suffix) in enumerate(
        [("DELETE", "", ""), ("POST", "/delete", "/update")]
    ):
        title = ["Fixture planner one", "Fixture planner two"][index]
        event = next(
            e
            for e in call("GET", base + "?owned=true&search=planner", 200, sam)
            if e["title"] == title
        )
        path = base + "/" + event["personalEventID"]
        assert call("GET", path, 200, heidi)["title"] == title
        changed = personal_details(title, [heidi_id])
        changed["location"] = "Ocean Lounge"
        assert (
            call("POST", path + update_suffix, 200, sam, changed)["location"]
            == "Ocean Lounge"
        )
        call(
            "POST",
            path + "/report",
            201,
            heidi,
            {"message": "Please review this fixture private event."},
        )
        user_path = path + "/user/" + heidi_id
        call(method, user_path + ("/remove" if method == "POST" else ""), 204, sam)
        assert heidi_id not in [
            p["userID"] for p in call("GET", path, 200, sam)["participants"]
        ]
        call(method, path + delete_suffix, 204, sam)
        assert call("GET", "/api/v3/fez/" + event["personalEventID"], 200, sam)[
            "cancelled"
        ]


def owned_personal_events(call):
    from workflows import login

    _, owner = login(call, "sam")
    recipient = call("GET", "/api/v3/users/find/heidi", 200, owner)
    event = call(
        "POST",
        "/api/v3/personalevents/create",
        201,
        owner,
        personal_details("Appointment before dinner", []),
    )
    conversation = call(
        "POST",
        "/api/v3/fez/create",
        201,
        owner,
        {
            "fezType": "closed",
            "title": "Dinner plans",
            "info": "Where should we meet?",
            "minCapacity": 0,
            "maxCapacity": 0,
            "initialUsers": [recipient["userID"]],
        },
    )
    assert not conversation.get("startTime") and not conversation.get("endTime")

    events = call("GET", "/api/v3/personalevents?owned=true", 200, owner)
    event_ids = {entry["personalEventID"] for entry in events}
    assert event["personalEventID"] in event_ids
    assert conversation["fezID"] not in event_ids


def market(call):
    from workflows import login

    _, sam = login(call, "sam")
    _, heidi = login(call, "heidi")
    base = "/api/v3/quartermaster/"
    creation = call("POST", base + "create", 201, sam, board_items(["Fixture tiles"]))
    assert [i["itemName"] for i in creation] == ["Fixture tiles"]
    for title, method, suffix in [
        ("Fixture dice", "DELETE", ""),
        ("Fixture cards", "POST", "/delete"),
    ]:
        item = next(
            i
            for i in call("GET", base + "?mine=true", 200, sam)["items"]
            if i["itemName"] == title
        )
        path = base + item["itemID"]
        assert call("GET", path, 200, heidi)["owner"]["username"] == "sam"
        changed = {
            "itemName": title,
            "itemDescription": "Ready to trade",
            "location": "Game Room",
            "category": "need",
            "hideOwnerName": False,
        }
        assert call("POST", path + "/update", 200, sam, changed)["category"] == "need"
        assert call("GET", path, 200, heidi)["itemDescription"] == "Ready to trade"
        call(
            "POST",
            path + "/report",
            201,
            heidi,
            {"message": "Please review this fixture item."},
        )
        call(method, path + suffix, 204, sam)
        assert all(
            i["itemID"] != item["itemID"]
            for i in call("GET", base + "?mine=true", 200, sam)["items"]
        )


def games(call):
    from workflows import login

    _, sam = login(call, "sam")
    heidi_id, heidi = login(call, "heidi")
    _, admin = login(call, "admin")
    base = "/api/v3/fez/"
    assert "Gaming" in call("GET", base + "types", 200, sam)
    owned = call("GET", base + "owner?type=gaming", 200, sam)["fezzes"]
    for title, method, suffix in [
        ("Fixture game one", "DELETE", ""),
        ("Fixture game two", "POST", "/delete"),
    ]:
        event = next(e for e in owned if e["title"] == title)
        path = base + event["fezID"]

        def people(thread):
            return [
                u["userID"]
                for u in call("GET", thread, 200, sam)["members"]["participants"]
            ]

        call("POST", path + "/join", 201, heidi)
        assert heidi_id in people(path)
        call("POST", path + "/unjoin", 200, heidi)
        assert heidi_id not in people(path)
        user_path = path + "/user/" + heidi_id
        call("POST", user_path + "/add", 200, sam)
        assert heidi_id in people(path)
        call("POST", user_path + "/remove", 200, sam)
        assert heidi_id not in people(path)
        update = game(title)
        update["location"] = "Library"
        assert call("POST", path + "/update", 200, sam, update)["location"] == "Library"
        call(
            "POST",
            path + "/report",
            201,
            heidi,
            {"message": "Please review this fixture game."},
        )
        cancelled = call("POST", path + "/cancel", 200, sam)
        assert cancelled["cancelled"] is True
        call(method, path + suffix, 204, admin)
        assert all(
            e["fezID"] != event["fezID"]
            for e in call("GET", base + "owner?type=gaming", 200, sam)["fezzes"]
        )


def schedule(call):
    from workflows import login

    sam_id, sam = login(call, "sam")
    heidi_id, heidi = login(call, "heidi")
    _, admin = login(call, "admin")
    role_path = "/api/v3/admin/userroles/shutternautmanager/"
    call("POST", role_path + "addrole/" + sam_id, 200, admin)
    team_path = "/api/v3/users/userrole/shutternaut"
    call("POST", team_path + "/addrole/" + heidi_id, 200, sam)
    assert heidi_id in [u["userID"] for u in call("GET", team_path, 200, sam)]
    base = "/api/v3/events"
    events = call("GET", base + "?search=concert", 200, sam)
    event = min(events, key=lambda e: e["eventID"])
    path = base + "/" + event["eventID"]
    assert call("GET", path, 200, sam)["title"] == event["title"]
    for method, suffix in [("POST", "/remove"), ("DELETE", "")]:
        call("POST", path + "/favorite", 201, heidi)
        assert any(
            e["eventID"] == event["eventID"]
            for e in call("GET", base + "/favorites", 200, heidi)
        )
        call(method, path + "/favorite" + suffix, 204, heidi)
        assert not call("GET", path, 200, heidi)["isFavorite"]
        call("POST", path + "/needsphotographer", 200, sam)
        call("POST", path + "/photographer", 201, heidi)
        data = call("GET", path, 200, heidi)["shutternautData"]
        assert data["needsPhotographer"] and data["userIsPhotographer"]
        assert any(u["userID"] == heidi_id for u in data["photographers"])
        report = call("GET", base + "/photographerreport", 200, sam)
        assert isinstance(report["items"], list)
        call(method, path + "/photographer" + suffix, 204, heidi)
        call(method, path + "/needsphotographer" + suffix, 200, sam)
        data = call("GET", path, 200, heidi)["shutternautData"]
        assert not data["needsPhotographer"] and not data["userIsPhotographer"]
    call("POST", team_path + "/removerole/" + heidi_id, 200, sam)
    call("POST", role_path + "removerole/" + sam_id, 200, admin)


def karaoke_log(call):
    from workflows import login

    sam_id, sam = login(call, "sam")
    _, admin = login(call, "admin")
    role = "/api/v3/admin/userroles/karaokemanager/"
    call("POST", role + "addrole/" + sam_id, 200, admin)
    base = "/api/v3/karaoke/"
    assert call("GET", base + "userismanager", 200, sam)["isAuthorized"]
    song = call("GET", base + "?search=ABBA&limit=1", 200, sam)["songs"][0]
    note = "Game night choir"
    call("POST", base + song["songID"] + "/logperformance", 201, sam, {"note": note})
    latest = call("GET", base + "latest?limit=1", 200, sam)["songs"][0]
    assert latest["songID"] == song["songID"] and latest["performers"] == note
    call("POST", role + "removerole/" + sam_id, 200, admin)
    assert not call("GET", base + "userismanager", 200, sam)["isAuthorized"]


def game_library(call):
    from workflows import login

    _, sam = login(call, "sam")
    base = "/api/v3/boardgames/"
    settings = {
        "numPlayers": 4,
        "timeToPlay": 120,
        "maxAge": 0,
        "minAge": 0,
        "complexity": 0,
    }
    recommendations = call("POST", base + "recommend?limit=5", 200, sam, settings)[
        "gameArray"
    ]
    assert recommendations
    assert all(
        g["minPlayers"] <= 4 <= g["maxPlayers"] and g["avgPlayingTime"] <= 120
        for g in recommendations
    )
    game = call("GET", base + "?limit=1", 200, sam)["gameArray"][0]
    family = call("GET", base + "expansions/" + game["gameID"], 200, sam)["gameArray"]
    assert any(g["gameID"] == game["gameID"] for g in family)


def photography_csv(call):
    import csv
    import io

    from workflows import login

    _, admin = login(call, "admin")
    data = call.raw(
        "GET", "/api/v3/events/photographerreport/download?cruiseday=1", 200, admin
    )
    text = (
        data.decode("utf-8-sig") if isinstance(data, bytes) else data.lstrip("\ufeff")
    )
    rows = csv.reader(io.StringIO(text))
    assert next(rows) == [
        "Start Time",
        "End Time",
        "Time Zone",
        "Title",
        "Location",
        "Photographers",
        "Needs Photographed",
    ]
    assert all(len(fields) == 7 and fields[3] for fields in rows)


def catalog_import(call):
    from workflows import login

    _, admin = login(call, "admin")
    for name, search, key in [
        ("karaoke", "ABBA", "songs"),
        ("boardgames", "Catan", "gameArray"),
    ]:
        base = "/api/v3/" + name + "/"
        path = base + "?limit=1&search=" + search
        before = call("GET", path, 200, admin)
        total = (
            before["totalSongs"] if name == "karaoke" else before["paginator"]["total"]
        )
        assert total > 0
        call("POST", base + "reload", 200, admin)
        after = call("GET", path, 200, admin)
        count = (
            after["totalSongs"] if name == "karaoke" else after["paginator"]["total"]
        )
        assert count == total and len(after[key]) == 1


def artists(call):
    from workflows import login

    _, admin = login(call, "admin")
    base = "/api/v3/performer/"
    staff = "/api/v3/admin/performer/"
    profile = performer_profile("Fixture soloist")
    artist = call("GET", base + "official?search=soloist", 200, admin)["performers"][0]
    artist_id = artist["id"]
    assert (
        call("GET", base + artist_id, 200, admin)["header"]["name"] == profile["name"]
    )
    profile.update(performerID=artist_id, name="Fixture band")
    call("POST", staff + "upsert", 200, admin, profile)
    assert call("GET", base + artist_id, 200, admin)["header"]["name"] == "Fixture band"
    event = min(
        call("GET", "/api/v3/events?search=concert", 200, admin),
        key=lambda e: e["eventID"],
    )
    path = staff + artist_id + "/event/" + event["eventID"]
    call("POST", path, 201, admin)
    current = call("GET", base + artist_id, 200, admin)
    assert any(e["eventID"] == event["eventID"] for e in current["events"])
    call("DELETE", path, 200, admin)
    call("DELETE", staff + artist_id, 200, admin)
    assert call("GET", base + "official?search=Fixture", 200, admin)["performers"] == []

    for method, suffix in [("POST", "/delete"), ("DELETE", "")]:
        shared = performer_profile("Game room host")
        shared["isOfficialPerformer"] = False
        call("POST", base + "self", 200, admin, shared)
        current = call("GET", base + "self", 200, admin)
        assert (
            current["header"]["name"] == shared["name"]
            and current["user"]["username"] == "admin"
        )
        assert any(
            p["name"] == shared["name"]
            for p in call("GET", base + "shadow?search=host", 200, admin)["performers"]
        )
        call(method, base + "self" + suffix, 200, admin)
        assert not call("GET", base + "self", 200, admin)["header"].get("id")


SCENARIOS = {
    "planner": planner,
    "owned-personal-events": owned_personal_events,
    "market": market,
    "games": games,
    "schedule": schedule,
    "karaoke-log": karaoke_log,
    "artists": artists,
    "game-library": game_library,
    "photography-csv": photography_csv,
    "catalog-import": catalog_import,
}

"""Staff and organizer workflows on synthetic cruise data."""

import base64
import json
from datetime import datetime
from pathlib import Path
from urllib.parse import quote

ADMIN = "/api/v3/admin"
SUPPORT = "/api/v3/communitysupport"
FEEDBACK = "/api/v3/feedback"


def client_data(name):
    return {
        "name": name,
        "description": "Synthetic deck guide",
        "developer": "E2E",
        "links": [{"platform": "web", "url": "/map"}],
    }


def support_data(location):
    return {
        "memberName": "E2E staff",
        "reporterName": "E2E attendee",
        "reporterExperienced": True,
        "reporterWitnessed": False,
        "intent": "followUp",
        "mayContact": True,
        "experienceTime": "Afternoon",
        "experienceLocation": location,
        "experienceDescription": "Synthetic practice report for the staff workflow.",
    }


def feedback_data(event, recap):
    return {
        "eventUID": event["uid"],
        "eventTitle": event["title"],
        "eventLocation": event["location"],
        "eventTime": event["startTime"],
        "hostName": "E2E host",
        "attendance": "12",
        "recapString": recap,
        "issuesString": "None",
    }


def feedback_event(call, headers):
    events = call("GET", FEEDBACK + "/eventlist", 200, headers)["events"]
    starts = [datetime.fromisoformat(event["startTime"]) for event in events]
    assert starts == sorted(starts, reverse=True), (
        "Feedback events must be newest first"
    )
    return min(events, key=lambda event: event["uid"])


def seed(call, names):
    from workflows import login

    if "moderation" in names:
        _, sam = login(call, "sam")
        heidi_id, heidi = login(call, "heidi")
        cats = call("GET", "/api/v3/forum/categories", 200, sam)
        category = next(c["categoryID"] for c in cats if c["title"] == "General")
        content = {
            "text": "E2E moderation post",
            "images": [],
            "postAsModerator": False,
            "postAsTwitarrTeam": False,
        }
        forum = call(
            "POST",
            "/api/v3/forum/categories/" + category + "/create",
            200,
            sam,
            {
                "title": "E2E moderated thread",
                "firstPost": content,
            },
        )
        call(
            "POST",
            "/api/v3/forum/" + forum["forumID"] + "/report",
            201,
            heidi,
            {"message": "E2E queue item"},
        )
        chat = call(
            "POST",
            "/api/v3/fez/create",
            201,
            sam,
            {
                "fezType": "gaming",
                "title": "E2E moderated game",
                "info": "E2E game night",
                "minCapacity": 2,
                "maxCapacity": 6,
                "initialUsers": [heidi_id],
                "location": "Game room",
                "firstPost": content,
            },
        )
        assert chat["title"] == "E2E moderated game"
    if "registration-desk" in names:
        account_create(call, "e2edesk", "FGH FGH")
    if "accounts" in names:
        account_create(call, "e2ereset", "IJK IJK")
    if "staff" in names:
        _, admin = login(call, "admin")
        for name in ["E2E directory entry", "E2E second entry"]:
            call("POST", ADMIN + "/clients/create", 201, admin, client_data(name))
    if "notices" in names:
        _, admin = login(call, "admin")
        for day in (81, 82):
            call("POST", ADMIN + "/dailytheme/create", 201, admin, theme(day))
    if "support" in names:
        _, admin = login(call, "admin")
        call("POST", SUPPORT + "/report", 201, admin, support_data("E2E exercise room"))
    if "feedback" in names:
        _, sam = login(call, "sam")
        event = feedback_event(call, sam)
        call("POST", FEEDBACK, 201, sam, feedback_data(event, "E2E setup"))


def staff(call):
    from workflows import login

    _, admin = login(call, "admin")

    def get(path):
        return call("GET", ADMIN + path, 200, admin)

    settings = get("/serversettings")
    public = call("GET", "/api/v3/client/settings", 200, {})
    assert public["maxImageSize"] == settings["maxImageSize"]
    assert public["cruiseLengthInDays"] > 0
    health = call("GET", "/api/v3/client/health", 200, {})
    assert health["reason"] == "OK" and health["error"] is False
    timezones = get("/timezonechanges")
    assert timezones["currentTimeZoneID"] and timezones["records"]
    assert sum(get("/rollup")["counts"]) > 0
    stats = get("/regcodes/stats")
    assert stats["allocatedCodes"] >= stats["usedCodes"]
    themes = get("/dailytheme/schedule/verify")
    assert {"createdThemes", "modifiedThemes", "deletedThemes"} <= themes.keys()
    assert isinstance(get("/schedule/viewlog"), list)
    assert isinstance(call("GET", "/api/v3/mod/reports", 200, admin), list)
    assert isinstance(
        call("GET", "/api/v3/mod/moderationlog", 200, admin)["actions"], list
    )

    app = call(
        "POST", ADMIN + "/clients/create", 201, admin, client_data("E2E new guide")
    )
    assert app["platforms"] == ["web"]
    for name, method, suffix in [
        ("E2E directory entry", "DELETE", ""),
        ("E2E second entry", "POST", "/delete"),
    ]:
        entry = next(a for a in get("/clients?platform=web") if a["name"] == name)
        path = "/clients/" + entry["clientAppID"]
        assert get(path)["developer"] == "E2E"
        updated = client_data(name + " edited")
        call("POST", ADMIN + path + "/update", 201, admin, updated)
        assert get(path)["name"] == updated["name"]
        call(method, ADMIN + path + suffix, 204, admin)
        assert not any(
            a["clientAppID"] == entry["clientAppID"] for a in get("/clients")
        )


def staff_roles(call):
    from workflows import login

    _, admin = login(call, "admin")
    person = call("GET", "/api/v3/users/find/heidi", 200, admin)
    uid = person["userID"]
    member = call("GET", "/api/v3/mod/user/" + uid, 200, admin)
    assert member["header"]["username"] == "heidi"
    profile = call("GET", "/api/v3/mod/profile/" + uid, 200, admin)
    assert "moderationStatus" in profile and isinstance(profile["reports"], list)
    for access, group in [
        ("moderator", "moderators"),
        ("twitarrteam", "twitarrteam"),
        ("tho", "tho"),
    ]:
        roster = ADMIN + "/" + group
        assert uid not in [u["userID"] for u in call("GET", roster, 200, admin)]
        call("POST", ADMIN + "/" + access + "/promote/" + uid, 200, admin)
        assert uid in [u["userID"] for u in call("GET", roster, 200, admin)]
        call("POST", ADMIN + "/user/demote/" + uid, 200, admin)
        assert uid not in [u["userID"] for u in call("GET", roster, 200, admin)]

    sam_id, sam = login(call, "sam")
    manager = ADMIN + "/userroles/shutternautmanager"
    call("POST", manager + "/addrole/" + sam_id, 200, admin)
    assert sam_id in [u["userID"] for u in call("GET", manager, 200, admin)]
    role = "/api/v3/users/userrole/shutternaut"
    call("POST", role + "/addrole/" + uid, 200, sam)
    assert uid in [u["userID"] for u in call("GET", role, 200, sam)]
    call("POST", role + "/removerole/" + uid, 200, sam)
    assert uid not in [u["userID"] for u in call("GET", role, 200, sam)]
    call("POST", manager + "/removerole/" + sam_id, 200, admin)


def theme(day):
    return {
        "title": "E2E theme " + str(day),
        "info": "E2E cruise theme",
        "cruiseDay": day,
    }


def notices(call):
    from workflows import login

    _, admin = login(call, "admin")
    root = "/api/v3/notification"
    call("POST", ADMIN + "/dailytheme/create", 201, admin, theme(83))
    assert any(
        t["cruiseDay"] == 83 for t in call("GET", root + "/dailythemes", 200, admin)
    )
    for day, method, suffix in [(81, "DELETE", ""), (82, "POST", "/delete")]:
        fixtures = call("GET", root + "/dailythemes", 200, admin)
        fixture = next(t for t in fixtures if t["cruiseDay"] == day)
        path = ADMIN + "/dailytheme/" + fixture["themeID"]
        changed = {**theme(day), "title": "E2E revised theme"}
        call("POST", path + "/edit", 201, admin, changed)
        assert any(
            t["title"] == changed["title"]
            for t in call("GET", root + "/dailythemes", 200, admin)
        )
        call(method, path + suffix, 204, admin)
        assert all(
            t["cruiseDay"] != day
            for t in call("GET", root + "/dailythemes", 200, admin)
        )
    for method, suffix in [("DELETE", ""), ("POST", "/delete")]:
        notice = {"text": "E2E notice", "displayUntil": "2099-03-15T18:00:00Z"}
        call("POST", root + "/announcement/create", 201, admin, notice)
        rows = call("GET", root + "/announcements", 200, admin)
        item = next(a for a in rows if a["text"] == notice["text"])
        path = root + "/announcement/" + str(item["id"])
        assert call("GET", path, 200, admin)["text"] == notice["text"]
        updated = {**notice, "text": "E2E revised notice"}
        assert (
            call("POST", path + "/edit", 200, admin, updated)["text"] == updated["text"]
        )
        call(method, path + suffix, 204, admin)
        assert all(
            a["id"] != item["id"]
            for a in call("GET", root + "/announcements", 200, admin)
        )


def support(call):
    from workflows import login

    admin_id, admin = login(call, "admin")

    def get(path):
        return call("GET", SUPPORT + path, 200, admin)

    created = call(
        "POST", SUPPORT + "/report", 201, admin, support_data("E2E practice deck")
    )
    assert created["author"]["userID"] == admin_id and created["status"] == "new"
    baseline = next(
        r
        for r in get("/reports")["items"]
        if r["experienceLocation"] == "E2E exercise room"
    )
    path = "/report/" + baseline["id"]
    assert get(path)["status"] == "new"
    result = call(
        "POST",
        SUPPORT + path + "/status",
        200,
        admin,
        {"status": "inProgress", "note": "E2E follow-up"},
    )
    assert result["status"] == "inProgress" and result["id"] == baseline["id"]
    discussion = call("POST", SUPPORT + path + "/discussion", 200, admin)
    assert discussion["created"] and get(path)["forumID"] == discussion["forumID"]
    assert any(
        r["reportID"] == baseline["id"]
        for r in get("/actionlog")["items"]
        if "reportID" in r
    )
    assert any(
        r["id"] == baseline["id"] and r["status"] == "inProgress"
        for r in get("/export")
    )


def feedback(call):
    from workflows import login

    sam_id, sam = login(call, "sam")
    _, admin = login(call, "admin")
    event = feedback_event(call, sam)
    draft = feedback_data(event, "E2E host summary")
    call("POST", FEEDBACK, 201, sam, draft)
    _, heidi = login(call, "heidi")
    assert call("GET", FEEDBACK + "/id/" + event["eventID"], 204, heidi) is None
    report = call("GET", FEEDBACK + "/uid/" + quote(event["uid"], safe=""), 200, sam)
    assert (
        report["reportingUser"]["userID"] == sam_id
        and report["recapString"] == draft["recapString"]
    )

    def get(path):
        return call("GET", ADMIN + "/feedback/" + path, 200, admin)

    room = event["location"].split(",", 1)[0].split("(", 1)[0].strip()
    assert room in get("roomlist")
    assert get("stats")["totalFeedbackReports"] >= 1
    assert any(r["id"] == report["id"] for r in get("reports"))
    path = "report/" + report["id"]
    for method, suffix in [("DELETE", "/mark"), ("POST", "/unmark")]:
        call("POST", ADMIN + "/feedback/" + path + "/mark", 201, admin)
        assert get(path)["adminFields"]["actionable"]
        call(method, ADMIN + "/feedback/" + path + suffix, 204, admin)
        assert not get(path)["adminFields"]["actionable"]


def account_create(call, username, code):
    created = call(
        "POST",
        "/api/v3/user/create",
        201,
        {"Content-Type": "application/json"},
        {
            "username": username,
            "password": "password",
            "verification": code,
            "agreeToTerms": True,
        },
    )
    assert created["username"] == username and created["recoveryKey"]
    return created


def accounts(call):
    headers = {"Content-Type": "application/json"}
    created = account_create(call, "e2ejoin", "GHI GHI")
    username = call(
        "POST",
        "/api/v3/auth/username",
        200,
        headers,
        {
            "registrationCode": "GHI GHI",
            "recoveryKey": "password",
        },
    )
    assert username["userID"] == created["userID"]
    changed = call(
        "POST",
        "/api/v3/auth/recovery",
        200,
        headers,
        {
            "username": "e2ejoin",
            "recoveryKey": "password",
            "newPassword": "e2eafterrecover",
        },
    )
    assert changed["userID"] == created["userID"] and changed["token"]

    name = "e2edeck"
    password = "e2eonboard"
    body = {
        "username": name,
        "password": password,
        "passwordConfirm": password,
        "regcode": "JKL JKL",
        "agreeToTerms": "true",
    }
    page = call("POST", "/createAccount", 200, headers, body)
    assert "Account Created. Welcome!" in page and "Your recovery key is:" in page
    found = json.loads(
        call(
            "POST",
            "/forgotUsername",
            200,
            headers,
            {
                "regCode": "JKL JKL",
                "recoveryKey": password,
            },
        )
    )
    assert found["username"] == name
    page = call(
        "POST", "/login", 200, headers, {"username": name, "password": password}
    )
    assert "Login Successful." in page
    page = call(
        "POST",
        "/recoverPassword",
        200,
        headers,
        {
            "username": name,
            "regCode": password,
            "password": "e2echanged",
            "passwordConfirm": "e2echanged",
        },
    )
    assert "Password Change Successful." in page
    page = call(
        "POST",
        "/resetPassword",
        200,
        {**headers, "Cookie": call.fixtures["e2ereset_cookie"]},
        {
            "currentPassword": "password",
            "password": "e2eboardgame",
            "confirmPassword": "e2eboardgame",
        },
    )
    assert "Change Password Successful." in page


def submitted_feedback_by_event_id(call):
    from workflows import login

    author_id, headers = login(call, "heidi")
    event = feedback_event(call, headers)
    draft = feedback_data(event, "The host answered every question.")
    call("POST", FEEDBACK, 201, headers, draft)

    report = call("GET", FEEDBACK + "/id/" + event["eventID"], 200, headers)
    assert report["id"]
    assert report["reportingUser"]["userID"] == author_id
    assert report["event"]["eventID"] == event["eventID"]
    assert report["recapString"] == draft["recapString"]


def monitoring(call):
    from workflows import login

    sam_id, _ = login(call, "sam")
    root = Path(__file__).resolve().parents[2]
    fixture = root / "Sources/swiftarr/seeds/test-registered-clients.txt"
    client, password, _ = next(
        row.split(":")
        for row in fixture.read_text().splitlines()
        if row.startswith("kraken:")
    )
    basic = base64.b64encode(f"{client}:{password}".encode()).decode()
    token = call(
        "POST", "/api/v3/auth/login", 200, {"Authorization": "Basic " + basic}
    )["token"]
    headers = {"Authorization": "Bearer " + token, "X-Swiftarr-User": sam_id}
    search = call("GET", "/api/v3/client/usersearch", 200, headers)
    assert any(u["userID"] == sam_id for u in search)
    changes = call("GET", "/api/v3/client/user/updates/since/0", 200, headers)
    assert any(u["userID"] == sam_id for u in changes)

    basic = base64.b64encode(b"prometheus:password").decode()
    service = {"Authorization": "Basic " + basic, "Content-Type": "application/json"}
    raw = call.raw("GET", "/api/v3/client/metrics", 200, service)
    metrics = raw.decode() if isinstance(raw, bytes) else raw
    assert "# TYPE" in metrics
    call(
        "POST",
        "/api/v3/client/alert",
        200,
        service,
        {
            "version": "4",
            "groupKey": "e2e",
            "truncatedAlerts": 0,
            "status": "resolved",
            "receiver": "swiftarr",
            "groupLabels": {},
            "commonLabels": {},
            "commonAnnotations": {},
            "externalURL": "http://localhost",
            "alerts": [],
        },
    )


def moderation(call):
    from workflows import login

    sam_id, sam = login(call, "sam")
    _, heidi = login(call, "heidi")
    admin_id, admin = login(call, "admin")
    mod = "/api/v3/mod"

    def get(path):
        return call("GET", mod + path, 200, admin)

    def review(path):
        call("POST", mod + path + "/setstate/reviewed", 200, admin)
        assert get(path)["moderationStatus"] == "modReviewed"

    queue = get("/reports")
    row = next(r for r in queue if r.get("submitterMessage") == "E2E queue item")
    fid = row["reportedID"]
    report = "/reports/" + row["id"]
    call("POST", mod + report + "/handleall", 200, admin)
    claimed = next(r for r in get("/reports") if r["id"] == row["id"])
    assert claimed["handledBy"]["userID"] == admin_id
    call("POST", mod + report + "/closeall", 200, admin)
    assert next(r for r in get("/reports") if r["id"] == row["id"])["isClosed"]

    forum = get("/forum/" + fid)
    assert forum["title"] == "E2E moderated thread"
    thread = call("GET", "/api/v3/forum/" + fid, 200, sam)
    first = str(thread["posts"][0]["postID"])
    call(
        "POST",
        "/api/v3/forum/post/" + first + "/report",
        201,
        heidi,
        {"message": "E2E reported post"},
    )
    review("/forumpost/" + first)
    review("/forum/" + fid)
    categories = call("GET", "/api/v3/forum/categories", 200, sam)
    new_category = next(
        c["categoryID"] for c in categories if c["title"] == "Activities"
    )
    call(
        "POST",
        mod + "/forum/" + fid + "/setcategory/" + new_category,
        200,
        admin,
    )
    assert get("/forum/" + fid)["categoryID"] == new_category

    fezzes = call("GET", "/api/v3/fez/owner?type=gaming", 200, sam)["fezzes"]
    game = next(f for f in fezzes if f["title"] == "E2E moderated game")
    gid = game["fezID"]
    chat = call("GET", "/api/v3/fez/" + gid, 200, sam)
    post_id = str(chat["members"]["posts"][0]["postID"])
    call(
        "POST",
        "/api/v3/fez/" + gid + "/report",
        201,
        heidi,
        {"message": "E2E reported meetup"},
    )
    call(
        "POST",
        "/api/v3/fez/post/" + post_id + "/report",
        201,
        heidi,
        {"message": "E2E reported chat post"},
    )
    review("/fez/" + gid)
    review("/fezpost/" + post_id)
    call(
        "POST",
        "/api/v3/users/" + sam_id + "/report",
        201,
        heidi,
        {"message": "E2E reported profile"},
    )
    review("/profile/" + sam_id)
    call("POST", mod + "/profile/" + sam_id + "/setstate/normal", 200, admin)
    assert get("/profile/" + sam_id)["moderationStatus"] == "normal"


def registration_desk(call):
    from workflows import login

    _, admin = login(call, "admin")
    code = ADMIN + "/regcodes"
    users = call("GET", code + "/find/fghfgh", 200, admin)
    assert [u["username"] for u in users] == ["e2edesk"]
    uid = users[0]["userID"]
    record = call("GET", code + "/findbyuser/" + uid, 200, admin)
    assert record["regCode"].lower().replace(" ", "") == "fghfgh"
    unlocked = call("POST", code + "/unlock/" + uid, 200, admin)
    assert unlocked["hasUsedRegCodeForPasswordRecovery"] is False
    invite = call("GET", code + "/discord/allocate/e2edesk", 200, admin)
    assert invite["isForDiscordUser"] and invite["discordUsername"] == "e2edesk"
    assert len(invite["regCode"].replace(" ", "")) == 6
    count = call("POST", ADMIN + "/authratelimits/clear", 200, admin)
    assert isinstance(count["clearedCount"], int)

    initial = call("GET", ADMIN + "/serversettings", 200, admin)
    settings = {
        "minUserAccessLevel": initial["minAccessUserLevel"],
        "enableFeatures": [],
        "disableFeatures": [],
    }
    for size in (initial["maxAlternateAccounts"] + 1, initial["maxAlternateAccounts"]):
        call(
            "POST",
            ADMIN + "/serversettings/update",
            200,
            admin,
            {**settings, "maxAlternateAccounts": size},
        )
        assert (
            call("GET", ADMIN + "/serversettings", 200, admin)["maxAlternateAccounts"]
            == size
        )


SCENARIOS = {
    "registration-desk": registration_desk,
    "moderation": moderation,
    "accounts": accounts,
    "monitoring": monitoring,
    "notices": notices,
    "staff": staff,
    "staff-roles": staff_roles,
    "support": support,
    "feedback": feedback,
    "submitted-feedback-by-event-id": submitted_feedback_by_event_id,
}

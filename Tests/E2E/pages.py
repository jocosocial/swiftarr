"""Exercise the member and staff website using signed-in fixture sessions."""

import base64
import csv
import json
from html import unescape
from io import StringIO
from pathlib import Path
from urllib.parse import quote


def seed(call, scenarios=()):
    from workflows import login

    _, sam = login(call, "sam")

    def get(path):
        return call("GET", "/api/v3/" + path, 200, sam)

    def create(path, payload, status=201):
        return call("POST", "/api/v3/" + path, status, sam, payload)

    user = get("users/find/heidi")["userID"]
    category = next(
        c["categoryID"] for c in get("forum/categories") if c["title"] == "General"
    )
    thread = next(
        t["forumID"]
        for t in get("forum/categories/" + category)["forumThreads"]
        if t["title"] == "E2E forum"
    )
    post = get("forum/" + thread)["posts"][0]["postID"]
    game = get("boardgames/?limit=1")["gameArray"][0]["gameID"]
    song = get("karaoke/?limit=1&search=ABBA")["songs"][0]["songID"]
    event = get("events?limit=1")[0]
    ids = {
        "user": user,
        "category": category,
        "forum": thread,
        "post": post,
        "game": game,
        "song": song,
        "event": event["eventID"],
        "uid": quote(event["uid"], safe=""),
    }
    for kind, key, title in [
        ("gaming", "lfg", "E2E game night"),
        ("open", "chat", "E2E meetup chat"),
    ]:
        created = create(
            "fez/create",
            {
                "fezType": kind,
                "title": title,
                "info": "Meet at the library.",
                "minCapacity": 0,
                "maxCapacity": 0,
                "initialUsers": [user],
                "startTime": event["startTime"],
                "endTime": event["endTime"],
                "location": "Library",
            },
        )
        assert created["title"] == title
        ids[key] = created["fezID"]
    message = create(
        "fez/" + ids["lfg"] + "/post",
        {
            "text": "Meet at the table.",
            "images": [],
            "postAsModerator": False,
            "postAsTwitarrTeam": False,
        },
        status=200,
    )
    ids["message"] = message["postID"]
    personal = create(
        "personalevents/create",
        {
            "title": "E2E library visit",
            "description": "Group visit",
            "startTime": event["startTime"],
            "endTime": event["endTime"],
            "location": "Library",
            "participants": [user],
        },
    )
    ids["personal"] = personal["personalEventID"]
    (item,) = create(
        "quartermaster/create",
        {
            "category": "have",
            "location": "Library",
            "hideOwnerName": False,
            "items": [
                {"itemName": "E2E spare dice", "itemDescription": "A spare set."}
            ],
        },
    )
    ids["item"] = item["itemID"]
    if "pages-records" in scenarios:
        ids.update(seed_records(call, event, sam))
    return ids


def seed_records(call, event, sam):
    from workflows import login

    admin_id, admin = login(call, "admin")

    def get(path):
        return call("GET", "/api/v3/" + path, 200, admin)

    def post(path, payload, status=201):
        return call("POST", "/api/v3/" + path, status, admin, payload)

    if not any(
        u["userID"] == admin_id for u in get("admin/userroles/shutternautmanager")
    ):
        post("admin/userroles/shutternautmanager/addrole/" + admin_id, None, status=200)
    image = Path(__file__).resolve().parents[1] / "AppTests/Fixtures/test_base.png"
    photo = call(
        "POST",
        "/api/v3/photostream/upload",
        200,
        sam,
        {
            "image": base64.b64encode(image.read_bytes()).decode(),
            "createdAt": event["startTime"],
        },
    )
    client = get("admin/clients")[0]["clientAppID"]
    shadow = get("events?type=shadow")[0]
    post(
        "admin/performer/upsert",
        {
            "name": "Library Players",
            "photo": {},
            "isOfficialPerformer": True,
            "yearsAttended": [],
            "eventUIDs": [],
            "bio": "Music at the library.",
        },
        status=200,
    )
    performer = next(
        p["id"]
        for p in get("performer/official")["performers"]
        if p["name"] == "Library Players"
    )
    post(
        "notification/announcement/create",
        {"text": "Game library is open.", "displayUntil": "2099-01-01T12:00:00Z"},
    )
    announcement = next(
        a["id"]
        for a in get("notification/announcements")
        if a["text"] == "Game library is open."
    )
    post(
        "admin/dailytheme/create",
        {"title": "Library day", "info": "Activities in the library.", "cruiseDay": 2},
    )
    theme = next(
        t["themeID"]
        for t in get("notification/dailythemes")
        if t["title"] == "Library day"
    )
    post(
        "hunts/create",
        {
            "title": "Library hunt",
            "description": "Find the library.",
            "puzzles": [
                {
                    "title": "Library shelf",
                    "body": "What holds the books?",
                    "answer": "SHELF",
                    "hints": {},
                }
            ],
        },
    )
    hunt = next(
        h["huntID"] for h in get("hunts/")["hunts"] if h["title"] == "Library hunt"
    )
    puzzle = get("hunts/" + hunt)["puzzles"][0]["puzzleID"]
    report = post(
        "communitysupport/report",
        {
            "memberName": "Fixture member",
            "reporterExperienced": True,
            "reporterWitnessed": False,
            "intent": "infoOnly",
            "mayContact": False,
            "experienceTime": "Afternoon",
            "experienceLocation": "Library",
            "experienceDescription": "Synthetic test report.",
        },
    )
    call(
        "POST",
        "/api/v3/feedback",
        201,
        sam,
        {
            "eventUID": shadow["uid"],
            "eventTitle": shadow["title"],
            "eventLocation": shadow["location"],
            "eventTime": shadow["startTime"],
            "hostName": "Fixture host",
            "attendance": "Two attendees",
            "recapString": "E2E scheduled event",
            "issuesString": "None.",
        },
    )
    feedback = next(
        r["id"]
        for r in get("admin/feedback/reports")
        if r["recapString"] == "E2E scheduled event"
    )
    return {
        "client": client,
        "photo": photo["postID"],
        "shadow": shadow["eventID"],
        "performer": performer,
        "announcement": announcement,
        "theme": theme,
        "hunt": hunt,
        "puzzle": puzzle,
        "report": report["id"],
        "feedback": feedback,
    }


MEMBER_PAGES = {
    "/quartermaster/report/{item}": "Report Item",
    "/quartermaster/{item}/edit": "Edit Quartermastarr Item",
    "/quartermaster/{item}": "Quartermastarr: E2E spare dice",
    "/privateevent/{personal}/update": "Update Private Event",
    "/privateevent/{personal}": "E2E library visit | Private Event",
    "/seamail/{chat}/edit": "Edit Seamail",
    "/seamail/{chat}": "E2E meetup chat | Seamail",
    "/lfg/post/report/{message}": "Report LFG Post",
    "/lfg/report/{lfg}": "Report LFG Content",
    "/lfg/{lfg}/members": "Update Looking For Group",
    "/lfg/{lfg}/update": "Update Looking For Group",
    "/lfg/{lfg}/edit": "Update Looking For Group",
    "/lfg/{lfg}": "E2E game night | LFG",
    "/": "Twitarr",
    "/about": "Frequently Asked Questions",
    "/notifications": "Notification Log",
    "/boardgames/guide": "Board Games List",
    "/events": "Events",
    "/eventfeedback": "Event Feedback",
    "/eventfeedback/form/submitted": "Feedback Submitted",
    "/events/{event}": "Events",
    "/eventfeedback/form/{uid}": "Event Feedback",
    "/forums": "Forum Categories",
    "/forums/{category}": "General | Forum Threads",
    "/forums/{category}/createForum": "Create New Forum",
    "/forum/{forum}": "E2E forum | Forum Thread",
    "/forum/{forum}/edit": "Edit Forum Thread",
    "/forum/report/{forum}": "Report Forum Title",
    "/forumpost/edit/{post}": "Edit Forum Post",
    "/forumpost/report/{post}": "Report Forum Post",
    "/forum/favorites": "Favorite Forums",
    "/forum/mutes": "Muted Forums",
    "/forum/owned": "Forums You Created",
    "/forum/recent": "Recently Viewed",
    "/forum/unread": "Unread Forums",
    "/forumpost/favorite": "Favorite Posts",
    "/forumpost/mentions": "Posts Mentioning You",
    "/forumpost/owned": "Your Forum Posts",
    "/forumpost/search": "Forum Post Search",
    "/lfg/": "LFG Find Groups",
    "/lfg/create": "New Looking For Group",
    "/lfg/faq": "LFG Help",
    "/lfg/former": "Former Groups",
    "/lfg/joined": "LFG Joined Groups",
    "/lfg/owned": "LFG Owned Groups",
    "/hunts": "Hunts",
    "/karaoke/?search=ABBA": "Latest Karaoke Songs",
    "/codeOfConduct": "Frequently Asked Questions",
    "/conductAgree": "Frequently Asked Questions",
    "/createAltAccount": "Create Alt Account",
    "/logout": "Logout",
    "/performers": "Performers",
    "/performers/shadow": "Performers",
    "/photostream": "Twitarr",
    "/dayplanner/": "Day Planner",
    "/dayplanner/subscribe": "Day Planner Subscribe",
    "/privateevent/create": "New Private Event",
    "/privateevent/list": "Private Events",
    "/quartermaster/": "Quartermastarr: Have",
    "/quartermaster/about": "Quartermastarr",
    "/quartermaster/create": "Add Quartermastarr Item(s)",
    "/quartermaster/need": "Quartermastarr: Need",
    "/quartermaster/owned": "Quartermastarr: Owned",
    "/seamail": "Seamail",
    "/seamail/create": "New Seamail",
    "/seamail/search": "Seamail",
    "/alertwords": "Manage Alertwords",
    "/blocks": "Manage Blocks and Mutes",
    "/directory": "User Directory",
    "/favorites": "Favorite Users",
    "/mutewords": "Manage Alertwords",
    "/profile": "sam | User Profile",
    "/profile/heidi": "heidi | User Profile",
    "/profile/edit": "Edit Profile",
    "/profile/report/{user}": "Report User Profile",
    "/profile/username/edit": "Edit Username",
    "/user/{user}": "heidi | User Profile",
    "/username/heidi": "heidi | User Profile",
    "/boardgames/{game}/expansions": "Board Games + Expansions",
    "/boardgames/{game}/createfez": "New LFG",
    "/forum/search?searchType=forums&search=E2E": "Forum Search",
}

STAFF_PAGES = {
    "/moderate/quartermaster/{item}": "Quartermastarr Item Moderation",
    "/moderate/personalevent/{personal}": "Personal Event Moderation",
    "/moderate/fezpost/{message}": "LFG Post Moderation",
    "/moderate/lfg/{lfg}": "LFG Moderation",
    "/admin/": "Server Admin",
    "/admin/announcements": "Announcements",
    "/admin/announcement/create": "Create Announcement",
    "/admin/boardgames": "Board Games Admin",
    "/admin/bulkuser": "Bulk Data Import/Export",
    "/admin/clients": "Client Apps",
    "/admin/clients/create": "Create Client App",
    "/admin/dailytheme/create": "Create New Daily Theme",
    "/admin/dailythemes": "Daily Tmemes",
    "/admin/dailythemes/schedule": "Load Daily Themes from Schedule",
    "/admin/hunts": "Hunts Admin",
    "/admin/karaoke": "Karaoke Admin",
    "/admin/mods": "Manage Moderator",
    "/admin/regcodes": "Registration Codes",
    "/admin/regcodes/showuser/{user}": "Registration Code for User",
    "/admin/rollup": "Server Counts",
    "/admin/schedule": "Upload Schedule",
    "/admin/scheduleupload/complete": "Schedule Update Complete",
    "/admin/serversettings": "Edit Server Settings",
    "/admin/tho": "Manage THO",
    "/admin/timezonechanges": "Time Zone Change Table",
    "/admin/twitarrteam": "Manage TwitarrTeam",
    "/admin/userroles": "User Roles",
    "/admin/userroles/shutternaut": "Shutternaut",
    "/communitysupport": "Community Support",
    "/communitysupport/log": "Community Support Log",
    "/communitysupport/newreport": "New Community Support Report",
    "/communitysupport/reports": "Community Support Reports",
    "/admin/eventfeedback": "Event Feedback Admin Page",
    "/admin/eventfeedback/reports": "Feedback Reports",
    "/admin/eventfeedback/reports/table": "Feedback Reports",
    "/admin/eventfeedback/roomposters": "Shadow Event Room Names",
    "/events/photographerreport": "Photographer Schedule Report",
    "/moderate/forum/{forum}": "Reports",
    "/moderate/forumpost/{post}": "Reports",
    "/moderate/user/{user}": "User Moderation",
    "/moderate/userprofile/{user}": "User Profile Moderation",
    "/moderate/microkaraoke": "Micro Karaoke Moderation",
    "/moderator": "Moderator Pages",
    "/moderator/guide": "Moderator Guide",
    "/moderator/log": "Moderator Action Log",
    "/reports": "Reports",
    "/reports/closed": "Closed Reports",
    "/admin/performer/add": "Add/Modify Official Performer Bio",
    "/admin/performer/bulk": "Bulk Add Performers",
    "/admin/performer/event/{event}": "Event Performers",
    "/admin/performer/link": "Link Performers To Events",
    "/admin/performer/manage": "Manage Performers",
    "/admin/performer/root": "Performers Admin Page",
    "/performer/shadow/self": "Add/Modify Event Organizer",
    "/dayplanner/shutternauts": "Day Planner",
    "/profile/edit/{user}": "Edit @heidi's Profile",
    "/profile/username/edit/{user}": "Edit @heidi's Username",
    "/karaoke/logperformance/{song}": "Latest Karaoke Songs",
}


def visit(call, role, paths):
    headers = {"Cookie": call.fixtures[role + "_cookie"]}
    for pattern, expected_title in paths.items():
        path = pattern.format_map(call.fixtures)
        page = call("GET", path, 200, headers)
        assert "<title>" + expected_title + "</title>" in unescape(page), path


def member_pages(call):
    visit(call, "sam", MEMBER_PAGES)
    headers = {"Cookie": call.fixtures["sam_cookie"]}
    event = call(
        "GET",
        "/events/{event}/calendarevent.ics".format_map(call.fixtures),
        200,
        headers,
    )
    assert "BEGIN:VEVENT" in event and "END:VCALENDAR" in event
    calendar = call(
        "GET",
        "/events/personal/{personal}/calendarevent.ics".format_map(call.fixtures),
        200,
        headers,
    )
    assert "BEGIN:VEVENT" in calendar and "SUMMARY:E2E library visit" in calendar
    card = call("GET", "/user/{user}/vcard".format_map(call.fixtures), 200, headers)
    assert "BEGIN:VCARD" in card and "NICKNAME:heidi" in card
    matches = json.loads(call("GET", "/seamail/usernames/search/heidi", 200, headers))
    assert any(
        u["userID"] == call.fixtures["user"] and u["username"] == "heidi"
        for u in matches
    )
    post = json.loads(
        call("GET", "/forumpost/{post}/details".format_map(call.fixtures), 200, headers)
    )
    assert (
        post["postID"] == call.fixtures["post"] and post["author"]["username"] == "sam"
    )


def staff_pages(call):
    visit(call, "admin", STAFF_PAGES)


def downloads(call):
    member = {"Cookie": call.fixtures["sam_cookie"]}
    for path in [
        "/events/subscribe/sam/following.ics",
        "/dayplanner/sam/jocoDayPlanner.ics",
    ]:
        calendar = call("GET", path, 200, member)
        assert calendar.startswith("BEGIN:VCALENDAR") and "END:VCALENDAR" in calendar
        assert "sam" in next(
            line for line in calendar.splitlines() if line.startswith("X-WR-CALNAME:")
        )
    images = []
    for size in ["full", "thumb"]:
        path = "/avatar/" + size + "/" + call.fixtures["user"]
        avatar = call.raw("GET", path, 200, member)
        assert avatar.startswith(b"\x89PNG\r\n\x1a\n") and b"IEND" in avatar
        images.append(avatar)
    assert images[0] == images[1]

    staff = {"Cookie": call.fixtures["admin_cookie"]}
    for role, path, title in [
        ("moderator", "/moderator/seamail", "Moderator Seamail"),
        ("communitysupport", "/communitysupport/seamail", "Community Support Seamail"),
    ]:
        body, headers = call.response("GET", path, (303, 200), staff)
        if "location" in headers:
            assert headers["location"] == "/seamail?foruser=" + role
        else:
            assert f"<title>{title}</title>".encode() in body
    for path, column in [
        ("/events/photographerreport/download", "Photographers"),
        ("/admin/eventfeedback/reports/download", "Event UID"),
        ("/communitysupport/reports/download", "Report ID"),
    ]:
        document = call("GET", path, 200, staff)
        columns = next(csv.reader(StringIO(document.removeprefix("\ufeff"))))
        assert column in columns, (path, columns)


def records(call):
    visit(
        call,
        "sam",
        {
            "/performer/{performer}": "Performer",
            "/photostream/report/{photo}": "Report Photostream Photo",
            "/hunt/{hunt}": "Library hunt | Hunt",
            "/puzzle/{puzzle}": "Library shelf | Puzzle",
            "/forum/containingpost/{post}": "E2E forum | Forum Thread",
        },
    )
    visit(
        call,
        "admin",
        {
            "/moderate/photostream/{photo}": "Photostream Photo Moderation",
            "/userrole/shutternaut/manage": "Shutternauts",
            "/admin/performer/bulk/complete": "Performer Import Complete",
            "/admin/regcodes/discord/assign": "Assign Registration Code To Discord User",
            "/admin/announcement/{announcement}/edit": "Edit Announcement",
            "/admin/dailytheme/{theme}/edit": "Edit Daily Theme",
            "/admin/clients/{client}/edit": "Edit Client App",
            "/admin/hunt/{hunt}/edit": "Library hunt | Hunt Admin",
            "/communitysupport/report/{report}": "Community Support Report",
            "/admin/eventfeedback/report/{feedback}": "Feedback Reports",
            "/performer/shadow/addtoevent/{shadow}": "Add/Modify Event Organizer",
        },
    )


SCENARIOS = {
    "pages-member": member_pages,
    "pages-staff": staff_pages,
    "pages-downloads": downloads,
    "pages-records": records,
}

"""End-to-end workflows shared by live runs and recorded-response verification."""

import base64


def login(call, name):
    basic = base64.b64encode(f"{name}:password".encode()).decode()
    user = call("POST", "/api/v3/auth/login", 200, {"Authorization": "Basic " + basic})
    assert user["userID"] and user["token"]
    return user["userID"], {
        "Authorization": "Bearer " + user["token"],
        "Content-Type": "application/json",
    }


def seamail(call):
    title = "E2E member conversation"
    _, sam = login(call, "sam")
    recipient_id, heidi = login(call, "heidi")
    created = call(
        "POST",
        "/api/v3/fez/create",
        201,
        sam,
        {
            "fezType": "closed",
            "title": title,
            "info": "Synthetic SeaMail",
            "minCapacity": 0,
            "maxCapacity": 0,
            "initialUsers": [recipient_id],
        },
    )
    assert (
        created["title"] == title
        and created["fezType"] == "closed"
        and created["owner"]["username"] == "sam"
    )
    assert {u["username"] for u in created["members"]["participants"]} == {
        "sam",
        "heidi",
    }
    thread = "/api/v3/fez/" + created["fezID"]

    def read():
        result = call("GET", thread, 200, heidi)
        assert result["fezID"] == created["fezID"] and result["title"] == title
        return result["members"]

    for index in range(2):
        content = "Synthetic SeaMail message " + str(index + 1)
        post = call(
            "POST",
            thread + "/post",
            200,
            sam,
            {
                "text": content,
                "images": [],
                "postAsModerator": False,
                "postAsTwitarrTeam": False,
            },
        )
        assert post["text"] == content and post["author"]["username"] == "sam"
        call("POST", thread + "/markRead", 201, heidi)
        call("POST", thread + "/markRead", 200, heidi)
        members = read()
        assert members["postCount"] == members["readCount"] == 1
        assert [
            (p["postID"], p["text"], p["author"]["username"]) for p in members["posts"]
        ] == [(post["postID"], content, "sam")]
        path = "/api/v3/fez/post/" + str(post["postID"])
        if index == 0:
            call("DELETE", path, 204, sam)
        else:
            call("POST", path + "/delete", 204, sam)
        members = read()
        assert (
            members["postCount"] == members["readCount"] == 0 and members["posts"] == []
        )
    for preference, key in [("favorite", "isFavorite"), ("mute", "isMuted")]:
        for alternate in [False, True]:
            call("POST", thread + "/" + preference, 201, heidi)
            assert read()[key] is True
            if alternate:
                call("POST", thread + "/" + preference + "/remove", 204, heidi)
            else:
                call("DELETE", thread + "/" + preference, 204, heidi)
            assert not read().get(key)


def forum(call):
    _, sam = login(call, "sam")
    _, heidi = login(call, "heidi")
    categories = call("GET", "/api/v3/forum/categories", 200, sam)
    general = next(c for c in categories if c["title"] == "General")
    category = "/api/v3/forum/categories/" + general["categoryID"]
    threads = call("GET", category, 200, sam)
    assert threads["title"] == "General"
    thread = next(t for t in threads["forumThreads"] if t["title"] == "E2E forum")
    path = "/api/v3/forum/" + thread["forumID"]

    def read():
        data = call("GET", path, 200, heidi)
        assert data["title"] == "E2E forum" and data["creator"]["username"] == "sam"
        return data

    first_post = read()["posts"][0]
    assert first_post["text"] == "E2E first post"
    post = "/api/v3/forum/post/" + str(first_post["postID"])
    assert call("GET", post, 200, heidi)["text"] == "E2E first post"
    assert call("GET", post + "/forum", 200, heidi)["forumID"] == thread["forumID"]
    assert call("GET", path + "/pinnedposts", 200, heidi) == []
    assert any(
        t["forumID"] == thread["forumID"]
        for t in call("GET", "/api/v3/forum/owner", 200, sam)["forumThreads"]
    )

    for reaction in ["like", "love", "laugh"]:
        assert call("POST", post + "/" + reaction, 200, heidi)["userLike"] == reaction
        assert call("DELETE", post + "/" + reaction, 200, heidi).get("userLike") is None
    assert call("POST", post + "/like", 200, heidi)["userLike"] == "like"
    assert call("POST", post + "/unreact", 200, heidi).get("userLike") is None
    for noun, key in [("favorite", "isFavorite"), ("mute", "isMuted")]:
        for method, suffix in [("DELETE", ""), ("POST", "/remove")]:
            call("POST", path + "/" + noun, 201, heidi)
            assert read()[key] is True
            call(method, path + "/" + noun + suffix, 204, heidi)
            assert read()[key] is False
    for method, suffix in [("DELETE", ""), ("POST", "/remove")]:
        call("POST", post + "/bookmark", 201, heidi)
        assert read()["posts"][0]["isBookmarked"]
        call(method, post + "/bookmark" + suffix, 204, heidi)
        assert not read()["posts"][0]["isBookmarked"]
    for method, suffix in [("DELETE", ""), ("POST", "/delete")]:
        text = "E2E reply from Heidi"
        reply = call(
            "POST",
            path + "/create",
            201,
            heidi,
            {
                "text": text,
                "images": [],
                "postAsModerator": False,
                "postAsTwitarrTeam": False,
            },
        )
        post_id = reply["postID"]
        assert any(
            p["postID"] == post_id and p["text"] == text
            for p in call("GET", path, 200, sam)["posts"]
        )
        call(method, "/api/v3/forum/post/" + str(post_id) + suffix, 204, heidi)
        assert all(p["postID"] != post_id for p in call("GET", path, 200, sam)["posts"])


def directory(call):
    _, headers = login(call, "sam")
    members = call("GET", "/api/v3/users/match/allnames/heidi", 200, headers)
    member = next(u for u in members if u["username"] == "heidi")
    path = "/api/v3/users/" + member["userID"]
    assert call("GET", path, 200, headers)["username"] == "heidi"
    assert call("GET", path + "/profile", 200, headers)["header"]["username"] == "heidi"
    for word_list in ["alertwords", "mutewords"]:
        path = "/api/v3/user/" + word_list
        word = "fixtureword"
        assert word not in call("GET", path, 200, headers)["keywords"]
        assert word in call("POST", path + "/add/" + word, 200, headers)["keywords"]
        assert word in call("GET", path, 200, headers)["keywords"]
        assert (
            word not in call("POST", path + "/remove/" + word, 200, headers)["keywords"]
        )


def catalogs(call):
    _, headers = login(call, "sam")

    def current(detail, id_field, expected_id):
        data = call("GET", detail, 200, headers)
        assert data[id_field] == expected_id
        return data["isFavorite"]

    for base, items, id_field in [
        ("boardgames", "gameArray", "gameID"),
        ("karaoke", "songs", "songID"),
    ]:
        path = "/api/v3/" + base + "/"
        query = "?limit=1&search=ABBA" if base == "karaoke" else "?limit=1"
        listing = call("GET", path + query, 200, headers)[items]
        assert len(listing) == 1
        item = listing[0]
        detail = path + item[id_field]

        assert not current(detail, id_field, item[id_field])
        for method, suffix in [("DELETE", ""), ("POST", "/remove")]:
            call("POST", detail + "/favorite", 201, headers)
            assert current(detail, id_field, item[id_field])
            call(method, detail + "/favorite" + suffix, 204, headers)
            assert not current(detail, id_field, item[id_field])


def site(call):
    for path, title in [
        ("/login", "Login"),
        ("/map", "Ship Map"),
        ("/forgotUsername", "Forgot Username"),
        ("/resetPassword", "Reset Password"),
        ("/createAccount", "Create Account"),
        ("/clients/", "Client Apps"),
        ("/clients/faq", "Client Apps FAQ"),
        ("/boardgames?limit=1", "Board Games List"),
        ("/time", "Time Zone Check"),
        ("/faq", "Frequently Asked Questions"),
    ]:
        assert "<title>" + title + "</title>" in call("GET", path, 200, {})


SCENARIOS = {
    "seamail": seamail,
    "forum": forum,
    "directory": directory,
    "catalogs": catalogs,
    "site": site,
}

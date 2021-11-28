from locust import HttpUser, task, between
from locust import events
import random

class LoggedOutUser(HttpUser):
	wait_time = between(1, 5)

	def on_start(self):
		self.client.post("/login", json={"username":"sam", "password":"password"})

	@task
	def rootPage(self):
		self.client.get("/")

	@task
	def eventsPage(self):
		self.client.get("/events")

	@task
	def boardgamePage(self):
		self.client.get("/boardgames")

	@task
	def boardgamePage(self):
		self.client.get("/karaoke")

class TwarrtAPIUser(HttpUser):
	wait_time = between(1, 5)
	samAuth = { "Authorization": "Bearer " }
	heidiAuth = { "Authorization": "Bearer " }
	jamesAuth = { "Authorization": "Bearer " }
	existingTwarrts = []
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth=('sam', 'password'))
		self.samAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		authResponse = self.client.post("/api/v3/auth/login", auth=('heidi', 'password'))
		self.heidiAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		twarrtResponse = self.client.get("/api/v3/twitarr", headers = self.samAuth)
		self.existingTwarrts = [ twarrt["twarrtID"] for twarrt in twarrtResponse.json() ]
		
	@task
	def twarrts(self):
		self.client.get("/api/v3/twitarr", headers = self.samAuth)

	@task
	def twarrtDetail(self):
		self.client.get("/api/v3/twitarr/" + str(random.choice(self.existingTwarrts)), headers = self.samAuth, name="/api/v3/twitarr/:id")
		
	@task
	def newTwarrt(self):
		response = self.client.post("/api/v3/twitarr/create", json={ "text": "This is a Locust post.", "images": [] }, headers = self.samAuth)
		maxTwarrt = response.json()["twarrtID"]
		self.client.post("/api/v3/twitarr/" + str(maxTwarrt) + "/love", headers = self.heidiAuth, name="/api/v3/twitarr/:id/love")
		self.client.post("/api/v3/twitarr/" + str(maxTwarrt) + "/like", headers = self.heidiAuth, name="/api/v3/twitarr/:id/like")
		self.client.post("/api/v3/twitarr/" + str(maxTwarrt) + "/love", headers = self.jamesAuth, name="/api/v3/twitarr/:id/love")
		self.client.post("/api/v3/twitarr/" + str(maxTwarrt) + "/unreact", headers = self.jamesAuth, name="/api/v3/twitarr/:id/unreact")
		self.client.post("/api/v3/twitarr/" + str(maxTwarrt) + "/bookmark", headers = self.jamesAuth, name="/api/v3/twitarr/:id/bookmark")
		self.client.post("/api/v3/twitarr/" + str(maxTwarrt) + "/bookmark/remove", headers = self.jamesAuth, name="/api/v3/twitarr/:id/bookmark/remove")
		response = self.client.post("/api/v3/twitarr/" + str(maxTwarrt) + "/update", json={ "text": "Editing the text of this twarrt.", "images": [] }, headers = self.samAuth, name="/api/v3/twitarr/:id/update")

	@task
	def createDeleteTwarrt(self):
		response = self.client.post("/api/v3/twitarr/create", json={ "text": "This is a Locust post that will get deleted", "images": [] }, headers = self.samAuth)
		newTwarrtID = response.json()["twarrtID"]
		self.client.delete("/api/v3/twitarr/" + str(newTwarrtID), headers = self.samAuth, name="/api/v3/twitarr/:id")

	@task
	def replyToTwarrt(self):
		response = self.client.post("/api/v3/twitarr/" + str(random.choice(self.existingTwarrts)) + "/reply", json={ "text": "This is a Locust reply.", "images": [] }, headers = self.heidiAuth, name="/api/v3/twitarr/:id/reply")
		newTwarrtID = response.json()["twarrtID"]

	@task
	def reportTwarrt(self):
		response = self.client.post("/api/v3/twitarr/create", json={ "text": "This is a Locust post that will get reported.", "images": [] }, headers = self.samAuth)
		reportTwarrt = response.json()["twarrtID"]
		response = self.client.post("/api/v3/twitarr/" + str(reportTwarrt) + "/report", json={ "message": "This is a Locust twarrt report." }, headers = self.heidiAuth, name="/api/v3/twitarr/:id/report")

class TwarrtUser(HttpUser):
	wait_time = between(1, 5)
	samAuth = { "Authorization": "Bearer " }
	existingTwarrts = []

	def on_start(self):
		self.client.post("/login", json={"username":"sam", "password":"password"})
		authResponse = self.client.post("/api/v3/auth/login", auth=('sam', 'password'))
		self.samAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		twarrtResponse = self.client.get("/api/v3/twitarr", headers = self.samAuth)
		self.existingTwarrts = [ twarrt["twarrtID"] for twarrt in twarrtResponse.json() ]

	@task
	def root(self):
		self.client.get("/tweets")

	@task
	def detail(self):
		tweetToDetail = str(random.choice(self.existingTwarrts))
		self.client.get("/tweets/" + tweetToDetail, name="/tweets/:id")
		response = self.client.get("/api/v3/twitarr/" + tweetToDetail, headers = self.samAuth, name="/api/v3/twitarr/:id")
		author = response.json()["author"]["username"]
		if author != "sam":
			self.client.post("/tweets/" + tweetToDetail + "/like", name="/tweets/:id/like")
			self.client.post("/tweets/" + tweetToDetail + "/unreact", name="/tweets/:id/unreact")
			

	@task
	def mentionSelf(self):
		self.client.get("/tweets?mentionSelf=true")

	@task
	def replyGroup(self):
		self.client.get("/tweets?replyGroup=" + str(random.choice(self.existingTwarrts)), name="/tweets?replyGroup=:id")

	@task
	def editTweet(self):
		self.client.get("/tweets/edit/" + str(random.choice(self.existingTwarrts)), name="/tweets/edit/:id")

	@task
	def bookmarkTweet(self):
		tweetToBookmark = str(random.choice(self.existingTwarrts))
		self.client.post("/tweets/" + tweetToBookmark + "/bookmark", name="/tweets/:id/bookmark")
		self.client.delete("/tweets/" + tweetToBookmark + "/bookmark", name="/tweets/:id/bookmark")

	@task
	def createEditDeleteTweet(self):
		self.client.post("/tweets/" + "/create", json={ "postText": "A Locust webclient post." }, name="/tweets/create")
		response = self.client.post("/api/v3/twitarr/create", json={ "text": "This is a Locust api post that will be deleted.", "images": [] }, headers = self.samAuth)
		newTwarrtID = str(response.json()["twarrtID"])
		self.client.post("/tweets/edit/" + newTwarrtID, json={ "postText": "A Locust webclient post edit." }, name="/tweets/edit/:id")
		self.client.post("/tweets/reply/" + newTwarrtID, json={ "postText": "A Locust webclient post reply." }, name="/tweets/reply/:id")
		self.client.post("/tweets/" + newTwarrtID + "/delete", name="/tweets/:id/delete")
		
		
		
class ForumAPIUser(HttpUser):
	wait_time = between(1, 5)
	samAuth = { "Authorization": "Bearer " }
	heidiAuth = { "Authorization": "Bearer " }
	jamesAuth = { "Authorization": "Bearer " }
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth=('sam', 'password'))
		self.samAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		authResponse = self.client.post("/api/v3/auth/login", auth=('heidi', 'password'))
		self.heidiAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }

	@task
	def readForum(self):
		catResponse = self.client.get("/api/v3/forum/categories", headers = self.samAuth)
		egypeCat = next(catData["categoryID"] for catData in catResponse.json() if catData["title"] == "Egype")
		forumsResponse = self.client.get("/api/v3/forum/categories/" + egypeCat, headers = self.samAuth, 
				name="/api/v3/forum/categories/:cat_id")
		firstForum = forumsResponse.json()["forumThreads"][0]["forumID"]
		forumResponse = self.client.get("/api/v3/forum/" + firstForum, headers = self.samAuth, name="/api/v3/forum/:forum_id")
		posts = [ post["postID"] for post in forumResponse.json()["posts"] if post["author"]["username"] != "sam" ]
		randPost = str(random.choice(posts))
		self.client.post("/api/v3/forum/post/" + randPost + "/like", headers = self.samAuth, name="/api/v3/forum/post/:post_id/like")
		self.client.post("/api/v3/forum/post/" + randPost + "/unreact", headers = self.samAuth, name="/api/v3/forum/post/:post_id/unreact")
		self.client.post("/api/v3/forum/post/" + randPost + "/bookmark", headers = self.samAuth, name="/api/v3/forum/post/:post_id/bookmark")
		self.client.post("/api/v3/forum/post/" + randPost + "/bookmark/remove", headers = self.samAuth, name="/api/v3/forum/post/:post_id/bookmark/remove")

	@task
	def searchForums(self):
		self.client.get("/api/v3/forum/match/hello", headers = self.samAuth, name="/api/v3/forum/match/:string")

	@task
	def searchPosts(self):
		self.client.get("/api/v3/forum/post/search?search=hello", headers = self.samAuth, name="/api/v3/forum/post/search")

	@task
	def ownForums(self):
		self.client.get("/api/v3/forum/owner", headers = self.samAuth, name="/api/v3/forum/owner")

	@task
	def createForum(self):
		# get categories, find "Lower Decks"
		catResponse = self.client.get("/api/v3/forum/categories", headers = self.samAuth)
		lowerCat = next(catData["categoryID"] for catData in catResponse.json() if catData["title"] == "Lower Decks")
		# Create forum in "Lower Decks" category
		createResponse = self.client.post("/api/v3/forum/categories/" + lowerCat + "/create", 
				json={ "title": "A Locust Forum", "firstPost":{"text": "hello this is my locust post", "images": [] }}, 
				headers = self.samAuth, name="/api/v3/forum/categories/:cat_id/create")
		newForumID = createResponse.json()["forumID"]
		# Add a post to the new forum
		self.client.post("/api/v3/forum/" + newForumID + "/create", headers = self.samAuth, 
				json={"text": "This is a reply in the Locust forum", "images": [] }, name="/api/v3/forum/:forum_id/create")
		# Add another post
		postResponse = self.client.post("/api/v3/forum/" + newForumID + "/create", headers = self.samAuth, 
				json={"text": "This is a post we're going to delete.", "images": [] }, name="/api/v3/forum/:forum_id/create")
		postToDeleteID = str(postResponse.json()["postID"])
		# Get details on the post
		self.client.get("/api/v3/forum/post/" + postToDeleteID, headers = self.samAuth, name="/api/v3/forum/post/:post_id")
		# Delete the post
		self.client.post("/api/v3/forum/post/" + postToDeleteID + "/delete", headers = self.samAuth, 
				name="/api/v3/forum/post/:post_id/delete")
# mods only		self.client.post("/api/v3/forum/" + newForumID + "/delete", headers = self.samAuth, name="/api/v3/forum/:forum_id/delete")
		
	@task
	def createRenameForum(self):
		catResponse = self.client.get("/api/v3/forum/categories", headers = self.samAuth)
		lowerCat = next(catData["categoryID"] for catData in catResponse.json() if catData["title"] == "Lower Decks")
		createResponse = self.client.post("/api/v3/forum/categories/" + lowerCat + "/create", 
				json={ "title": "A Locust Forum To Rename", "firstPost":{"text": "hello this is my locust post", "images": [] }},
				headers = self.samAuth, name="/api/v3/forum/categories/:cat_id/create")
		newForumID = createResponse.json()["forumID"]
		postResponse = self.client.post("/api/v3/forum/" + newForumID + "/create", headers = self.samAuth, 
				json={"text": "This is a reply in the Locust forum", "images": [] }, name="/api/v3/forum/:forum_id/create")
		postID = str(postResponse.json()["postID"])
		self.client.post("/api/v3/forum/post/" + postID + "/update", headers = self.samAuth, 
				json={"text": "This is a post we've updated.", "images": [] }, name="/api/v3/forum/post/:post_id/update")
		self.client.post("/api/v3/forum/" + newForumID + "/rename/A%20Locust%20Forum%20We%20Renamed", 
				headers = self.samAuth, name="/api/v3/forum/:forum_id/rename/:new_name")

	@task
	def favoriteForum(self):
		catResponse = self.client.get("/api/v3/forum/categories", headers = self.samAuth)
		lowerCat = next(catData["categoryID"] for catData in catResponse.json() if catData["title"] == "Lower Decks")
		forumsResponse = self.client.get("/api/v3/forum/categories/" + lowerCat, headers = self.samAuth, 
				name="/api/v3/forum/categories/:cat_id")
		if len(forumsResponse.json()["forumThreads"]) > 0:
			firstForum = forumsResponse.json()["forumThreads"][0]["forumID"]
			self.client.post("/api/v3/forum/" + firstForum + "/favorite",  headers = self.samAuth, name="/api/v3/forum/:forum_id/favorite")
			self.client.delete("/api/v3/forum/" + firstForum + "/favorite",  headers = self.samAuth, name="/api/v3/forum/:forum_id/favorite")

class ForumWebUser(HttpUser):
	wait_time = between(1, 5)
	jamesAuth = { "Authorization": "Bearer " }
	eventsCategory = ""
	forumIDs = ""
	
	def on_start(self):
		# log james in, both with the log in page POST and via the API (so we can get object IDs for further calls)
		self.client.post("/login", json={"username":"james", "password":"password"})
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		# get some initial data - Events category, and some forum thread IDs 
		catResponse = self.client.get("/api/v3/forum/categories", headers = self.jamesAuth)
		self.eventsCategory = next(catData["categoryID"] for catData in catResponse.json() if catData["title"] == "Event Forums")
		forumsResponse = self.client.get("/api/v3/forum/categories/" + self.eventsCategory, headers = self.jamesAuth,
				name="/api/v3/forum/categories/:cat_id")
		self.forumIDs = [ thread["forumID"] for thread in forumsResponse.json()["forumThreads"] ]

	@task
	def viewCategories(self):
		self.client.get("/forums")

	@task
	def viewEventsForums(self):
		self.client.get("/forums/" + self.eventsCategory, name="/forums/:category_id")

	@task
	def viewEventsForumThread(self):
		randomEvent = random.choice(self.forumIDs)
		self.client.get("/forum/" + randomEvent, name="/forum/:forum_id")

	@task
	def searchForums(self):
		self.client.get("/forum/search?search=locust&searchType=forums", name="/forum/search")

	@task
	def searchForumPosts(self):
		self.client.get("/forum/search?search=locust&searchType=posts", name="/forum/search")

	@task
	def showFavorites(self):
		self.client.get("/forum/favorites")

	@task
	def showOwnForums(self):
		self.client.get("/forum/owned")

	@task
	def showMentions(self):
		self.client.get("/forumpost/mentions")

	@task
	def showFavoritePosts(self):
		self.client.get("/forumpost/favorite")

	@task
	def showOwnPosts(self):
		self.client.get("/forumpost/owned")

	@task
	def alsoSearchForumPosts(self):
		# There's 2 different ways to get to search posts in the UI, with different <form>s.
		self.client.get("/forumpost/search?search=hello", name="/forumpost/search")

class SeamailAPIUser(HttpUser):
	wait_time = between(1, 5)
	samAuth = { "Authorization": "Bearer " }
	samID = ""
	heidiAuth = { "Authorization": "Bearer " }
	heidiID = ""
	jamesAuth = { "Authorization": "Bearer " }
	jamesID = ""
	fezID = ""
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth=('sam', 'password'))
		self.samAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.samID = authResponse.json()["userID"]
		authResponse = self.client.post("/api/v3/auth/login", auth=('heidi', 'password'))
		self.heidiAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.heidiID = authResponse.json()["userID"]
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.jamesID = authResponse.json()["userID"]
		createResponse = self.client.post("/api/v3/fez/create", headers = self.heidiAuth, 
				json={ "fezType": "closed", "title": "Hey Everyone", "info": "what", "minCapacity": 0, "maxCapacity": 0, "initialUsers": [ self.samID, self.jamesID ] })
		self.fezID = createResponse.json()["fezID"]

	@task
	def joinedSeamails(self):
		self.client.get("/api/v3/fez/joined?type=private", headers = self.heidiAuth)

	@task
	def ownedSeamails(self):
		self.client.get("/api/v3/fez/owner?type=private", headers = self.heidiAuth)

	@task
	def createSeamail(self):
		createResponse = self.client.post("/api/v3/fez/create", headers = self.heidiAuth, 
				json={ "fezType": "closed", "title": "Hey Everyone", "info": "what", "minCapacity": 0, "maxCapacity": 0, "initialUsers": [ self.samID, self.jamesID ] })
		newFezID = createResponse.json()["fezID"]
		self.client.get("/api/v3/fez/" + newFezID, headers = self.samAuth, name="/api/v3/fez/:fez_ID")
		self.client.get("/api/v3/fez/" + newFezID, headers = self.jamesAuth, name="/api/v3/fez/:fez_ID")

	@task
	def postAndDeleteMsg(self):
		response = self.client.post("/api/v3/fez/" + self.fezID + "/post", json={ "text": "This is a Locust Seamail Post.", "images": [] }, 
				headers = self.heidiAuth, name = "/api/v3/fez/:fez_id/post")
		postID = str(response.json()["postID"])
		self.client.delete("/api/v3/fez/post/" + postID, headers = self.heidiAuth, name = "/api/v3/fez/post/:postID")

class SeamailWebUser(HttpUser):
	wait_time = between(1, 5)
	jamesAuth = { "Authorization": "Bearer " }
	jamesID = ""
	heidiAuth = { "Authorization": "Bearer " }
	heidiID = ""
	
	def on_start(self):
		# log james in, both with the log in page POST and via the API (so we can get object IDs for further calls)
		self.client.post("/login", json={"username":"james", "password":"password"})
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.jamesID = authResponse.json()["userID"]
		authResponse = self.client.post("/api/v3/auth/login", auth=('heidi', 'password'))
		self.heidiAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.heidiID = authResponse.json()["userID"]

	@task
	def viewSeamailRoot(self):
		self.client.get("/seamail")

	@task
	def viewSeamailCreate(self):
		self.client.get("/seamail/create")

	@task
	def seamailUsernameSearch(self):
		self.client.get("/seamail/usernames/search/adm", name="/seamail/usernames/search/:search_string")

	@task
	def seamailCreate(self):
		self.client.post("/seamail/create", json={"subject": "What about Locust?", "postText": "A post, full of text", "participants": self.heidiID} )

	@task
	def seamailCreateAndView(self):
		createResponse = self.client.post("/api/v3/fez/create", headers = self.jamesAuth, 
				json={ "fezType": "closed", "title": "Talking to Sam", "info": "", "minCapacity": 0, "maxCapacity": 0, "initialUsers": [ self.heidiID ] })
		newFezID = createResponse.json()["fezID"]
		self.client.get("/seamail/" + newFezID, name="/seamail/:seamail_id")

class EventsAPIUser(HttpUser):
	wait_time = between(1, 5)
	jamesAuth = { "Authorization": "Bearer " }
	jamesID = ""
	heidiAuth = { "Authorization": "Bearer " }
	heidiID = ""
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.jamesID = authResponse.json()["userID"]
		authResponse = self.client.post("/api/v3/auth/login", auth=('heidi', 'password'))
		self.heidiAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.heidiID = authResponse.json()["userID"]

	@task
	def getEvents(self):
		eventResponse = self.client.get("/api/v3/events", headers = self.heidiAuth)
		eventIDs = [ event["eventID"] for event in eventResponse.json() ]
		self.client.get("/api/v3/events/" + random.choice(eventIDs), headers = self.heidiAuth, name="/api/v3/events/:event_id")
		favEvent = random.choice(eventIDs)
		self.client.post("/api/v3/events/" + favEvent + "/favorite", headers = self.heidiAuth, name="/api/v3/events/:event_id/favorite")
		self.client.delete("/api/v3/events/" + favEvent + "/favorite", headers = self.heidiAuth, name="/api/v3/events/:event_id/favorite")

	@task
	def searchEvents(self):
		eventResponse = self.client.get("/api/v3/events?search=cruise", headers = self.heidiAuth)

	@task
	def getFavoriteEvents(self):
		self.client.get("/api/v3/events/favorites", headers = self.heidiAuth)

class EventsWebUser(HttpUser):
	wait_time = between(1, 5)
	jamesAuth = { "Authorization": "Bearer " }
	jamesID = ""
	
	def on_start(self):
		self.client.post("/login", json={"username":"heidi", "password":"password"})
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.jamesID = authResponse.json()["userID"]

	@task
	def viewEvents(self):
		self.client.get("/events")

	@task
	def searchEvents(self):
		self.client.get("/events?search=cruise")

class BoardgamesAPIUser(HttpUser):
	wait_time = between(1, 5)
	jamesAuth = { "Authorization": "Bearer " }
	jamesID = ""
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth=('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.jamesID = authResponse.json()["userID"]

	@task
	def getBoardgames(self):
		boardgameResponse = self.client.get("/api/v3/boardgames", headers = self.jamesAuth)
		boardgameIDs = [ game["gameID"] for game in boardgameResponse.json()["gameArray"] ]
		self.client.get("/api/v3/boardgames/" + random.choice(boardgameIDs), headers = self.jamesAuth, name="/api/v3/boardgames/:game_id")
		self.client.get("/api/v3/boardgames/expansions/" + random.choice(boardgameIDs), 
				headers = self.jamesAuth, name="/api/v3/boardgames/expansions/:game_id")
		favGame = random.choice(boardgameIDs)
		self.client.post("/api/v3/boardgames/" + favGame + "/favorite", headers = self.jamesAuth, name="/api/v3/boardgames/:event_id/favorite")
		self.client.delete("/api/v3/boardgames/" + favGame + "/favorite", headers = self.jamesAuth, name="/api/v3/boardgames/:event_id/favorite")

	@task
	def searchBoardgames(self):
		eventResponse = self.client.get("/api/v3/boardgames?search=catan", headers = self.jamesAuth)

	@task
	def getFavoriteBoardgames(self):
		self.client.get("/api/v3/boardgames?favorite=true", headers = self.jamesAuth)

class BoardgamesWebUser(HttpUser):
	wait_time = between(1, 5)
	heidiAuth = { "Authorization": "Bearer " }
	
	def on_start(self):
		self.client.post("/login", json={"username":"heidi", "password":"password"})
		authResponse = self.client.post("/api/v3/auth/login", auth=('heidi', 'password'))
		self.heidiAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }

	@task
	def viewBoardgames(self):
		self.client.get("/boardgames")

	@task
	def searchGames(self):
		self.client.get("/boardgames?search=star")

	@task
	def viewMakeGameFezPage(self):
		boardgameResponse = self.client.get("/api/v3/boardgames", headers = self.heidiAuth)
		boardgameIDs = [ game["gameID"] for game in boardgameResponse.json()["gameArray"] ]
		fezGame = random.choice(boardgameIDs)
		self.client.get("/boardgames/" + fezGame + "/createfez", name="/boardgames/:game_id/createFez")
		
class KaraokeAPIUser(HttpUser):
	wait_time = between(1, 5)
	heidiAuth = { "Authorization": "Bearer " }
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth=('heidi', 'password'))
		self.heidiAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }

	@task
	def getSongs(self):
		self.client.get("/api/v3/karaoke?search=radiohead")

	@task
	def getLatest(self):
		self.client.get("/api/v3/karaoke/latest")

	@task
	def getFavoriteSongs(self):
		self.client.get("/api/v3/karaoke?favorite=true", headers = self.heidiAuth)

class KaraokeWebUser(HttpUser):
	wait_time = between(1, 5)
	
	@task
	def viewSongsRootPage(self):
		self.client.get("/karaoke")

	@task
	def viewSongSearch(self):
		self.client.get("/karaoke?search=prince")

class AlertAPIUser(HttpUser):
	wait_time = between(1, 5)
	jamesAuth = { "Authorization": "Bearer " }
	jamesID = ""
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth = ('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.jamesID = authResponse.json()["userID"]

	@task
	def getNotifications(self):
		self.client.get("/api/v3/notification/global", headers = self.jamesAuth)

	@task
	def getAnnouncements(self):
		self.client.get("/api/v3/notification/announcements", headers = self.jamesAuth)

	@task
	def getDailyThemes(self):
		self.client.get("/api/v3/notification/dailythemes", headers = self.jamesAuth)

class ProfileAPIUser(HttpUser):
	wait_time = between(1, 5)
	jamesAuth = { "Authorization": "Bearer " }
	jamesID = ""
	
	def on_start(self):
		authResponse = self.client.post("/api/v3/auth/login", auth = ('james', 'password'))
		self.jamesAuth = { "Authorization": "Bearer " + authResponse.json()["token"] }
		self.jamesID = authResponse.json()["userID"]

	@task
	def getProfile(self):
		self.client.get("/api/v3/user/profile", headers = self.jamesAuth)

	@task
	def whoami(self):
		self.client.get("/api/v3/user/whoami", headers = self.jamesAuth)
		
	@task
	def findUser(self):
		self.client.get("/api/v3/users/find/heidi", headers = self.jamesAuth, name="/api/v3/users/:username")

	@task
	def getHeader(self):
		self.client.get("/api/v3/users/" + self.jamesID, headers = self.jamesAuth, name="/api/v3/users/:user_ID")

	@task
	def userSearch(self):
		self.client.get("/api/v3/users/match/allnames/admin", headers = self.jamesAuth, name="/api/v3/users/match/allnames/:search_str")

# AuthUser, to login/logout, maybe create accts?
# ClientUser
# FezUser
# ImageUser; uploads/downloads images
# UserUser; modifies profile, sets alertwords/blocks/mutes/mutewords

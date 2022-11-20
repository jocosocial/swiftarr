import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis

// Decoding struct for the URL Query Options that twarrtsHandler() can decode.
public struct TwarrtQueryOptions: Content {
	var search: String?
	var hashtag: String?
	var mentions: String?
	var mentionSelf: Bool?
	var byUser: UUID?
	var byUsername: String?
	var bookmarked: Bool?
	var inBarrel: UUID?
	var replyGroup: Int?
	var hideReplies: Bool?
	var likeType: String?
	var after: Int?
	var before: Int?
	var afterDate: String?
	var beforeDate: String?
	var from: String?
	var start: Int?
	var limit: Int?
	
	// This is a somewhat low-rent way to allow both camelCase and lowercased query options in the url query.
	// Only works for optional values, and doesn't implement full case-insensitivity.
	// As of Swift 5.5, there's a keyDecodingStrategy that does what we want, but it's JSONDecoder only.
	private var mentionself: Bool?
	private var byuser: UUID?
	private var byusername: String?
	private var inbarrel: UUID?
	private var replygroup: Int?
	private var hidereplies: Bool?
	private var liketype: String?
	private var afterdate: String?
	private var beforedate: String?

	public mutating func afterDecode() throws {
		mentionSelf = mentionSelf ?? mentionself
		afterDate = afterDate ?? afterdate
		beforeDate = beforeDate ?? beforedate
		byUser = byUser ?? byuser
		byUsername = byUsername ?? byusername
		replyGroup = replyGroup ?? replygroup
		hideReplies = hideReplies ?? hidereplies
		likeType = likeType ?? liketype
		inBarrel = inBarrel ?? inbarrel

		if let searchStr = search {
			if searchStr.hasPrefix("#"), hashtag == nil {
				hashtag = String(searchStr.dropFirst())
				search = nil
			}
			if searchStr.hasPrefix("@"), mentions == nil {
				mentions = String(searchStr.dropFirst())
				search = nil
			}
		}
	}
	
	// TRUE if the 'next' tweets in this query are going to be newer or older than the current ones.
	// For instance, by default the 'anchor' is the most recent tweet and the direction is towards older tweets.
	func directionIsNewer() -> Bool {
		return (after != nil) || (afterdate != nil)  || (from == "first") || (replyGroup != nil)
	}
	
	func computedLimit() -> Int {
		return limit ?? 50
	}
	
	func buildQuery(baseURL: String, anchor: Int, startOffset: Int) -> String? {
		
		guard var components = URLComponents(string: baseURL) else {
			return nil
		}
		
		let hasAnchor = after != nil || before != nil || afterDate != nil || beforeDate != nil
	
		var elements = [URLQueryItem]()
		var beforeValue = before
		var afterValue = after
		if let search = search { elements.append(URLQueryItem(name: "search", value: search)) }
		if let hashtag = hashtag { elements.append(URLQueryItem(name: "hashtag", value: hashtag)) }
		if let mentions = mentions { elements.append(URLQueryItem(name: "mentions", value: mentions)) }
		if let byUser = byUser { elements.append(URLQueryItem(name: "byUser", value: byUser.uuidString)) }
		if let inBarrel = inBarrel { elements.append(URLQueryItem(name: "inBarrel", value: inBarrel.uuidString)) }
		if let from = from { elements.append(URLQueryItem(name: "from", value: from)) }
		if let limit = limit { elements.append(URLQueryItem(name: "limit", value: String(limit))) }
		let newOffset = (start ?? 0) + startOffset 
		if newOffset > 0 {
			elements.append(URLQueryItem(name: "start", value: String(newOffset)))
			if !hasAnchor {
				if directionIsNewer() {
					afterValue = anchor - 1
				}
				else {
					beforeValue = anchor + 1
				}
			}
		}
		else {
			if let val = beforeValue {
				beforeValue = val - newOffset
			}
			else if let val = afterValue {
				afterValue = val + newOffset
			}
			else if beforeDate != nil {
				beforeValue = anchor - newOffset
			}
			else if afterDate != nil {
				afterValue = anchor + newOffset
			}
		}
		if let before = beforeValue { elements.append(URLQueryItem(name: "before", value: String(before))) }
		else if let after = afterValue { elements.append(URLQueryItem(name: "after", value: String(after))) }
		else if let afterDate = afterDate { elements.append(URLQueryItem(name: "afterDate", value: afterDate)) }
		else if let beforeDate = beforeDate { elements.append(URLQueryItem(name: "beforeDate", value: beforeDate)) }
		else if let from = from { elements.append(URLQueryItem(name: "from", value: from)) }

		if let replyGroup = replyGroup { elements.append(URLQueryItem(name: "replyGroup", value: String(replyGroup))) }
		if let _ = hideReplies { elements.append(URLQueryItem(name: "hideReplies", value: "true")) }

		components.queryItems = elements
		return components.string
	}
}


/// The collection of `/api/v3/twitarr/*` route endpoint and handler functions related
/// to the twit-arr stream.
struct TwitarrController: APIRouteCollection {
		
// MARK: RouteCollection Conformance
	/// Required. Resisters routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/twitarr endpoints
		let twitarrRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .tweets)).grouped("api", "v3", "twitarr")

		// endpoints only available when logged in
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: twitarrRoutes)
		tokenCacheAuthGroup.get("", use: twarrtsHandler)
		tokenCacheAuthGroup.get(twarrtIDParam, use: twarrtHandler)
		tokenCacheAuthGroup.post("create", use: twarrtCreateHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "delete", use: twarrtDeleteHandler)
		tokenCacheAuthGroup.delete(twarrtIDParam, use: twarrtDeleteHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "reply", use: replyHandler)
		
		tokenCacheAuthGroup.post(twarrtIDParam, "laugh", use: twarrtLaughHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "like", use: twarrtLikeHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "love", use: twarrtLoveHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "unreact", use: twarrtUnreactHandler)
		tokenCacheAuthGroup.delete(twarrtIDParam, "laugh", use: twarrtUnreactHandler)
		tokenCacheAuthGroup.delete(twarrtIDParam, "like", use: twarrtUnreactHandler)
		tokenCacheAuthGroup.delete(twarrtIDParam, "love", use: twarrtUnreactHandler)

		tokenCacheAuthGroup.post(twarrtIDParam, "bookmark", use: bookmarkAddHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "bookmark", "remove", use: bookmarkRemoveHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "report", use: twarrtReportHandler)
		tokenCacheAuthGroup.post(twarrtIDParam, "update", use: twarrtUpdateHandler)
	}
	
	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.
			
/**
	`GET /api/v3/twitarr/ID`

	Retrieve the specified `Twarrt` with full user <doc:LikeType> data.

	- Parameter twarrtID: in URL path
	- Throws: 404 error if the twarrt is not available.
	- Returns: <doc:TwarrtDetailData> containing the specified twarrt.
*/
	func twarrtHandler(_ req: Request) async throws -> TwarrtDetailData {
		let cachedUser = try req.auth.require(UserCacheData.self)
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req, builder: { $0.with(\.$likes.$pivots) })
		// we have twarrt, but need to filter
		if cachedUser.getBlocks().contains(twarrt.$author.id) || cachedUser.getMutes().contains(twarrt.$author.id) ||
				twarrt.containsMutewords(using: cachedUser.mutewords ?? []) {
			throw Abort(.notFound, reason: "twarrt is not available")
		}
		guard let author = req.userCache.getUser(twarrt.$author.id)?.makeHeader() else {
			throw Abort(.internalServerError, reason: "Could not find author of twarrt.")
		}
		var twarrtDetailData = try TwarrtDetailData(
				postID: twarrt.requireID(),
				createdAt: twarrt.createdAt ?? Date(),
				author: author,
				text: twarrt.isQuarantined ? "This twarrt is under moderator review." : twarrt.text,
				images: twarrt.isQuarantined ? nil : twarrt.images,
				replyGroupID: twarrt.$replyGroup.id,
				isBookmarked: false,
				userLike: nil,
				laughs: [],
				likes: [],
				loves: []
		)
		// sort liking users into like types
		let likingUserHeaders = req.userCache.getHeaders(twarrt.$likes.pivots.map { $0.$user.id })
		for (index, liker) in twarrt.$likes.pivots.enumerated() {
			if liker.$user.id == cachedUser.userID {
				twarrtDetailData.userLike = liker.likeType
				twarrtDetailData.isBookmarked = liker.isFavorite
			}
			switch liker.likeType {
				case .laugh: twarrtDetailData.laughs.append(likingUserHeaders[index])
				case .like:  twarrtDetailData.likes.append(likingUserHeaders[index])
				case .love:  twarrtDetailData.loves.append(likingUserHeaders[index])
				default: continue
			}
		}
		return twarrtDetailData
	}
	 
/**
	`GET /api/v3/twitarr`

	Retrieve an array of `Twarrt`s. This query supports several optional query parameters.
	
	**URL Query Parameters**

	Parameters that filter the set of returned `Twarrt`s. These may be combined (but only one instance of each); 
	the result set will match all provided filters.
	* `?search=STRING` - Only return twarrts whose text contains the search string.
	* `?hashtag=STRING` - Only return twarrts whose text contains the given #hashtag. The # is not required in the value.
	* `?mentions=STRING` - Only return twarrts that @mention the given username. The @ is not required in the value.
	* `?mentionSelf=true` - Matches posts whose text contains a @mention of the current user.
	* `?byUser=ID` - Only return twarrts authored by the given user.
	* `?byUsername=STRING` - Only return twarrts authored by the given user.
	* `?bookmarked=true` - Only return twarrts the user has bookmarked.
	* `?replyGroup=ID` - Only return twarrts in the given replyGroup. The twarrt whose twarrtID == ID is always considered to be in the reply group,
	even if there are no replies to it.
	* `?hideReplies=true` - Filter out twarrts that are replies to other twarrts. Will still return the twarrt that starts a replyGroup. Ignored if `replyGroup` option is used.
	* `?likeType=[like, laugh, love, all]` - Only return twarrts the user has reacted to.

	Parameters that set the anchor. The anchor can be a specific `Twarrt`, a `Date`, or the first or last twarrt in the stream.
	These parameters are mutually exclusive. The default anchor if none is specified is `?from=last`. 
	If you specify a twarrt ID as an anchor, that twarrt does not need to pass the filter params (see above).
	* `?after=ID` - the ID of the twarrt *after* which the retrieval should start (newer).
	* `?before=ID` - the ID of the twarrt *before* which the retrieval should start (older).
	* `?afterDate=DATE` - the timestamp *after* which the retrieval should start (newer).
	* `?beforeDate=DATE` - the timestamp *before* which the retrieval should start (older).
	* `?from=STRING` - retrieve starting from "first" or "last".

	These parameters operate on the filtered set of twarrts, starting at the anchor, above. These parameters can be used
	to implement paging that is invariant to new results being added while displaying filtered twarrts. That is, for an initial call
	with `?hashtag=joco&from=last`, on subsequent calls you can call `?hashtag=joco&before=<id of first result>&start=50`
	and you will get the 50 twarrts containing the #joco hashtag, occuring immediately before the 50 results returned in the first call--
	even if there have been more twarrts posted with the hashtag in the interim.
	* `?start=INT` - the offset from the anchor to start. Offset only counts twarrts that pass the filters.
	* `?limit=INT` - the maximum number of twarrts to retrieve: 1-200, default is 50

	A query without additional parameters defaults to `?limit=50&from=last`, the 50 most recent twarrts.

	`DATE` values can be either `TimeInterval` values (Doubles) since epoch, or ISO8601
	string representations including milliseconds ("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"). The
	numeric value method is recommended.

	- Note: It is *highly* recommended that clients use `after=ID` or `before=ID` where
	  possible. `Twarrt` ID's are Int values and thus unambiguous. `DATE` values are
	  accurate only within 1 millisecond and are therefore prone to rounding errors. To
	  ensure that all twarrts of interest are returned when sending a date based on the
	  value found in a twarrt's timestamp, it is recommended that 1 millisecond be added
	  (if retrieving older) or subtracted (if retrieving newer) from that value for the
	  query. You will almost certainly receive the original anchor twarrt again, but it will
	  also ensure that any others possibly created within the same millisecond will not be
	  omitted.
	  
	- Note: Blocks are always applied to the search results. User mutes are applied to the search results unless a filter is used that 
	involves users or twarrts the user has previously interacted with (`inBarrel`, `likeType`, `bookmarked`) or matches users by name (`byuser`).

	- Throws: 400 error if a date parameter was supplied and is in an unknown format.
	- Returns: An array of <doc:TwarrtData> containing the requested twarrts.
*/
	func twarrtsHandler(_ req: Request) async throws -> [TwarrtData] {
		let cachedUser = try req.auth.require(UserCacheData.self)
 		let filters = try req.query.decode(TwarrtQueryOptions.self)
		
		// Query builder always filters out blocks and mutes, and the range always applies.
		let start = filters.start ?? 0
		let limit = (filters.limit ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		var postFilterMentions: String? = nil
		var applyMutes = true
		let twarrtQuery = Twarrt.query(on: req.db)
				.filter(\.$author.$id !~ cachedUser.getBlocks())
				.range(start..<(start + limit))
		
		// Process query params that set an anchor twarrt and search direction.
		// SearchDescending refers to the sort order in the database query, which affects start and limit.
		// SortDescending refers to the ordering of the returned twarrts.
		var searchDescending = true
		var sortDescending = true
		if let afterID = filters.after {
			twarrtQuery.filter(\.$id > afterID)
			searchDescending = false
		}
		else if let beforeID = filters.before {
			twarrtQuery.filter(\.$id < beforeID)
		}
		else if let afterDate = filters.afterDate {
			guard let date = TwitarrController.dateFromParameter(string: afterDate) else {
				throw Abort(.badRequest, reason: "not a recognized date format")
			}
			twarrtQuery.filter(\.$createdAt > date)
			searchDescending = false
		}
		else if let beforeDate = filters.beforeDate {
			guard let date = TwitarrController.dateFromParameter(string: beforeDate) else {
				throw Abort(.badRequest, reason: "not a recognized date format")
			}
			twarrtQuery.filter(\.$createdAt < date)
		}
		else if let from = filters.from?.lowercased(), from == "first" {
			searchDescending = false
		}
		
		// Process query params that filter for specific content.
		if let searchStr = filters.search {
			twarrtQuery.fullTextFilter(\.$text, searchStr)
			if !searchStr.contains(" ") && start == 0 {
				try await markNotificationViewed(user: cachedUser, type: .alertwordTwarrt(searchStr, 0), on: req)
			}
		}
		if var hashtag = filters.hashtag {
			if !hashtag.hasPrefix("#") {
				hashtag = "#\(hashtag)"
			}
			twarrtQuery.filter(\.$text, .custom("ILIKE"), "%\(hashtag)%")
		}
		if var mentions = filters.mentions {
			if !mentions.hasPrefix("@") {
				mentions = "@\(mentions)"
			}
			postFilterMentions = mentions
			twarrtQuery.filter(\.$text, .custom("ILIKE"), "%\(mentions)%")
		}
		if let mentionSelf = filters.mentionSelf, mentionSelf == true {
			let mentions = "@\(cachedUser.username)"
			postFilterMentions = mentions
			twarrtQuery.filter(\.$text, .custom("ILIKE"), "%\(mentions)%")
		}
		if let byUser = filters.byUser {
			applyMutes = false
			twarrtQuery.filter(\.$author.$id == byUser)
		}
		if let byUsername = filters.byUsername {
			applyMutes = false
			guard let targetCacheUser = req.userCache.getHeader(byUsername) else {
				throw Abort(.badRequest, reason: "byUsername query parameter references a nonexistent user.")
			}
			twarrtQuery.filter(\.$author.$id == targetCacheUser.userID)
		}
		if let replyGroup = filters.replyGroup {
			twarrtQuery.group(.or) { group in
				group.filter(\.$replyGroup.$id == replyGroup).filter(\.$id == replyGroup)
			}
			sortDescending = false
		}
		else if let hide = filters.hideReplies, hide == true {
			twarrtQuery.group(.or) { group in
				group.filter(\.$replyGroup.$id == nil).filter(\.$replyGroup.$id == \.$id)
			}
		}
		if filters.likeType != nil || filters.bookmarked == true {
			applyMutes = false
			twarrtQuery.join(children: \.$likes.$pivots).filter(TwarrtLikes.self, \TwarrtLikes.$user.$id == cachedUser.userID)
			switch filters.likeType {
				case "like": twarrtQuery.filter(TwarrtLikes.self, \TwarrtLikes.$likeType == .like)
				case "laugh": twarrtQuery.filter(TwarrtLikes.self, \TwarrtLikes.$likeType == .laugh)
				case "love": twarrtQuery.filter(TwarrtLikes.self, \TwarrtLikes.$likeType == .love)
				case "all": twarrtQuery.filter(TwarrtLikes.self, \TwarrtLikes.$likeType != nil)
				default: break
			}
			if filters.bookmarked == true {
				twarrtQuery.filter(TwarrtLikes.self, \TwarrtLikes.$isFavorite == true)
			}
		}
						
		if applyMutes {
			twarrtQuery.filter(\.$author.$id !~ cachedUser.getMutes())
		}

		let twarrts = try await twarrtQuery.sort(\.$id, searchDescending ? .descending : .ascending).all()
		// The filter() for mentions will include usernames that are prefixes for other usernames and other false positives.
		// This filters those out after the query. 
		var postFilteredTwarrts = twarrts
		if let postFilter = postFilterMentions {
			postFilteredTwarrts = twarrts.compactMap { $0.filterForMention(of: postFilter) }
			// This also clears new mentions in cases where the user got their mentions plus additional filters.
			if postFilter == "@\(cachedUser.username)" {
				try await markNotificationViewed(user: cachedUser, type: .twarrtMention(0), on: req)
			}
		}
	
		// correct sort order if necessary
		let sortedTwarrts: [Twarrt] = searchDescending == sortDescending ? postFilteredTwarrts : postFilteredTwarrts.reversed()
		return try await buildTwarrtData(from: sortedTwarrts, userID: cachedUser.userID, on: req, mutewords: cachedUser.mutewords)
	}
		
	/// `POST /api/v3/twitarr/ID/bookmark`
	///
	/// Add a bookmark of the specified `Twarrt`.
	///
	/// - Parameter twarrtID: in URL path
	/// - Throws: 400 error if the twarrt is already bookmarked.
	/// - Returns: 201 Created on success.
	func bookmarkAddHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		// get twarrt to make sure it exists
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		let twarrtLike = try await TwarrtLikes.query(on: req.db).filter(\.$user.$id == user.userID)
				.filter(\.$twarrt.$id == twarrt.requireID()).first() ?? TwarrtLikes(user.userID, twarrt, likeType: nil)
		twarrtLike.isFavorite = true
		try await twarrtLike.save(on: req.db)
		return .created
	}
	
	/// `POST /api/v3/twitarr/ID/bookmark/remove`
	///
	/// Remove a bookmark of the specified `Twarrt`.
	///
	/// - Parameter twarrtID: in URL path
	/// - Throws: 400 error if the user has not bookmarked any twarrts.
	/// - Returns: 204 NoContent on success.
	func bookmarkRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString, as: Twarrt.IDValue.self) else {
			throw Abort(.badRequest, reason: "Invalid twarrt ID parameter")
		}
		if let twarrtLike = try await TwarrtLikes.query(on: req.db).filter(\.$user.$id == user.userID)
				.filter(\.$twarrt.$id == twarrtID).first() {
			twarrtLike.isFavorite = false
			try await twarrtLike.save(on: req.db)		
		}
		return .noContent
	}
			
	/// `POST /api/v3/twitarr/:twarrt_ID/reply`
	///
	/// Create a `Twarrt` as a reply to an existing twarrt. If the replyTo twarrt is in quarantine, the post is rejected.
	/// 
	/// - Note: Replies work differently than on Twitter. Here, any twarrt that is replied to becomes a reply-group, and all 
	/// twarrts replying to ANY twarrt in the reply-group are added to that reply-group. Reply-groups are not nestable, and every twarrt
	/// is a member of at most one reply group. Twarrts that are not replies themselves are eligible to become the head of a reply-group if they are replied to.
	/// Twarrts that are replies are placed in a reply-group whose ID is the twarrt ID of the first twarrt in the group. This may not be the ID of the twarrt
	/// they're directly replying to. If B is created as a reply to A, and C is created as a reply to B, C is actually placed in a reply-group with both A and B.
	/// 
	/// One feature of this system for replies is that `TwarrtData.replyGroupID` can be used to discern whether a twarrt is part of a reply-group or not.
	///
	/// - Parameter twarrtID: in URL path. The twarrt to reply to.
	/// - Parameter requestBody: <doc:PostContentData>
	/// - Throws: 400 error if the replyTo twarrt is in quarantine.
	/// - Returns: A <doc:TwarrtData> containing the twarrt's contents and metadata. HTTP 201 status if successful.
	func replyHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent(customErrorString: "user cannot post twarrts")
		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		// get replyTo twarrt
		let replyTo = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		guard !replyTo.isQuarantined else {
			throw Abort(.badRequest, reason: "moderator-bot: twarrt cannot be replied to")
		}
		// process images
		let filenames = try await self.processImages(data.images, usage: .twarrt, on: req)
		// create twarrt and save it
		let effectiveAuthor = data.effectiveAuthor(actualAuthor: cacheUser, on: req)
		let twarrt = try Twarrt(authorID: effectiveAuthor.userID, text: data.text, images: filenames, replyTo: replyTo)
		try await twarrt.save(on: req.db)
		try await twarrt.logIfModeratorAction(.post, moderatorID: cacheUser.userID, on: req)
		try await processTwarrtMentions(twarrt: twarrt, editedText: nil, isCreate: true, on: req)
		if replyTo.$replyGroup.id == nil {
			// If the replyTo twarrt wasn't in a replyGroup, it becomes the head of a new one.
			replyTo.$replyGroup.id = replyTo.id
			try await replyTo.save(on: req.db)
		}
		// return as TwarrtData with 201 status
		let response = Response(status: .created)
		try response.content.encode(TwarrtData(twarrt: twarrt, creator: cacheUser.makeHeader(), isBookmarked: false,
				userLike: nil, likeCount: 0))
		return response
	}
		
	/// `POST /api/v3/twitarr/create`
	///
	/// Create a new `Twarrt` in the twitarr stream.
	///
	/// - Parameter requestBody: <doc:PostContentData>
	/// - Returns: <doc:TwarrtData> containing the twarrt's contents and metadata. HTTP 201 status if successful.
	func twarrtCreateHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent(customErrorString: "user cannot post twarrts")
 		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		// process images then save new twarrt
		let filenames = try await self.processImages(data.images, usage: .twarrt, on: req)
		let effectiveAuthor = data.effectiveAuthor(actualAuthor: cacheUser, on: req)
		let twarrt = try Twarrt(authorID: effectiveAuthor.userID, text: data.text, images: filenames)
		try await twarrt.save(on: req.db)
		// Secondary effects
		try await twarrt.logIfModeratorAction(.post, moderatorID: cacheUser.userID, on: req)
		try await processTwarrtMentions(twarrt: twarrt, editedText: nil, isCreate: true, on: req)
		// return as TwarrtData with 201 status
		let response = Response(status: .created)
		try response.content.encode(TwarrtData(twarrt: twarrt, creator: effectiveAuthor.makeHeader(), isBookmarked: false,
				userLike: nil, likeCount: 0))
		return response
	}
	
	/// `POST /api/v3/twitarr/ID/delete`
	/// `DELETE /api/v3/twitarr/ID`
	///
	/// Delete the specified `Twarrt`.
	///
	/// - Parameter twarrtID: in URL path. The twarrt to delete.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func twarrtDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		try cacheUser.guardCanModifyContent(twarrt, customErrorString: "user cannot delete twarrt")
		try await processTwarrtMentions(twarrt: twarrt, editedText: nil, on: req)
		try await twarrt.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		try await twarrt.delete(on: req.db)
		return .noContent
	}
	
	/// `POST /api/v3/twitarr/ID/report`
	///
	/// Create a `Report` regarding the specified `Twarrt`. If the twarrt has reached the report
	/// threshold for auto-quarantining, it is quarantined.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   sent an empty string in the `.message` field.
	///
	/// - Parameter twarrtID: in URL path. The twarrt to report.
	/// - Parameter requestBody: <doc:ReportData>
	/// - Throws: 400 error if user has already submitted report.
	/// - Returns: 201 Created on success.
	func twarrtReportHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		return try await twarrt.fileReport(submitter: user, submitterMessage: data.message, on: req)
	}
	
	/// `POST /api/v3/twitarr/ID/laugh`
	///
	/// Add a "laugh" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
	///
	/// - Parameter twarrtID: in URL path.
	/// - Throws: 403 error if user is the twarrt's creator.
	/// - Returns: <doc:TwarrtData> containing the updated like info.
	func twarrtLaughHandler(_ req: Request) async throws -> TwarrtData {
		return try await twarrtReactHandler(req, likeType: .laugh)
	}
	
	/// `POST /api/v3/twitarr/ID/like`
	///
	/// Add a "like" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
	///
	/// - Parameter twarrtID: in URL path.
	/// - Throws: 403 error if user is the twarrt's creator.
	/// - Returns: <doc:TwarrtData> containing the updated like info.
	func twarrtLikeHandler(_ req: Request) async throws -> TwarrtData {
		return try await twarrtReactHandler(req, likeType: .like)
	}

	/// `POST /api/v3/twitarr/ID/love`
	///
	/// Add a "love" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
	///
	/// - Parameter twarrtID: in URL path.
	/// - Throws: 403 error if user is the twarrt's creator.
	/// - Returns: <doc:TwarrtData> containing the updated like info.
	func twarrtLoveHandler(_ req: Request) async throws -> TwarrtData {
		return try await twarrtReactHandler(req, likeType: .love)
	}

	/// Add a  reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
	///  All 3 reaction handlers use this function as they all do the same thing.
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Parameter likeType:  The type of reaction being set.
	/// - Throws: 403 error if user is the twarrt's creator.
	/// - Returns: <doc:TwarrtData> containing the updated like info.
	func twarrtReactHandler(_ req: Request, likeType: LikeType) async throws -> TwarrtData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get twarrt
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		guard twarrt.$author.id != cacheUser.userID else {
			throw Abort(.forbidden, reason: "user cannot like own twarrt")
		}
		// check for existing like, else make a new one
		let twarrtLike = try await TwarrtLikes.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
				.filter(\.$twarrt.$id == twarrt.requireID()).first() ?? TwarrtLikes(cacheUser.userID, twarrt, likeType: .laugh)
		twarrtLike.likeType = likeType
		try await twarrtLike.save(on: req.db)
		return try await buildTwarrtData(from: twarrt, userID: cacheUser.userID, on: req)
	}
		
	/// `POST /api/v3/twitarr/ID/unreact`
	/// `DELETE /api/v3/twitarr/ID/reaction`
	///
	/// Remove a `LikeType` reaction from the specified `Twarrt`.
	///
	/// - Parameter twarrtID: in URL path.
	/// - Throws: 403 error if user is is the twarrt's creator. 404 if no twarrt with the ID is found. 
	/// - Returns: <doc:TwarrtData> containing the updated like info.
	func twarrtUnreactHandler(_ req: Request) async throws -> TwarrtData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get twarrt
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		guard twarrt.$author.id != cacheUser.userID else {
			throw Abort(.forbidden, reason: "user cannot like own post")
		}
		if let twarrtLike = try await TwarrtLikes.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
				.filter(\.$twarrt.$id == twarrt.requireID()).first() {
			twarrtLike.likeType = nil
			try await twarrtLike.save(on: req.db)
		}
		return try await buildTwarrtData(from: twarrt, userID: cacheUser.userID, on: req)
	}
	
	/// `POST /api/v3/twitarr/ID/update`
	///
	/// Update the specified `Twarrt`.
	///
	/// - Parameter twarrtID: in URL path.
	/// - Parameter requestBody: <doc:PostContentData>
	/// - Throws: 403 error if user is not twarrt owner or has read-only access.
	/// - Returns: <doc:TwarrtData> containing the twarrt's contents and metadata.
	func twarrtUpdateHandler(_ req: Request) async throws -> TwarrtData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		let twarrt = try await Twarrt.findFromParameter(twarrtIDParam, on: req)
		// I *think* the author should be allowed to edit a quarantined twarrt?
		// ensure user has write access
		try cacheUser.guardCanModifyContent(twarrt, customErrorString: "user cannot modify twarrt")
		let filenames = try await processImages(data.images, usage: .twarrt, on: req)
		// update if there are changes
		let normalizedText = data.text.replacingOccurrences(of: "\r\n", with: "\r")
		if twarrt.text != normalizedText || twarrt.images != filenames {
			try await processTwarrtMentions(twarrt: twarrt, editedText: normalizedText, on: req)
			// stash current twarrt contents before modifying
			let twarrtEdit = try TwarrtEdit(twarrt: twarrt, editorID: cacheUser.userID)
			twarrt.text = normalizedText
			twarrt.images = filenames
			try await twarrtEdit.save(on: req.db)
			try await twarrt.save(on: req.db)
			try await twarrt.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
		}
		// return updated twarrt as TwarrtData, with 201 status
		let twarrtData = try await buildTwarrtData(from: twarrt, userID: cacheUser.userID, on: req)
		return twarrtData
	}
}

// MARK: -
extension TwitarrController {
	// Builds a TwarrtData from a Twarrt. Uses the array builder to do its work. Don't call this in a loop;
	// the array builder is much more efficient. This does give a better error if the twarrt isn't found or is blocked.
	func buildTwarrtData(from twarrt: Twarrt, userID: UUID, on req: Request) async throws -> TwarrtData {
		let twarrtData = try await buildTwarrtData(from: [twarrt], userID: userID, on: req)
		guard let result = twarrtData.first else {
			throw Abort(.internalServerError, reason: "Twarrt not found.")
		}
		return result
	}

	// Builds an array of TwarrtDatas from an array of Twarrts. Can filter out twarrts containing mutewords and also
	// does post-query hashtag filtering.
	func buildTwarrtData(from twarrts: [Twarrt], userID: UUID, on req: Request, mutewords: [String]? = nil, 
			assumeBookmarked: Bool? = nil, matchHashtag: String? = nil) async throws -> [TwarrtData] {
		// remove muteword twarrts
		var filteredTwarrts = twarrts
		if let mutewords = mutewords {
			 filteredTwarrts = twarrts.compactMap { $0.filterOutStrings(using: mutewords) }
		}
		// get exact hashtag if we're matching on hashtag
		if let hashtag = matchHashtag {
			filteredTwarrts = filteredTwarrts.compactMap { (filteredTwarrt) -> Twarrt? in
				let text = filteredTwarrt.text.lowercased()
				let words = text.components(separatedBy: .whitespacesAndNewlines + .contentSeparators)
				return words.contains(hashtag) ? filteredTwarrt : nil
			}
		}
		
		let twarrtIDs = try filteredTwarrts.map { try $0.requireID() }
		let userLikes = try await TwarrtLikes.query(on: req.db).filter(\.$twarrt.$id ~~ twarrtIDs).filter(\.$user.$id == userID).all()
		let userLikeDict = Dictionary(userLikes.map { ($0.$twarrt.id, $0) }, uniquingKeysWith: { (first, _) in first })
		let likeCountDict = try await filteredTwarrts.childCountsPerModel(atPath: \.$likes.$pivots, on: req.db,
				fluentFilter: { builder in builder.filter(\.$likeType != nil) },
				sqlFilter: { builder in builder.where("liketype", .isNot, SQLLiteral.null) })
		return try filteredTwarrts.map { twarrt in
			let twarrtID = try twarrt.requireID()
			let author = try req.userCache.getHeader(twarrt.$author.id)
			let bookmarked = assumeBookmarked ?? userLikeDict[twarrtID]?.isFavorite ?? false
			let userLike = userLikeDict[twarrtID]?.likeType
			let likeCount = likeCountDict[twarrtID] ?? 0
			return try TwarrtData(twarrt: twarrt, creator: author, isBookmarked: bookmarked, userLike: userLike, likeCount: likeCount)
		}
	}
	
	// Scans the text of twarrts as they are created/edited/deleted. Handles several on-post text processing tasks.
	//	1. finds @mentions, updates mention counts for mentioned `User`s. 
	//	2. runs text through the alertword checker, adjusts counts for words *someone* is alerting on.
	//		--note: Does not trigger a notification directly, although perhaps it could? Instead, the next time
	// 		the user calls the notification endpoint they are informed of the new alertword hits.
	//	3. finds hashtags 
	func processTwarrtMentions(twarrt: Twarrt, editedText: String?, isCreate: Bool = false, on req: Request) async throws {	
		let twarrtID = try twarrt.requireID()
		try await withThrowingTaskGroup(of: Void.self) { group in
			// Mentions
			let (subtracts, adds) = twarrt.getMentionsDiffs(editedString: editedText, isCreate: isCreate)
			if !subtracts.isEmpty {
				let subtractUUIDs = req.userCache.getHeaders(usernames: subtracts).map { $0.userID }
				group.addTask { try await subtractNotifications(users: subtractUUIDs, type: .twarrtMention(twarrtID), on: req) }
			}
			if !adds.isEmpty {
				let addUUIDs = req.userCache.getHeaders(usernames: adds).map { $0.userID }
				let authorName = req.userCache.getUser(twarrt.$author.id)?.username
				let infoStr = "\(authorName == nil ? "A user" : "User @\(authorName!)") posted a twarrt that @mentioned you."
				group.addTask { try await addNotifications(users: addUUIDs, type: .twarrtMention(twarrtID), info: infoStr, on: req) }
			}
			
			// Alert words check
			let (alertSubtracts, alertAdds) = twarrt.getAlertwordDiffs(editedString: editedText, isCreate: isCreate)
			let alertSet = try await req.redis.getAllAlertwords()
			let subtractingAlertWords = alertSubtracts.intersection(alertSet)
			let addingAlertWords = alertAdds.intersection(alertSet)
			subtractingAlertWords.forEach { word in
				group.addTask { 
					let userIDs = try await req.redis.getUsersForAlertword(word)
					return try await subtractNotifications(users: userIDs, type: .alertwordTwarrt(word, twarrtID), on: req)
				}
			}
			if addingAlertWords.count > 0 {
				let authorName = req.userCache.getUser(twarrt.$author.id)?.username
				addingAlertWords.forEach { word in
					let infoStr = "\(authorName == nil ? "A user" : "User @\(authorName!)") posted a twarrt containing your alert word '\(word)'."
					group.addTask { 
						let userIDs = try await req.redis.getUsersForAlertword(word)
						let validUserIDs = req.userCache.getUsers(userIDs).compactMap { $0.accessLevel >= .quarantined ? $0.userID : nil }
						return try await addNotifications(users: validUserIDs, type: .alertwordTwarrt(word, twarrtID), info: infoStr, on: req)
					}
				}
			}

			// Hashtag check
			let hashtags = twarrt.getHashtags()
			if !hashtags.isEmpty {
				group.addTask { try await req.redis.addHashtags(hashtags) }
			}
			// I believe this line is required to let subtasks propagate thrown errors by rethrowing.
			for try await _ in group { }
		}
	}
}

import Crypto
import Fluent
import FluentSQL
import RediStack
import Redis
import Vapor

/// The collection of `/api/v3/user/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct UsersController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// endpoints available only when logged in, and not subject to feature-disable flags.
		let tokenAuthGroup = app.grouped("api", "v3", "users").addTokenAuthRequirement()
		tokenAuthGroup.get("find", ":userSearchString", use: findHandler)
		tokenAuthGroup.get(userIDParam, use: headerHandler)
		tokenAuthGroup.get("match", "allnames", searchStringParam, use: matchAllNamesHandler)
		tokenAuthGroup.get("match", "username", searchStringParam, use: matchUsernameHandler)
		tokenAuthGroup.get(userIDParam, "profile", use: profileHandler)
		tokenAuthGroup.post(userIDParam, "report", use: reportHandler)

		// Endpoints available only when logged in, and also can be disabled by server admin
		let blockableAuthGroup = tokenAuthGroup.grouped(DisabledAPISectionMiddleware(feature: .users))

		// Notes on users
		blockableAuthGroup.post(userIDParam, "note", use: noteCreateHandler)
		blockableAuthGroup.post(userIDParam, "note", "delete", use: noteDeleteHandler)
		blockableAuthGroup.delete(userIDParam, "note", use: noteDeleteHandler)
		blockableAuthGroup.get(userIDParam, "note", use: noteHandler)

		// Blocks, Mutes, Favorites
		blockableAuthGroup.get("blocks", use: blocksHandler)
		blockableAuthGroup.post(userIDParam, "block", use: blockHandler)
		blockableAuthGroup.post(userIDParam, "unblock", use: unblockHandler)
		blockableAuthGroup.get("mutes", use: mutesHandler)
		blockableAuthGroup.post(userIDParam, "mute", use: muteHandler)
		blockableAuthGroup.post(userIDParam, "unmute", use: unmuteHandler)
		blockableAuthGroup.get("favorites", use: favoritesHandler)
		blockableAuthGroup.post(userIDParam, "favorite", use: favoriteAddHandler)
		blockableAuthGroup.post(userIDParam, "unfavorite", use: favoriteRemoveHandler)

		// User Role Management for non-THO. Currently, this means the Shutternaut Manager managing the Shutternaut role
		blockableAuthGroup.get("userrole", userRoleParam, use: getUsersWithRole)
		blockableAuthGroup.post("userrole", userRoleParam, "addrole", userIDParam, use: addRoleForUser)
		blockableAuthGroup.post("userrole", userRoleParam, "removerole", userIDParam, use: removeRoleForUser)
	}

	// MARK: - Finding Other Users
	/// `GET /api/v3/users/find/:username`
	///
	/// Retrieves a user's `UserHeader` using either an ID (UUID string) or a username.
	///
	/// This endpoint is of limited utility, but is included for the case of obtaining a
	/// user's ID from a username. If you have an ID and want the associated username, use
	/// the more efficient `/api/v3/users/ID` endpoint instead.
	///
	/// - Note: Because a username can be changed, there is no guarantee that a once-valid
	///   username will result in a successful return, even though the User itself does
	///   exist.
	///
	/// - Parameter STRING: in URL path. The userID or username to search for.
	/// - Throws: 404 error if no match is found.
	/// - Returns: `UserHeader` containing the user's ID, username, displayName and userImage.
	func findHandler(_ req: Request) throws -> UserHeader {
		let requester = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get("userSearchString") else {
			throw Abort(.badRequest, reason: "Find User: missing search string")
		}
		var userHeader: UserHeader? = req.userCache.getHeader(parameter)
		// try converting to UUID
		if userHeader == nil, let userID = UUID(uuidString: parameter) {
			userHeader = try? req.userCache.getHeader(userID)
		}
		guard let foundUser = userHeader else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		if requester.getBlocks().contains(foundUser.userID) {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		return foundUser
	}

	/// `GET /api/v3/users/:userID`
	///
	/// Retrieves the specified user's `UserHeader` info.
	///
	/// This endpoint provides one-off retrieval of the user information appropriate for
	/// a header on posted content – the user's ID, current generated `.displayedName`, and
	/// filename of their current profile image.
	///
	/// For bulk data retrieval, see the `ClientController` endpoints.
	///
	/// - Parameter userID: in URL path. The userID to search for.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `UserHeader` containing the user's ID, `.displayedName` and profile image filename.
	func headerHandler(_ req: Request) throws -> UserHeader {
		let requester = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "UserID parameter missing or invalid UUID")
		}
		let userHeader = try req.userCache.getHeader(parameter)
		guard !requester.getBlocks().contains(userHeader.userID) else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		return userHeader
	}

	/// `GET /api/v3/users/ID/profile`
	///
	/// Retrieves the specified user's profile, as a `ProfilePublicData` object.
	///
	/// - Parameter userID: in URL path. The userID to search for.
	/// - Throws: 404 error if the profile is not available. A 5xx response should be reported
	///   as a likely bug, please and thank you.
	/// - Returns: `ProfilePublicData` containing the displayable properties of the specified
	///   user's profile.
	func profileHandler(_ req: Request) async throws -> ProfilePublicData {
		let requester = try req.auth.require(UserCacheData.self)
		let profiledUser = try await User.findFromParameter(userIDParam, on: req)
		// 404 if blocked
		if requester.getBlocks().contains(try profiledUser.requireID()) {
			throw Abort(.notFound, reason: "profile is not available")
		}
		// a .banned profile is only available to .moderator or above
		if profiledUser.accessLevel == .banned && !requester.accessLevel.hasAccess(.moderator) {
			throw Abort(.notFound, reason: "profile is not available")
		}
		// Profile hidden if user quarantined and requester not mod, or if requester is banned.
		var publicProfile = try ProfilePublicData(
			user: profiledUser,
			note: nil,
			requesterAccessLevel: requester.accessLevel
		)
		// include UserNote if any, then return
		if let note = try await UserNote.query(on: req.db).filter(\.$author.$id == requester.userID)
			.filter(\.$noteSubject.$id == profiledUser.requireID()).first()
		{
			publicProfile.note = note.note
		}
		return publicProfile
	}

	/// `GET /api/v3/users/match/allnames/STRING`
	///
	/// Retrieves the first 10 `User.userSearch` values containing the specified substring,
	/// returning an array of `UserHeader` structs..
	/// The intended use for this endpoint is to help isolate a particular user in an
	/// auto-complete type scenario, by searching **all** of the `.displayName`, `.username`
	/// and `.realName` profile fields.
	///
	/// Compare to `/api/v3/user/match/username/STRING`, which searches just `.username` and
	/// returns an array of just strings.
	///
	/// - Note: If the search substring contains "unsafe" characters, they must be url encoded.
	///   Unicode characters are supported. A substring comprised only of whitespace is
	///   disallowed. A substring of "@" or "(@" is explicitly disallowed to prevent single-step
	///   username harvesting.
	///
	/// For bulk `.userSearch` data retrieval, see the `ClientController` endpoints.
	/// 
	/// **URL Query Parameters:**
	/// - ?favors=BOOLEAN Show only resulting users that have favorited the requesting user.
	///
	/// - Parameter STRING: in URL path. The search string to use. Must be at least 2 characters long.
	/// - Throws: 403 error if the search term is not permitted.
	/// - Returns: An array of `UserHeader` values of all matching users.
	func matchAllNamesHandler(_ req: Request) async throws -> [UserHeader] {
		let requester = try req.auth.require(UserCacheData.self)
		guard var search = req.parameters.get(searchStringParam.paramString) else {
			throw Abort(.badRequest, reason: "No user search string in request.")
		}
		// postgres "_" and "%" are wildcards, so escape for literals
		search = search.replacingOccurrences(of: "_", with: "\\_")
		search = search.replacingOccurrences(of: "%", with: "\\%")
		// trim and disallow "@" harvesting
		search = search.trimmingCharacters(in: .whitespacesAndNewlines)
		guard search != "@", search != "(@" else {
			throw Abort(.forbidden, reason: "'\(search)' is not a permitted search string")
		}
		guard search.count >= 2 else {
			throw Abort(.badRequest, reason: "User search requires at least 2 valid characters in search string..")
		}

		// Process query params
		struct QueryOptions: Content {
			var favors: Bool?
		}
		let options: QueryOptions = try req.query.decode(QueryOptions.self)

		// Return matches based on the query mode.
		// Remove any blocks from the results.
		var matchingUsers: [User] = []
		if let _ = options.favors {
			let favoritingUsers = try await UserFavorite.query(on: req.db)
				.join(User.self, on: \UserFavorite.$user.$id == \User.$id, method: .left)
				.filter(\.$user.$id !~ requester.getBlocks())
				.filter(\.$favorite.$id == requester.userID)
				.filter(User.self, \.$userSearch, .custom("ILIKE"), "%\(search)%")
				.sort(User.self, \.$username, .ascending)
				.range(0..<10)
				.with(\.$user)
				.all()
			matchingUsers = favoritingUsers.map { $0.user }
		} else {
			matchingUsers = try await User.query(on: req.db)
				.filter(\.$userSearch, .custom("ILIKE"), "%\(search)%")
				.filter(\.$id !~ requester.getBlocks())
				.sort(\.$username, .ascending)
				.range(0..<10)
				.all()
		}
		return try matchingUsers.map { try UserHeader(user: $0) }
	}

	/// `GET /api/v3/users/match/username/STRING`
	///
	/// Retrieves all usernames containing the specified substring, returning an array
	/// of `@username` strings. The intended use for this endpoint is to help isolate a
	/// particular user in an auto-complete type scenario.
	///
	/// - Note: An `@` is prepended to each returned matching username as a convenience, but
	///   should never be included in the search itself. No base username can contain an `@`,
	///   thus there would never be a match.
	///
	/// - Parameter STRING: in URL path. The search string to use. Must be at least 2 characters long.
	/// - Returns: An array of  `String` containng all matching usernames as "@username" strings.
	func matchUsernameHandler(_ req: Request) async throws -> [String] {
		let requester = try req.auth.require(UserCacheData.self)
		guard var search = req.parameters.get(searchStringParam.paramString) else {
			throw Abort(.badRequest, reason: "No user search string in request.")
		}
		guard search.count >= 2 else {
			throw Abort(.badRequest, reason: "User search requires at least 2 valid characters in search string..")
		}
		// postgres "_" is wildcard, so escape for literal
		search = search.replacingOccurrences(of: "_", with: "\\_")
		// remove blocks from results
		let users = try await User.query(on: req.db).filter(\.$username, .custom("ILIKE"), "%\(search)%")
			.filter(\.$id !~ requester.getBlocks()).sort(\.$username, .ascending).all()
		// return @username only
		return users.map { "@\($0.username)" }
	}

	// MARK: - Actions Taken on Other Users
	/// `POST /api/v3/users/ID/note`
	///
	/// Saves a `UserNote` associated with the specified user and the current user.
	///
	/// - Parameter userID: in URL path. The user to associate with the note.
	/// - Parameter requestBody: `NoteCreateData` struct containing the text of the note.
	/// - Throws: 400 error if the profile is a banned user's. A 5xx response should be reported as a likely bug, please and
	///   thank you.
	/// - Returns: `NoteData` containing the newly created note.
	func noteCreateHandler(_ req: Request) async throws -> Response {
		let requester = try req.auth.require(UserCacheData.self)
		let data = try ValidatingJSONDecoder().decode(NoteCreateData.self, fromBodyOf: req)
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		// profile shouldn't be visible, but just in case
		guard targetUser.accessLevel != .banned else {
			throw Abort(.badRequest, reason: "notes are unavailable for profile")
		}
		// check for existing note
		let note =
			try await UserNote.query(on: req.db).filter(\.$author.$id == requester.userID)
			.filter(\.$noteSubject.$id == targetUser.requireID()).first()
			?? UserNote(authorID: requester.userID, subjectID: targetUser.requireID(), note: data.note)
		note.note = data.note
		try await note.save(on: req.db)
		// return note's data with 201 response
		let createdNoteData = try NoteData(note: note, targetUser: targetUser)
		return try await createdNoteData.encodeResponse(status: .created, for: req)
	}

	/// `POST /api/v3/users/ID/note/delete`
	/// `DELETE /api/v3/users/ID/note`
	///
	/// Deletes an existing `UserNote` associated with the specified user's profile and
	/// the current user.
	///
	/// - Parameter userID: in URL path. Specifies the target of the note to be deleted.
	/// - Throws: 400 error if there is no existing note on the profile. A 5xx response should
	///   be reported as a likely bug, please and thank you.
	/// - Returns: 204 No Content on success.
	func noteDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let requester = try req.auth.require(UserCacheData.self)
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		// delete note if found
		if let note = try await UserNote.query(on: req.db).filter(\.$author.$id == requester.userID)
			.filter(\.$noteSubject.$id == targetUser.requireID()).first()
		{
			try await note.delete(force: true, on: req.db)
		}
		return .noContent
	}

	/// `GET /api/v3/users/ID/note`
	///
	/// Retrieves an existing `UserNote` associated with the specified user's profile and
	/// the current user.
	///
	/// - Note: In order to support the editing of a note in contexts other than when
	///   actively viewing a profile, the contents of `profile.note` cannot be used to determine
	///   if there is an exiting associated UserNote, since it is possible for a valid note to
	///   contain no text at any given time. Use this GET endpoint prior to attempting a POST
	///   to it.
	///
	/// - Parameter userID: in URL path. The user the note is attached to.
	/// - Throws: 400 error if there is no existing note on the profile. A 5xx response should
	///   be reported as a likely bug, please and thank you.
	/// - Returns: `NoteEditData` containing the note's ID and text.
	func noteHandler(_ req: Request) async throws -> NoteData {
		let requester = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(userIDParam.paramString), let targetUserID = UUID(parameter) else {
			throw Abort(.badRequest, reason: "No user ID in request.")
		}
		guard
			let note = try await UserNote.query(on: req.db).filter(\.$author.$id == requester.userID)
				.filter(\.$noteSubject.$id == targetUserID).with(\.$noteSubject).first()
		else {
			throw Abort(.badRequest, reason: "no existing note found")
		}
		return try NoteData(note: note, targetUser: note.noteSubject)
	}

	/// `POST /api/v3/users/ID/report`
	///
	/// Creates a `Report` regarding the specified user's profile, either the text fields or the avatar image.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter requestBody: `ReportData` containing an optional accompanying message
	/// - Returns: 201 Created on success.
	func reportHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedUser = try await User.findFromParameter(userIDParam, on: req)
		return try await reportedUser.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}

	// MARK: - Blocks and Mutes
	/// `GET /api/v3/users/blocks`
	///
	/// Returns a list of the user's currently blocked users as an array of `UserHeader` objects.
	/// If the user is a sub-account, the parent user's blocks are returned.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: Array of `UserHeader` containing the currently blocked users.
	func blocksHandler(_ req: Request) async throws -> [UserHeader] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// if sub-account, we want parent's blocks
		guard let user = try await User.query(on: req.db).filter(\.$id == cacheUser.userID).with(\.$parent).first()
		else {
			throw Abort(.internalServerError, reason: "User not found in database.")
		}
		let parentUser = user.parent ?? user
		return req.userCache.getHeaders(parentUser.blockedUserIDs).sorted { $0.username < $1.username }
	}

	/// `POST /api/v3/users/:userID/block`
	///
	/// Blocks the specified `User`. The blocking user and any sub-accounts will not be able
	/// to see posts from the blocked `User` or any of their associated sub-accounts, and vice
	/// versa. This affects all forms of communication, public and private, as well as user
	/// searches.
	///
	/// Only the specified user is added to the block list, so as not to explicitly expose the
	/// ownership of any other accounts the blocked user may be using. The blocking of any
	/// associated user accounts is handled under the hood.
	///
	/// Users with an `.accessLevel` of `.moderator` or higher may not be blocked.
	/// Attempting to block a moderator account directly will produce an error.  A block
	/// applied to an alt account of a moderator will be accepted, but will not include the moderator
	/// in the set of blocked accounts. Similarly, moderators can block accounts, which has no
	/// effect on their moderator account but applies bidirectional blocks between their (non-moderator)
	/// alt accounts and the blocked accounts.
	///
	/// - Parameter userID: in URL path. The userID to block.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: 201 Created on success, 200 OK if user already in block list.
	func blockHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// if sub-account, we want parent
		guard let requester = try await User.query(on: req.db).filter(\.$id == cacheUser.userID).with(\.$parent).first()
		else {
			throw Abort(.internalServerError, reason: "User not found in database.")
		}
		let parentUser = requester.parent ?? requester
		guard let userIDToBlock = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Request parameter userID is missing.")
		}
		guard let blockee = req.userCache.getUser(userIDToBlock) else {
			throw Abort(.badRequest, reason: "Can't find a user with the userID specified in the :userID parameter")
		}
		// This guard only applies to *directly* blocking a moderator's Mod account.
		guard blockee.accessLevel < .moderator else {
			throw Abort(.badRequest, reason: "Cannot block accounts of moderators, THO, or admins")
		}
		guard try userIDToBlock != cacheUser.userID && userIDToBlock != parentUser.requireID() else {
			throw Abort(.badRequest, reason: "You cannot block yourself.")
		}
		if parentUser.blockedUserIDs.contains(userIDToBlock) {
			return .ok
		}
		parentUser.blockedUserIDs.append(userIDToBlock)
		try await parentUser.save(on: req.db)
		try await addBlockToCache(requestedBy: parentUser, blocking: userIDToBlock, on: req)
		return .created
	}

	/// `POST /api/v3/users/ID/unblock`
	///
	/// Removes a block of the specified `User` and all sub-accounts by the current user and
	/// all associated accounts.
	///
	/// - Parameter userID: in URL path. The user to unblock.
	/// - Throws: 400 error if the specified user was not currently blocked. A 5xx response
	///   should be reported as a likely bug, please and thank you.
	/// - Returns: 204 No Content on success.
	func unblockHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let requester = try await User.query(on: req.db).filter(\.$id == cacheUser.userID).with(\.$parent).first()
		else {
			throw Abort(.internalServerError, reason: "User not found in database.")
		}
		let parentUser = requester.parent ?? requester
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		let targetUserID = try targetUser.requireID()
		parentUser.blockedUserIDs.removeAll { $0 == targetUserID }
		try await parentUser.save(on: req.db)
		try await removeBlockFromCache(by: requester, of: targetUser, on: req)
		return .noContent
	}

	/// `GET /api/v3/users/mutes`
	///
	/// Returns a list of the user's currently muted users.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: Array of `UserHeader` containing the currently muted users.
	func mutesHandler(_ req: Request) async throws -> [UserHeader] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let user = try await User.find(cacheUser.userID, on: req.db) else {
			throw Abort(.internalServerError, reason: "User not found in database.")
		}
		return req.userCache.getHeaders(user.mutedUserIDs).sorted { $0.username < $1.username }
	}

	/// `POST /api/v3/users/ID/mute`
	///
	/// Mutes the specified `User` for the current user. The muting user will not see public
	/// posts from the muted user. A mute does not affect what is or is not visible to the
	/// muted user. A mute does not affect private communication channels.
	///
	/// A mute does not mute any associated sub-accounts of the muted `User`, nor is it applied
	/// to any of the muting user's associated accounts. It is very much just *this* currently
	/// logged-in username muting *that* one username.
	///
	/// Any user can be muted, including users with privileged `.accessLevel`. Such users are
	/// *not* muted, however, when posting from role accounts. That is, a `.moderator` can post
	/// *as* `@moderator` and it is visible to all users, period.
	///
	/// - Parameter userID: in URL path. The userID to mute.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: 201 Created on success.
	func muteHandler(_ req: Request) async throws -> HTTPStatus {
		let requester = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(userIDParam.paramString), let mutedUserID = UUID(parameter) else {
			throw Abort(.badRequest, reason: "No user ID in request.")
		}
		guard let _ = try await User.find(mutedUserID, on: req.db) else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		guard let requestingUser = try await User.find(requester.userID, on: req.db) else {
			throw Abort(.internalServerError, reason: "User not found in db, but present in cache")
		}
		if !requestingUser.mutedUserIDs.contains(mutedUserID) {
			requestingUser.mutedUserIDs.append(mutedUserID)
			try await requestingUser.save(on: req.db)
			try await req.userCache.updateUser(requester.userID)
		}
		return .created
	}

	/// `POST /api/v3/users/ID/unmute`
	///
	/// Removes a mute of the specified `User` by the current user.
	///
	/// - Parameter userID: in URL path. The user to unmute.
	/// - Throws: 400 error if the specified user was not currently muted. A 5xx response should
	///   be reported as a likely bug, please and thank you.
	/// - Returns: 204 No Content on success.
	func unmuteHandler(_ req: Request) async throws -> HTTPStatus {
		let requester = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(userIDParam.paramString), let unmutedUserID = UUID(parameter) else {
			throw Abort(.badRequest, reason: "No user ID in request.")
		}
		guard let _ = try await User.find(unmutedUserID, on: req.db) else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		guard let requestingUser = try await User.find(requester.userID, on: req.db) else {
			throw Abort(.internalServerError, reason: "User not found in db, but present in cache")
		}
		if requestingUser.mutedUserIDs.contains(unmutedUserID) {
			requestingUser.mutedUserIDs.removeAll { $0 == unmutedUserID }
			try await requestingUser.save(on: req.db)
			try await req.userCache.updateUser(requester.userID)
		}
		return .noContent
	}

	// MARK: Favorites

	/// `GET /api/v3/users/favorites`
	///
	/// Returns a list of the user's currently favorited users.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of `UserHeader` containing the currently favorited users.
	func favoritesHandler(_ req: Request) async throws -> [UserHeader] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let favoriteUsers = try await UserFavorite.query(on: req.db).filter(\.$user.$id == cacheUser.userID).all()
		let favoriteUserIDs: [UUID] = favoriteUsers.map { $0.$favorite.id }
		return req.userCache.getHeaders(favoriteUserIDs).sorted { $0.username < $1.username }
	}

	/// `POST /api/v3/users/:user_ID/favorite`
	///
	/// Favorites the specified `User` for the current user. Favoriting is a way to short-list friends
	/// for easy retrieval when using various Twitarr features.
	///
	/// - Parameter userID: in URL path. The userID to favorite.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: 201 Created on success.
	func favoriteAddHandler(_ req: Request) async throws -> HTTPStatus {
		let requester = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(userIDParam.paramString), let favoriteUserID = UUID(parameter) else {
			throw Abort(.badRequest, reason: "No user ID in request.")
		}
		guard let _ = try await User.find(favoriteUserID, on: req.db) else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		if let _ = try await UserFavorite.query(on: req.db).filter(\.$user.$id == requester.userID)
			.filter(\.$favorite.$id == favoriteUserID).first()
		{
			return .created
		}
		try await UserFavorite(userID: requester.userID, favoriteUserID: favoriteUserID).create(on: req.db)
		return .created
	}

	/// `POST /api/v3/users/:user_ID/unfavorite`
	///
	/// Removes a favorite of the specified `User` by the current user.
	///
	/// - Parameter userID: in URL path. The user to unfavorite.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: 204 No Content on success.
	func favoriteRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let requester = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(userIDParam.paramString), let favoriteUserID = UUID(parameter) else {
			throw Abort(.badRequest, reason: "No user ID in request.")
		}
		guard let _ = try await User.find(favoriteUserID, on: req.db) else {
			throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
		}
		if let userFavorite = try await UserFavorite.query(on: req.db).filter(\.$user.$id == requester.userID)
			.filter(\.$favorite.$id == favoriteUserID).first()
		{
			try await userFavorite.delete(on: req.db)
		}
		return .noContent
	}

	// MARK: - User Role Management
	/// `GET /api/v3/forum/userrole/:user_role`
	///
	///  Returns a list of all users that have the given role. Currently, caller must have the `shutternautmanager` role to call this, and can only
	///  query the `shutternaut` role.
	///
	/// - Throws: badRequest if the caller isn't a shutternaut manager, or the user role param isn't `shutternaut`.
	/// - Returns: Array of `UserHeader`. Array may be empty if nobody has this role yet.
	func getUsersWithRole(_ req: Request) async throws -> [UserHeader] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.userRoles.contains(.shutternautmanager) else {
			throw Abort(.badRequest, reason: "User cannot set any roles")
		}
		guard let roleString = req.parameters.get(userRoleParam.paramString) else {
			throw Abort(.badRequest, reason: "No UserRoleType found in request.")
		}
		let role = try UserRoleType(fromAPIString: roleString)
		guard role == .shutternaut else {
			throw Abort(.badRequest, reason: "User cannot manage the \(roleString) role")
		}
		let userIDsWithRole = try await User.query(on: req.db).join(UserRole.self, on: \User.$id == \UserRole.$user.$id)
			.filter(UserRole.self, \.$role == role).all(\.$id)
		return req.userCache.getHeaders(userIDsWithRole)
	}

	/// `POST /api/v3/forum/userrole/:user_role/addrole/:user_id`
	///
	/// Adds the given role to the given user's role list. Currently, caller must have the `shutternautmanager` role to call this, and can only
	/// give a user the `shutternaut` role.
	///
	/// - Throws: badRequest if the target user already has the role, or if the caller role/role being set are invalid.
	/// - Returns: 200 OK if the user now has the given role.
	func addRoleForUser(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.userRoles.contains(.shutternautmanager) else {
			throw Abort(.badRequest, reason: "User cannot set any roles")
		}
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		guard let userRoleString = req.parameters.get(userRoleParam.paramString) else {
			throw Abort(.badRequest, reason: "No UserRoleType found in request.")
		}
		let targetUserID = try targetUser.requireID()
		let role = try UserRoleType(fromAPIString: userRoleString)
		guard role == .shutternaut else {
			throw Abort(.badRequest, reason: "User cannot manage the \(userRoleString) role")
		}
		if let _ = try await UserRole.query(on: req.db).filter(\.$role == role).filter(\.$user.$id == targetUserID)
			.first()
		{
			throw Abort(.badRequest, reason: "User \(targetUser.username) already has role of \(role.label)")
		}
		try await UserRole(user: targetUserID, role: role).create(on: req.db)
		try await req.userCache.updateUser(targetUserID)
		return .ok
	}

	/// `POST /api/v3/admin/userrole/:user_role/removerole/:user_id`
	///
	/// Removes the given role from the target user's role list. Currently, caller must have the `shutternautmanager` role to call this, and can only
	/// remove the `shutternaut` role from a user's role list.
	///
	/// - Throws: badRequest if the target user isn't a Shutternaut Manager, the role being set isn't Shutternaut. Does not error if the target user already doesn't have the role.
	/// - Returns: 200 OK if the user was demoted successfully.
	func removeRoleForUser(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.userRoles.contains(.shutternautmanager) else {
			throw Abort(.badRequest, reason: "User cannot set any roles")
		}
		guard let userRoleString = req.parameters.get(userRoleParam.paramString) else {
			throw Abort(.badRequest, reason: "No UserRoleType found in request.")
		}
		let role = try UserRoleType(fromAPIString: userRoleString)
		guard role == .shutternaut else {
			throw Abort(.badRequest, reason: "User cannot manage the \(userRoleString) role")
		}
		guard let targetUserIDStr = req.parameters.get(userIDParam.paramString),
			let targetUserID = UUID(targetUserIDStr)
		else {
			throw Abort(.badRequest, reason: "Missing user ID parameter.")
		}
		try await UserRole.query(on: req.db).filter(\.$role == role).filter(\.$user.$id == targetUserID).delete()
		try await req.userCache.updateUser(targetUserID)
		return .ok
	}

	// MARK: - Helper Functions

	/// Updates the cache values for all accounts involved in a block removal. The currently
	/// blocked user and any associated accounts are removed from all blocking user's associated
	/// accounts' blocks caches, and vice versa.
	///
	/// - Parameters:
	///   - requester: The `User` removing the block.
	///   - user: The `User` currently being blocked.
	///   - req:The incoming `Request`, which provides the `EventLoop` on which this must run.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: Void.
	func removeBlockFromCache(by requester: User, of blockedUser: User, on req: Request) async throws {
		// get all involved IDs. We don't need to filter out mod accts, as Redis `srem` on them should no-op.
		let requesterIDs = try await requester.allAccountIDs(on: req.db)
		let unblockeeIDs = try await blockedUser.allAccountIDs(on: req.db)
		guard let unblockParentID = unblockeeIDs.first,
			let unblockParent = try await User.find(unblockParentID, on: req.db)
		else {
			return
		}
		// If the person we're unblocking has somehow blocked *us*, don't actually remove the
		// Redis blocks, but do still update the Barrel.
		if !Set(unblockParent.blockedUserIDs).isDisjoint(with: requesterIDs) {
			return
		}
		try await withThrowingTaskGroup(of: Void.self) { group in
			for ruuid in requesterIDs {
				_ = try await req.redis.removeBlockedUsers(unblockeeIDs, blockedBy: ruuid)
			}
			for buuid in unblockeeIDs {
				_ = try await req.redis.removeBlockedUsers(requesterIDs, blockedBy: buuid)
			}
			// I believe this line is required to let subtasks propagate thrown errors by rethrowing.
			for try await _ in group {}
		}
		try await req.userCache.updateUsers(requesterIDs + unblockeeIDs)
	}

	/// Updates the cache values for all accounts involved in a block. Blocked user and any
	/// associated accounts are added to all blocking user's associated accounts' blocks caches,
	/// and vice versa.
	///
	/// - Parameters:
	///   - requester: The `User` requesting the block.
	///   - user: The `User` being blocked.
	///   - req:The incoming `Request`, which provides the `EventLoop` on which this must run.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: Void.
	func addBlockToCache(requestedBy requester: User, blocking blockedUserID: UUID, on req: Request) async throws {
		// get all involved IDs
		guard let blockedUser = try await User.find(blockedUserID, on: req.db) else {
			throw Abort(.internalServerError, reason: "User not found")
		}
		let requesterUsers = try await requester.allAccounts(on: req.db)
		let blockedUsers = try await blockedUser.allAccounts(on: req.db)
		// Relies on the fact that allAccounts returns parent acct in position 0
		guard !requesterUsers.isEmpty, !blockedUsers.isEmpty,
			try requesterUsers[0].requireID() != blockedUsers[0].requireID()
		else {
			throw Abort(.badRequest, reason: "You cannot block your own alt accounts.")
		}
		let nonModRequesters = try requesterUsers.compactMap {
			try $0.accessLevel.hasAccess(.moderator) ? nil : $0.requireID()
		}
		let nonModBlocked = try blockedUsers.compactMap {
			try $0.accessLevel.hasAccess(.moderator) ? nil : $0.requireID()
		}
		try await withThrowingTaskGroup(of: Void.self) { group in
			nonModRequesters.forEach { ruuid in
				group.addTask { try await req.redis.addBlockedUsers(nonModBlocked, blockedBy: ruuid) }
			}
			nonModBlocked.forEach { buuid in
				group.addTask { try await req.redis.addBlockedUsers(nonModRequesters, blockedBy: buuid) }
			}
			for try await _ in group {}
		}
		return try await req.userCache.updateUsers(nonModRequesters + nonModBlocked)
	}
}

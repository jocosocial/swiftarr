import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis
import RediStack

/// The collection of `/api/v3/user/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct UsersController: APIRouteCollection {
        
    /// Required. Registers routes to the incoming router.
    func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/users endpoints
		let usersRoutes = app.grouped("api", "v3", "users")
				
		// endpoints available only when logged in
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: usersRoutes)
		tokenCacheAuthGroup.get("find", ":userSearchString", use: findHandler)
		tokenCacheAuthGroup.get(userIDParam, use: headerHandler)
		tokenCacheAuthGroup.get("match", "allnames", searchStringParam, use: matchAllNamesHandler)
		tokenCacheAuthGroup.get("match", "username", searchStringParam, use: matchUsernameHandler)
		tokenCacheAuthGroup.get(userIDParam, "profile", use: profileHandler)

		let tokenAuthGroup = addTokenAuthGroup(to: usersRoutes)
		tokenAuthGroup.post(userIDParam, "report", use: reportHandler)
		tokenAuthGroup.post(userIDParam, "block", use: blockHandler)
		tokenAuthGroup.post(userIDParam, "unblock", use: unblockHandler)
		tokenAuthGroup.post(userIDParam, "mute", use: muteHandler)
		tokenAuthGroup.post(userIDParam, "unmute", use: unmuteHandler)
		tokenAuthGroup.post(userIDParam, "note", use: noteCreateHandler)
		tokenAuthGroup.post(userIDParam, "note", "delete", use: noteDeleteHandler)
		tokenAuthGroup.delete(userIDParam, "note", use: noteDeleteHandler)
		tokenAuthGroup.get(userIDParam, "note", use: noteHandler)
    }
        
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `GET /api/v3/users/find/STRING`
    ///
    /// Retrieves a user's <doc:UserHeader> using either an ID (UUID string) or a username.
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
    /// - Returns: <doc:UserHeader> containing the user's ID, username, displayName and userImage.
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
            
    /// `GET /api/v3/users/ID`
    ///
    /// Retrieves the specified user's <doc:UserHeader> info.
    ///
    /// This endpoint provides one-off retrieval of the user information appropriate for
    /// a header on posted content – the user's ID, current generated `.displayedName`, and
    /// filename of their current profile image.
    ///
    /// For bulk data retrieval, see the `ClientController` endpoints.
    ///
    /// - Parameter userID: in URL path. The userID to search for.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:UserHeader> containing the user's ID, `.displayedName` and profile image filename.
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
    /// Retrieves the specified user's profile, as a <doc:ProfilePublicData> object.
	///
    /// - Parameter userID: in URL path. The userID to search for.
    /// - Throws: 404 error if the profile is not available. A 5xx response should be reported
    ///   as a likely bug, please and thank you.
    /// - Returns: <doc:ProfilePublicData> containing the displayable properties of the specified
    ///   user's profile.
    func profileHandler(_ req: Request) throws -> EventLoopFuture<ProfilePublicData> {
        let requester = try req.auth.require(UserCacheData.self)
        return User.findFromParameter(userIDParam, on: req).throwingFlatMap { profiledUser in
			// 404 if blocked
			if requester.getBlocks().contains(try profiledUser.requireID()) {
				throw Abort(.notFound, reason: "profile is not available")
			}
			// a .banned profile is only available to .moderator or above
			if profiledUser.accessLevel == .banned && !requester.accessLevel.hasAccess(.moderator) {
				throw Abort(.notFound, reason: "profile is not available")
			}
			// Profile hidden if user quarantined and requester not mod, or if requester is banned.
			var publicProfile = try ProfilePublicData(user: profiledUser, note: nil, requesterAccessLevel: requester.accessLevel)
			// include UserNote if any, then return
			return try UserNote.query(on: req.db).filter(\.$author.$id == requester.userID)
					.filter(\.$noteSubject.$id == profiledUser.requireID()).first().map { note in
				if let note = note {
					publicProfile.note = note.note
				}
				return publicProfile
			}
		}
    }
        
    /// `POST /api/v3/users/ID/block`
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
    func blockHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let requester = try req.auth.require(User.self)
        let requesterParentID = try requester.parentAccountID()
		// get block barrel for the requester's parent account
        let blockBarrel = Barrel.query(on: req.db)
					.filter(\.$ownerID == requesterParentID)
					.filter(\.$barrelType == .userBlock)
					.first()
					.unwrap(or: Abort(.internalServerError, reason: "userBlock barrel not found"))
        return User.findFromParameter(userIDParam, on: req).and(blockBarrel).throwingFlatMap { (user, barrel) in
        	// This guard only applies to *directly* blocking a moderator's Mod account. 
        	guard user.accessLevel < .moderator else {
        		throw Abort(.badRequest, reason: "Cannot block accounts of moderators, THO, or admins")
        	}
        	let userIDToBlock = try user.requireID()
        	guard try userIDToBlock != requester.requireID() else {
        		throw Abort(.badRequest, reason: "You cannot block yourself.")
        	} 
        	if barrel.modelUUIDs.contains(userIDToBlock) {
        		return req.eventLoop.future(.ok)
        	}
			// add blocked user to barrel
			barrel.modelUUIDs.append(userIDToBlock)
			return try self.setBlocksCache(by: requester, of: user, on: req).flatMap {
				return barrel.save(on: req.db).transform(to: .created)
			}
		}
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
    /// - Parameter STRING: in URL path. The search string to use. Must be at least 2 characters long.
    /// - Throws: 403 error if the search term is not permitted.
    /// - Returns: An array of <doc:UserHeader> values of all matching users.
    func matchAllNamesHandler(_ req: Request) throws -> EventLoopFuture<[UserHeader]> {
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
        // remove blocks from results
		return User.query(on: req.db)
				.filter(\.$userSearch, .custom("ILIKE"), "%\(search)%")
				.filter(\.$id !~ requester.getBlocks())
				.sort(\.$username, .ascending)
				.range(0..<10)
				.all()
				.flatMapThrowing { (profiles) in
			// return as UserSearch
			return try profiles.map { try UserHeader(user: $0) }
		}
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
    func matchUsernameHandler(_ req: Request) throws -> EventLoopFuture<[String]> {
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
		return User.query(on: req.db)
				.filter(\.$username, .custom("ILIKE"), "%\(search)%")
				.filter(\.$id !~ requester.getBlocks())
				.sort(\.$username, .ascending)
				.all()
				.map { (users) in
			// return @username only
			return users.map { "@\($0.username)" }
		}
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
    func muteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
		guard let parameter = req.parameters.get(userIDParam.paramString), let userID = UUID(parameter) else {
            throw Abort(.badRequest, reason: "No user ID in request.")
        }
		return User.find(userID, on: req.db)
				.unwrap(or: Abort(.notFound, reason: "no user found for identifier '\(parameter)'"))
				.flatMap { (user) in
			// get requester mute barrel
			return Barrel.query(on: req.db)
					.filter(\.$ownerID == requesterID)
					.filter(\.$barrelType == .userMute)
					.first()
					.unwrap(or: Abort(.internalServerError, reason: "userMute barrel not found"))
					.flatMap { (barrel) in
				// add to barrel
				barrel.modelUUIDs.append(userID)
				return barrel.save(on: req.db).flatMap { _ in
					// update cache, return 201
					return req.userCache.updateUser(requesterID).transform(to: .created)
				}
			}
		}
    }

    /// `POST /api/v3/users/ID/note`
    ///
    /// Saves a `UserNote` associated with the specified user and the current user.
	///
    /// - Parameter userID: in URL path. The user to associate with the note.
    /// - Parameter requestBody: <doc:NoteCreateData> struct containing the text of the note.
    /// - Throws: 400 error if the profile is a banned user's. A 5xx response should be reported as a likely bug, please and
    ///   thank you.
    /// - Returns: <doc:NoteData> containing the newly created note.
    func noteCreateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        // FIXME: account for banned user
        let requester = try req.auth.require(User.self)
		let data = try ValidatingJSONDecoder().decode(NoteCreateData.self, fromBodyOf: req)
        return User.findFromParameter(userIDParam, on: req) .throwingFlatMap { targetUser in
            // profile shouldn't be visible, but just in case
            guard targetUser.accessLevel != .banned else {
                throw Abort(.badRequest, reason: "notes are unavailable for profile")
            }
			// check for existing note
			return try requester.$notes.query(on: req.db)
					.filter(\.$noteSubject.$id == targetUser.requireID())
					.first()
					.throwingFlatMap { (existingNote) in
				let note = try existingNote ?? UserNote(author: requester, subject: targetUser, note: data.note)
				note.note = data.note
				// return note's data with 201 response
				return note.save(on: req.db).throwingFlatMap { _ in
					let createdNoteData = try NoteData(note: note, targetUser: targetUser)
					return createdNoteData.encodeResponse(status: .created, for: req)
				}
			}
		}
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
    func noteDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        // FIXME: account for blocks, banned user
        let requester = try req.auth.require(User.self)
        return User.findFromParameter(userIDParam, on: req).addModelID().flatMap { (targetUser, targetUserID) in
			// delete note if found
			return requester.$notes.query(on: req.db)
					.filter(\.$noteSubject.$id == targetUserID)
					.first()
					.unwrap(or: Abort(.notFound, reason: "no existing note found"))
					.flatMap { (note) in
				// force true delete
				return note.delete(force: true, on: req.db).transform(to: .noContent)
			}
		}
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
    /// - Returns: <doc:NoteEditData> containing the note's ID and text.
    func noteHandler(_ req: Request) throws -> EventLoopFuture<NoteData> {
        // FIXME: account for blocks, banned user
        let requester = try req.auth.require(User.self)
		guard let parameter = req.parameters.get(userIDParam.paramString), let targetUserID = UUID(parameter) else {
            throw Abort(.badRequest, reason: "No user ID in request.")
        }
		return requester.$notes.query(on: req.db)
				.filter(\.$noteSubject.$id == targetUserID)
				.with(\.$noteSubject)
				.first()
				.unwrap(or: Abort(.badRequest, reason: "no existing note found"))
				.flatMapThrowing { (note) in
			return try NoteData(note: note, targetUser: note.noteSubject)
		}
    }
    
    /// `POST /api/v3/users/ID/report`
    ///
    /// Creates a `Report` regarding the specified user's profile, either the text fields or the avatar image.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   send an empty string in the `.message` field.
    ///
    /// - Parameter requestBody: <doc:ReportData> containing an optional accompanying message
    /// - Returns: 201 Created on success.
    func reportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let submitter = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)        
		return User.findFromParameter(userIDParam, on: req).throwingFlatMap { reportedUser in
        	return try reportedUser.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
		}
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
    func unblockHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let requester = try req.auth.require(User.self)
        let requesterParentID = try requester.parentAccountID()
		// get block barrel for the requester's parent account
        let blockBarrelFuture = Barrel.query(on: req.db)
					.filter(\.$ownerID == requesterParentID)
					.filter(\.$barrelType == .userBlock)
					.first()
					.unwrap(or: Abort(.internalServerError, reason: "userBlock barrel not found"))
        return User.findFromParameter(userIDParam, on: req).and(blockBarrelFuture).throwingFlatMap { (user, barrel) in
			// remove user from barrel
        	let userIDToUnblock = try user.requireID()
			guard let index = barrel.modelUUIDs.firstIndex(of: userIDToUnblock) else {
				throw Abort(.badRequest, reason: "user not found in block list")
			}
			barrel.modelUUIDs.remove(at: index)
			return barrel.save(on: req.db).flatMap { (_) in
				// update cache and return 204
				return self.removeBlockFromCache(by: requester, of: user, on: req).transform(to: .noContent)
			}
		}
    }
    
    /// `POST /api/v3/users/ID/unmute`
    ///
    /// Removes a mute of the specified `User` by the current user.
    ///
    /// - Parameter userID: in URL path. The user to unmute.
    /// - Throws: 400 error if the specified user was not currently muted. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func unmuteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let requester = try req.auth.require(User.self)
        let requesterID = try requester.requireID()
  		guard let parameter = req.parameters.get(userIDParam.paramString), let userID = UUID(parameter) else {
            throw Abort(.badRequest, reason: "No user ID in request.")
        }
        return User.find(userID, on: req.db)
				.unwrap(or: Abort(.notFound, reason: "no user found for identifier '\(parameter)'"))
				.flatMap { (user) in
            // get requester mute barrel
            return Barrel.query(on: req.db)
					.filter(\.$ownerID == requesterID)
					.filter(\.$barrelType == .userMute)
					.first()
					.unwrap(or: Abort(.internalServerError, reason: "userMute barrel not found"))
					.flatMap { (barrel) in
				// remove from barrel
				guard let index = barrel.modelUUIDs.firstIndex(of: userID) else {
					return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "user not found in mute list"))
				}
				barrel.modelUUIDs.remove(at: index)
				return barrel.save(on: req.db).flatMap { (_) in
					// update cache, return 204
					return req.userCache.updateUser(requesterID).transform(to: .noContent)
				}
            }
        }
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
    func removeBlockFromCache(by requester: User, of user: User, on req: Request) -> EventLoopFuture<Void> {
        // get all involved IDs. We don't need to filter out mod accts, as Redis `srem` on them should no-op.
        let requesterFuture = requester.allAccountIDs(on: req)
        let unblockFuture = user.allAccountIDs(on: req)
        return requesterFuture.and(unblockFuture).flatMap { (ruuids, buuids) in
			var futures: [EventLoopFuture<Int>] = []
        	ruuids.forEach { ruuid in
				futures.append(req.redis.srem(buuids, from: "rblocks:\(ruuid)"))
        	}
        	buuids.forEach { buuid in
				futures.append(req.redis.srem(ruuids, from: "rblocks:\(buuid)"))
        	}
			return futures.flatten(on: req.eventLoop).flatMap { (_) in
				return req.userCache.updateUsers(ruuids)
						.and(req.userCache.updateUsers(buuids))
						.transform(to: ())
			}
        }
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
    func setBlocksCache(by requester: User, of user: User, on req: Request) throws -> EventLoopFuture<Void> {
        // get all involved IDs
        let requesterFuture = requester.allAccounts(on: req.db)
        let blockedFuture = user.allAccounts(on: req.db)
        return requesterFuture.and(blockedFuture).throwingFlatMap { (requesterUsers, blockedUsers) in
        	// Relies on the fact that allAccounts returns parent acct in position 0
        	guard !requesterUsers.isEmpty, !blockedUsers.isEmpty, try requesterUsers[0].requireID() != blockedUsers[0].requireID() else {
        		throw Abort(.badRequest, reason: "You cannot block your own alt accounts.")
        	}
        	let nonModRequesters = try requesterUsers.compactMap { try $0.accessLevel.hasAccess(.moderator) ? nil : $0.requireID() }
        	let nonModBlocked = try blockedUsers.compactMap { try $0.accessLevel.hasAccess(.moderator) ? nil : $0.requireID() }
			var futures: [EventLoopFuture<Int>] = []
        	nonModRequesters.forEach { ruuid in
				futures.append(req.redis.sadd(nonModBlocked, to: "rblocks:\(ruuid)"))
        	}
        	nonModBlocked.forEach { buuid in
				futures.append(req.redis.sadd(nonModRequesters, to: "rblocks:\(buuid)"))
        	}
			return futures.flatten(on: req.eventLoop).flatMap { (_) in
				return req.userCache.updateUsers(nonModRequesters)
						.and(req.userCache.updateUsers(nonModBlocked))
						.transform(to: ())
			}
		}
	}
}

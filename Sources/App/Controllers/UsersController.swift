import Vapor
import Crypto
import FluentSQL
import Redis

/// The collection of `/api/v3/user/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct UsersController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/users endpoints
        let usersRoutes = router.grouped("api", "v3", "users")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let basicAuthGroup = usersRoutes.grouped([basicAuthMiddleware, guardAuthMiddleware])
        let sharedAuthGroup = usersRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = usersRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        sharedAuthGroup.get("find", String.parameter, use: findHandler)
        sharedAuthGroup.get(User.parameter, "header", use: headerHandler)
        sharedAuthGroup.get(User.parameter, "profile", use: profileHandler)
        sharedAuthGroup.get(User.parameter, use: userHandler)

        // endpoints available only when logged in
        tokenAuthGroup.post(User.parameter, "block", use: blockHandler)
        tokenAuthGroup.get("match", "allnames", String.parameter, use: matchAllNamesHandler)
        tokenAuthGroup.get("match", "username", String.parameter, use: matchUsernameHandler)
        tokenAuthGroup.post(User.parameter, "mute", use: muteHandler)
        tokenAuthGroup.post(NoteCreateData.self, at: User.parameter, "note", use: noteCreateHandler)
        tokenAuthGroup.post(User.parameter, "note", "delete", use: noteDeleteHandler)
        tokenAuthGroup.get(User.parameter, "note", use: noteHandler)
        tokenAuthGroup.post(User.parameter, "unblock", use: unblockHandler)
        tokenAuthGroup.post(User.parameter, "unmute", use: unmuteHandler)
    }
    
    // MARK: - Open Access Handlers
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/users/find/STRING`
    ///
    /// Retrieves a user's `UserInfo` using either an ID (UUID string) or a username.
    ///
    /// This endpoint is of limited utility, but is included for the case of obtaining a
    /// user's ID from a username. If you have an ID and want the associated username, use
    /// the more efficient `/api/v3/users/ID` endpoint instead.
    ///
    /// - Note: Because a username can be changed, there is no guarantee that a once-valid
    ///   username will result in a successful return, even though the User itself does
    ///   exist.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 404 error if no match is found.
    /// - Returns: `UserInfo` containing the user's ID, username and timestamp of last
    ///   profile update.
    func findHandler(_ req: Request) throws -> Future<UserInfo> {
        // FIXME: account for blocks
//        let requester = try req.requireAuthenticated(User.self)
        let parameter = try req.parameters.next(String.self)
        // try converting to UUID
        let userID = UUID(uuidString: parameter)
        return UserProfile.query(on: req).group(.or) {
            (or) in
            // search ID if a UUID
            if let userID = userID {
                or.filter(\.userID == userID)
            }
            // search as username
            or.filter(\.username == parameter)
            }.first()
            .unwrap(or: Abort(.notFound, reason: "no user found for identifier '\(parameter)'"))
            .map {
                (profile) in
                // return as UserInfo
                let userInfo = UserInfo(
                    userID: profile.userID,
                    username: profile.username,
                    updatedAt: profile.updatedAt ?? Date()
                )
                return userInfo
        }
    }
    
    /// `GET /api/v3/users/ID/header`
    ///
    /// Retrieves the specified user's `UserHeader` info.
    ///
    /// This endpoint provides one-off retrieval of the user information appropriate for
    /// a header on posted content – the user's ID, current generated `.displayedName`, and
    /// filename of their current profile image.
    ///
    /// For bulk data retrieval, see the `ClientController` endpoints.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `UserHeader` containing the user's ID, `.displayedName` and profile
    ///   image filename.
    func headerHandler(_ req: Request) throws -> Future<UserHeader> {
        // FIXME: account for blocks
//        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            return try user.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found"))
                .map {
                    (profile) in
                    // return UserHeader
                    return try profile.convertToHeader()
            }
        }
    }
    
    /// `GET /api/v3/users/ID/profile`
    ///
    /// Retrieves the specified user's profile, as a `UserProfile.Public` object.
    ///
    /// This endpoint can be reached with either Basic or Bearer authenticaton. If using Basic
    /// (requesting user is *not* logged in), the data returned may be a limited subset if the
    /// profile user's `.limitAccess` setting is `true`, and the `.message` field will contain
    /// text to inform the viewing user of that fact.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 404 error if the profile is not available. A 5xx response should be reported
    ///   as a likely bug, please and thank you.
    /// - Returns: `UserProfile.Public` containing the displayable properties of the specified
    ///   user's profile.
    func profileHandler(_ req: Request) throws -> Future<UserProfile.Public> {
        // FIXME: account for blocks
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // a .banned profile is only available to .moderator or above
            if user.accessLevel == .banned
                && requester.accessLevel.rawValue < UserAccessLevel.moderator.rawValue {
                throw Abort(.notFound, reason: "profile is not available")
            }
            // get profile and convert to .Public
            return try user.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found"))
                .flatMap {
                    (profile) in
                    let publicProfile = try profile.convertToPublic()
                    // if auth type is Basic, requester is not logged in, so hide info if
                    // `.limitAccess` is true or requester is .banned
                    if (req.http.headers.basicAuthorization != nil && profile.limitAccess)
                        || requester.accessLevel == .banned {
                        publicProfile.about = ""
                        publicProfile.email = ""
                        publicProfile.homeLocation = ""
                        publicProfile.message = "You must be logged in to view this user's Profile details."
                        publicProfile.preferredPronoun = ""
                        publicProfile.realName = ""
                        publicProfile.roomNumber = ""
                    }
                    // include UserNote if any, then return
                    return try requester.notes.query(on: req)
                        .filter(\.profileID == profile.requireID())
                        .first()
                        .map {
                            (note) in
                            if let note = note {
                                publicProfile.note = note.note
                            }
                            return publicProfile
                }
            }
        }
    }
    
    /// `GET /api/v3/users/ID`
    ///
    /// Retrieves the specified user's `UserInfo`.
    ///
    /// This endpoint provides one-off retrieval of a user's username and the timestamp of
    /// the last time their publicly viewable data was updated. It would typically be used to:
    ///
    ///  - obtain a username from an ID
    ///  - determine if a user's info has updated since it was last obtained (username change,
    ///    displayedName change, profile photo change, or any field on their profile)
    ///
    /// For bulk data retrieval, see the `ClientController` endpoints.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 404 error if no match is found.
    /// - Returns: `UserInfo` containing the user's ID, username and timestamp of last
    ///   profile update.
    func userHandler(_ req: Request) throws -> Future<UserInfo> {
        // FIXME: account for blocks
//        let requester = try req.authenticated(User.self)
        return try req.parameters.next(User.self).convertToInfo()        
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/users/ID/block`
    ///
    /// Blocks the specified `User`. The blocking user and any subaccounts will not be able
    /// to see posts from the blocked `User` or any of their associated subaccounts, and vice
    /// versa. This affects all forms of communication, public and private, as well as user
    /// searches.
    ///
    /// Only the specified user is added to the block list, so as not to explicitly expose the
    /// ownership of any other accounts the blocked user may be using. The blocking of any
    /// associated user accounts is handled under the hood.
    ///
    /// Users with an `.accessLevel` of `.moderator` or higher may not be blocked. A block
    /// applied to such accounts will be accepted, but is effectively a uni-directional block.
    /// That is, the blocking user will not see the blocked user, but the blocked privileged
    /// user will still see the blocking user throughout the public areas of the system, and
    /// their role accounts will still be visible to the blocking user.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: 201 Created on success.
    func blockHandler(_ req: Request) throws -> Future<HTTPStatus> {
        // FIXME: needs block processing
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get requester block barrel
            return try Barrel.query(on: req)
                .filter(\.ownerID == requester.requireID())
                .filter(\.barrelType == .userBlock)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "userBlock barrel not found"))
                .flatMap {
                    (barrel) in
                    // add and return 201
                    barrel.modelUUIDs.append(try user.requireID())
                    return barrel.save(on: req).transform(to: .created)
            }
        }
    }
    
    /// `GET /api/v3/users/match/allnames/STRING`
    ///
    /// Retrieves all `UserProfile.userSearch` values containing the specified substring,
    /// returning an array of precomposed `.userSearch` strings in `UserSearch` format.
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
    /// - Parameter req: he incoming request `Container`, provided automatically.
    /// - Throws: 403 error if the search term is not permitted.
    /// - Returns: `[UserSearch]` containing the ID and profile.userSearch string
    ///   values of all matching users.
    func matchAllNamesHandler(_ req: Request) throws -> Future<[UserSearch]> {
        // FIXME: account for blocks
        // let requester = try req.requireAuthenticated(User.self)
        var search = try req.parameters.next(String.self)
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        // trim and disallow "@" harvesting
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard search != "@", search != "(@" else {
            throw Abort(.forbidden, reason: "'\(search)' is not a permitted search string")
        }
        return UserProfile.query(on: req)
            .filter(\.userSearch, .ilike, "%\(search)%")
            .sort(\.username, .ascending)
            .all()
            .map {
                (profiles) in
                // return as UserSearch
                return try profiles.map { try $0.convertToSearch() }
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
    /// - Parameter req: he incoming request `Container`, provided automatically.
    /// - Returns: `[String]` containng all matching usernames as "@username" strings.
    func matchUsernameHandler(_ req: Request) throws -> Future<[String]> {
        // FIXME: account for blocks
        // let requester = try req.requireAuthenticated(User.self)
        var search = try req.parameters.next(String.self)
        // postgres "_" is wildcard, so escape for literal
        search = search.replacingOccurrences(of: "_", with: "\\_")
        return UserProfile.query(on: req)
            .filter(\.username, .ilike, "%\(search)%")
            .sort(\.username, .ascending)
            .all()
            .map {
                (profiles) in
                // return @username only
                return profiles.map { "@\($0.username)" }
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
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: 201 Created on success.
    func muteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get requester mute barrel
            return try Barrel.query(on: req)
                .filter(\.ownerID == requester.requireID())
                .filter(\.barrelType == .userMute)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "userMute barrel not found"))
                .flatMap {
                    (barrel) in
                    // add to barrel
                    barrel.modelUUIDs.append(try user.requireID())
                    return barrel.save(on: req).flatMap {
                        (savedBarrel) in
                        // update cache, return 201
                        let cache = try req.keyedCache(for: .redis)
                        let key = try "mutes:\(user.requireID())"
                        return cache.set(key, to: savedBarrel.modelUUIDs).transform(to: .created)
                    }
            }
        }
    }

    /// `POST /api/v3/users/ID/note`
    ///
    /// Creates a new `UserNote` associated with the specified user's profile and the current
    /// user.
    ///
    /// - Note: In order to support the editing of a note in contexts other than when
    ///   actively viewing a profile, the contents of `profile.note` cannot be used to determine
    ///   if there is an existing associated UserNote, since it is possible for a valid note to
    ///   contain no text at any given time. This means that a GET should be performed on this
    ///   endpoint prior to attempting a POST. If GET returns data, use `POST /api/v3/user/note`
    ///   to update the note instead of this endpoint.
    ///
    /// - Requires: `NoteCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `NoteCreateData` struct containing the text of the note.
    /// - Throws: 409 error if there is an existing note on the profile. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: `CreatedNoteData` containing the newly created note's ID and text.
    func noteCreateHandler(_ req: Request, data: NoteCreateData) throws -> Future<Response> {
        // FIXME: account for banned user
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get user profile
            return try user.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found"))
                .flatMap {
                    (profile) in
                    // check for existing note
                    return try requester.notes.query(on: req)
                        .filter(\.profileID == profile.requireID())
                        .first()
                        .flatMap {
                            (existingNote) in
                            guard existingNote == nil else {
                                throw Abort(.conflict, reason: "note already exists for this profile")
                            }
                            // create note
                            let note = try UserNote(
                                userID: requester.requireID(),
                                profileID: profile.requireID(),
                                note: data.note
                            )
                            // return note's data with 201 response
                            return note.save(on: req).map {
                                (savedNote) in
                                let createdNoteData = try CreatedNoteData(
                                    noteID: savedNote.requireID(),
                                    note: savedNote.note
                                )
                                let response = Response(http: HTTPResponse(status: .created), using: req)
                                try response.content.encode(createdNoteData)
                                return response
                            }
                    }
            }
        }
    }
    
    /// `POST /api/v3/users/ID/note/delete`
    ///
    /// Deletes an existing `UseerNote` associated with the specified user's profile and
    /// the current user.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 400 error if there is no existing note on the profile. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func noteDeleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        // FIXME: account for blocks, banned user
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get user profile
            return try user.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found, note not deleted"))
                .flatMap {
                    (profile) in
                    // delete note if found
                    return try requester.notes.query(on: req)
                        .filter(\.profileID == profile.requireID())
                        .first()
                        .unwrap(or: Abort(.notFound, reason: "no existing note found"))
                        .flatMap {
                            (note) in
                            // force true delete
                            return note.delete(force: true, on: req).transform(to: .noContent)
                    }
            }
        }
    }
        
    /// `GET /api/v3/users/ID/note`
    ///
    /// Retrieves an existing `UseerNote` associated with the specified user's profile and
    /// the current user.
    ///
    /// - Note: In order to support the editing of a note in contexts other than when
    ///   actively viewing a profile, the contents of `profile.note` cannot be used to determine
    ///   if there is an exiting associated UserNote, since it is possible for a valid note to
    ///   contain no text at any given time. Use this GET endpoint prior to attempting a POST
    ///   to it.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 400 error if there is no existing note on the profile. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: `UserNote.Edit` containing the note's ID and text.
    func noteHandler(_ req: Request) throws -> Future<UserNote.Edit> {
        // FIXME: account for blocks, banned user
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get user profile
            return try user.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found"))
                .flatMap {
                    (profile) in
                    // return note data if any
                    return try requester.notes.query(on: req)
                        .filter(\.profileID == profile.requireID())
                        .first()
                        .unwrap(or: Abort(.badRequest, reason: "no existing note found"))
                        .map {
                            (note) in
                            return try note.convertToEdit()
                    }
            }
        }
    }
    
    /// `POST /api/v3/users/ID/unblock`
    ///
    /// Removes a block of the specified `User` and all subaccounts by the current user and
    /// all associated accounts.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 400 error if the specified user was not currently blocked. A 5xx response
    ///   should be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func unblockHandler(_ req: Request) throws -> Future<HTTPStatus> {
        // FIXME: needs block processing
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get requester block barrel
            return try Barrel.query(on: req)
                .filter(\.ownerID == requester.requireID())
                .filter(\.barrelType == .userBlock)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "userBlock barrel not found"))
                .flatMap {
                    (barrel) in
                    // remove and return 204
                    guard let index = barrel.modelUUIDs.firstIndex(of: try user.requireID()) else {
                        throw Abort(.badRequest, reason: "user not found in block list")
                    }
                    barrel.modelUUIDs.remove(at: index)
                    return barrel.save(on: req).transform(to: .noContent)
            }
        }
    }
    
    /// `POST /api/v3/users/ID/unmute`
    ///
    /// Removes a mute of the specified `User` by the current user.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 400 error if the specified user was not currently muted. A 5xx response should
    ///   be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func unmuteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        // FIXME: needs mute processing
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get requester mute barrel
            return try Barrel.query(on: req)
                .filter(\.ownerID == requester.requireID())
                .filter(\.barrelType == .userMute)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "userMute barrel not found"))
                .flatMap {
                    (barrel) in
                    // remove and return 204
                    guard let index = barrel.modelUUIDs.firstIndex(of: try user.requireID()) else {
                        throw Abort(.badRequest, reason: "user not found in mute list")
                    }
                    barrel.modelUUIDs.remove(at: index)
                    return barrel.save(on: req).transform(to: .noContent)
            }
        }
    }
}

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
        tokenAuthGroup.get("match", "allnames", String.parameter, use: matchAllNamesHandler)
        tokenAuthGroup.get("match", "username", String.parameter, use: matchUsernameHandler)
        tokenAuthGroup.post(NoteCreateData.self, at: User.parameter, "note", use: noteCreateHandler)
        tokenAuthGroup.post(User.parameter, "note", "delete", use: noteDeleteHandler)
        tokenAuthGroup.get(User.parameter, "note", use: noteHandler)
        
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
        let user = try req.requireAuthenticated(User.self)
        return try user.profile.query(on: req)
            .first()
            .unwrap(or: Abort(.internalServerError, reason: "profile not found"))
            .map {
                (profile) in
                return try profile.convertToHeader()
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
        // get requested user
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
                    // if auth type is Basic, requestor is not logged in, so hide info if
                    // `.limitAccess` is true or requestor is .banned
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
        return try req.parameters.next(User.self).convertToInfo()        
    }
        
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
        
    /// `GET /api/v3/users/match/allnames/STRING`
    ///
    /// Retrieves all `UserProfile.userSearch` values containing the specified substring,
    /// returning an array of precomposed `.userSearch` strings in `UserProfile.Search` format.
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
    /// - Returns: `[UserProfile.Search]` containing the ID and profile.userSearch string
    ///   values of all matching users.
    func matchAllNamesHandler(_ req: Request) throws -> Future<[UserProfile.Search]> {
        // FIXME: account for blocks
        // let user = try req.requireAuthenticated(User.self)
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
        // let user = try req.requireAuthenticated(User.self)
        var search = try req.parameters.next(String.self)
        // postgres "_" is wildcard, so escape for literal
        search = search.replacingOccurrences(of: "_", with: "\\_")
        return UserProfile.query(on: req)
            .filter(\.username, .ilike, "%\(search)%")
            .sort(\.username, .ascending)
            .all()
            .map {
                (profiles) in
                return profiles.map { "@\($0.username)" }
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
        let user = try req.requireAuthenticated(User.self)
        // get profile's user
        return try req.parameters.next(User.self).flatMap {
            (profileUser) in
            // get their profile
            return try profileUser.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found"))
                .flatMap {
                    (profile) in
                    // check for existing note
                    return try user.notes.query(on: req)
                        .filter(\.profileID == profile.requireID())
                        .first()
                        .flatMap {
                            (existingNote) in
                            guard existingNote == nil else {
                                throw Abort(.conflict, reason: "note already exists for this profile")
                            }
                            // create note
                            let note = try UserNote(
                                userID: user.requireID(),
                                profileID: profile.requireID(),
                                note: data.note
                            )
                            // return note's data
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
        let user = try req.requireAuthenticated(User.self)
        // get profile's user
        return try req.parameters.next(User.self).flatMap {
            (profileUser) in
            // get their profile
            return try profileUser.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found, note not deleted"))
                .flatMap {
                    (profile) in
                    // delete note if found
                    return try user.notes.query(on: req)
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
        let user = try req.requireAuthenticated(User.self)
        // get profile's user
        return try req.parameters.next(User.self).flatMap {
            (profileUser) in
            // get their profile
            return try profileUser.profile.query(on: req)
                .first()
                .unwrap(or: Abort(.internalServerError, reason: "profile not found"))
                .flatMap {
                    (profile) in
                    // return note data if any
                    return try user.notes.query(on: req)
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

    // MARK: - Helper Functions
}

// MARK: - Helper Structs

/// Returned by `/api/v3/users/ID/note`.
///
/// See `UsersController.noteCreateHandler(_:data:)`.
struct CreatedNoteData: Content {
    /// The ID of the note.
    var noteID: UUID
    /// The text of the note.
    var note: String
}

/// Required by `/api/v3/users/ID/note` to create a `UserNote`.
///
/// See `UsersController.noteCreateHandler(_:data:)`.
struct NoteCreateData: Content {
    /// The text of the note.
    var note: String
}

/// Used to obtain a user's current header information (name and image) for attributed content.
///
/// Returned by:
/// * `GET /api/v3/users/ID/header`
/// * `GET /api/v3/client/user/headers/since/DATE`
///
/// See `UsersController.headerHandler(_:)`, `ClientController.userHeadersHandler(_:)`.
struct UserHeader: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's displayName + username.
    var displayedName: String
    /// The filename of the user's profile image.
    var userImage: String
}

/// Used to obtain user identity and whether any cached information may be stale.
///
/// Returned by `GET /api/v3/users/ID`,`GET /api/v3/users/find/STRING`,
/// `GET /api/v3/client/user/updates/since/DATE`.
///
/// See `UsersController.findHandler(_:)`, `UsersController.userHandler(_:)`,
/// `ClientController.userUpdatesHandler(_:)`.
struct UserInfo: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
    /// Timestamp of last update to the user's profile.
    var updatedAt: Date
}

/// Used to broad search for a user based on any of their name fields.
///
/// Returned by `GET /api/v3/users/match/allnames/STRING`, `GET /api/v3/client/usersearch`.
///
/// See `UsersController.matchAllNamesHandler(_:)`, `ClientController.userSearchHandler(_:)`.
struct UserSearch: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's composed displayName + username + realName.
    var userSearch: String
}

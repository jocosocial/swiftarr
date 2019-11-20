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
        sharedAuthGroup.get(User.parameter, "profile", use: profileHandler)
        sharedAuthGroup.get("find", String.parameter, use: findHandler)
        sharedAuthGroup.get(User.parameter, use: userHandler)

        // endpoints available only when logged in
        tokenAuthGroup.post(NoteCreateData.self, at: User.parameter, "note", use: noteCreateHandler)
        tokenAuthGroup.post(User.parameter, "note", "delete", use: noteDeleteHandler)
        tokenAuthGroup.get(User.parameter, "note", use: noteHandler)
        
    }
    
    // MARK: - Open Access Handlers
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in *or* out)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/users/find/STRING`
    ///
    /// Retrieves a user's .Public info using either an ID (UUID string) or a username.
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
    /// - Returns: The user's ID, username and timestamp of last info update.
    func findHandler(_ req: Request) throws -> Future<User.Public> {
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
            .map {
                (profile) in
                // unwrap timestamp if match found
                guard let profile = profile, let updatedAt = profile.updatedAt else {
                    throw Abort(.notFound, reason: "no user found for identifier '\(parameter)'")
                }
                // return as User.Public
                let userPublic = User.Public(
                    id: profile.userID,
                    username: profile.username,
                    updatedAt: updatedAt
                )
                return userPublic
        }
    }
    
    /// `GET /api/v3/users/ID/profile`
    ///
    /// Retrieves the user's own profile data for editing, as a `UserProfile.Edit` object.
    ///
    /// This endpoint can be reached with either Basic or Bearer authenticaton, so that a user
    /// can customize their profile even if they do not yet have their registration code.
    ///
    /// - Note: The `.username` and `.displayedName` properties of the returned object
    ///   are for display convenience only. A username must be changed using the
    ///   `POST /api/v3/user/username` endpoint. The displayedName property is generated from
    ///   the username and displayName values.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: A `UserProfile.Edit` object containing the editable properties of the
    ///   profile.
    func profileHandler(_ req: Request) throws -> Future<UserProfile.Public> {
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
            return try user.profile.query(on: req).first().flatMap {
                (profile) in
                guard let profile = profile, let profileID = profile.id else {
                    throw Abort(.internalServerError, reason: "profile not found")
                }
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
                    .filter(\.profileID == profileID)
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
    /// Retrieves the specified user's .Public info.
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
    /// - Returns: The user's ID, username and timestamp of last info update.
    func userHandler(_ req: Request) throws -> Future<User.Public> {
        return try req.parameters.next(User.self).convertToPublic()        
    }
        
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
        
    /// `POST /api/v3/users/ID/note`
    ///
    /// Creates a new `UseerNote` associated with the specified user's profile and the current
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
    /// - Returns: The newly created note's ID and text.
    func noteCreateHandler(_ req: Request, data: NoteCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // get profile's user
        return try req.parameters.next(User.self).flatMap {
            (profileUser) in
            // get their profile
            return try profileUser.profile.query(on: req).first().flatMap {
                (profile) in
                guard let profile = profile else {
                    throw Abort(.internalServerError, reason: "profile not found, note not created")
                }
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
        let user = try req.requireAuthenticated(User.self)
        // get profile's user
        return try req.parameters.next(User.self).flatMap {
            (profileUser) in
            // get their profile
            return try profileUser.profile.query(on: req).first().flatMap {
                (profile) in
                guard let profile = profile else {
                    throw Abort(.internalServerError, reason: "profile not found, note not deleted")
                }
                // delete note if found
                return try user.notes.query(on: req)
                    .filter(\.profileID == profile.requireID())
                    .first()
                    .flatMap {
                        (note) in
                        guard let note = note else {
                            throw Abort(.notFound, reason: "no existing note found")
                        }
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
    /// - Returns: The note's ID and text.
    func noteHandler(_ req: Request) throws -> Future<UserNote.Edit> {
        let user = try req.requireAuthenticated(User.self)
        // get profile's user
        return try req.parameters.next(User.self).flatMap {
            (profileUser) in
            // get their profile
            return try profileUser.profile.query(on: req).first().flatMap {
                (profile) in
                guard let profile = profile else {
                    throw Abort(.internalServerError, reason: "profile not found")
                }
                // return note data if any
                return try user.notes.query(on: req)
                    .filter(\.profileID == profile.requireID())
                    .first()
                    .map {
                        (note) in
                        guard let note = note else {
                            throw Abort(.badRequest, reason: "no existing note found")
                        }
                        return try note.convertToEdit()
                }
            }
        }
    }

    // MARK: - Helper Functions
}

// MARK: - Helper Structs

/// Returned by `UsersController.noteHandler(_:data:).`
struct CreatedNoteData: Content {
    /// The ID of the note.
    var noteID: UUID
    /// The text of the note.
    var note: String
}

/// Used by `UsersController.noteHandler(_:data:)` to create a `UserNote`.
struct NoteCreateData: Content {
    /// The text of the note.
    var note: String
}

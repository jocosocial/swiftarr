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

struct UserController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/user endpoints
        let userRoutes = router.grouped("api", "v3", "user")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let basicAuthGroup = userRoutes.grouped([basicAuthMiddleware, guardAuthMiddleware])
        let sharedAuthGroup = userRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = userRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        userRoutes.post(UserCreateData.self, at: "create", use: createHandler)
        
        // endpoints available only when not logged in
        basicAuthGroup.post(UserVerifyData.self, at: "verify", use: verifyHandler)
        
        // endpoints available whether logged in or out
        sharedAuthGroup.get("profile", use: profileHandler)
        sharedAuthGroup.post(UserProfileData.self, at: "profile", use: profileUpdateHander)
        sharedAuthGroup.get("whoami", use: whoamiHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.post(UserAddData.self, at: "add", use: addHandler)
        tokenAuthGroup.post(NoteUpdateData.self, at: "note", use: noteHandler)
        tokenAuthGroup.get("notes", use: notesHandler)
        tokenAuthGroup.post(UserPasswordData.self, at: "password", use: passwordHandler)
        tokenAuthGroup.post(UserUsernameData.self, at: "username", use: usernameHandler)
    }
    
    // MARK: - Open Access Handlers
    
    /// `POST /api/v3/user/create`
    ///
    /// Creates a new `User` account and its associated `UserProfile`. If either fail, neither
    /// is created, since we want to ensure that all accounts have profiles.
    ///
    /// A `CreatedUserData` structure is returned on success, containing the new user's ID,
    /// username and a generated recovery key.
    ///
    /// - Note: The `CreatedUserData.recoveryKey` is a random phrase used to recover an account
    ///   in the case of a forgotten password. While it can be stored by a client, that
    ///   essentially defeats its purpose (presumably the password would also already be
    ///   stored). The *intended client use* is that it is displayed to the user upon successful
    ///   creation, and the user is *encouraged to take a screenshot or write it down before
    ///   proceeding*.
    ///
    /// - Requires: `UserCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserCreateData` struct containing the user's desired username and password.
    /// - Throws: 409 errpr if the username is not available.
    /// - Returns: The newly created user's ID, username, and a recovery key string.
    func createHandler(_ req: Request, data: UserCreateData) throws -> Future<Response> {
        // see `UserCreateData.validations()`
        try data.validate()
        // check for existing username so we can return 409 Conflict status instead
        // of the default super-unfriendly 500 for unique constraint violation
        return User.query(on: req)
            .filter(\.username == data.username)
            .first()
            .flatMap {
                (existingUser) in
                // abort if name is already taken
                guard existingUser == nil else {
                    throw Abort(.conflict, reason: "username '\(data.username)' is not available")
                }
                
                // create recovery key
                var recoveryKey = ""
                _ = try UserController.generateRecoveryKey(on: req).map {
                    (resolvedKey) in
                    recoveryKey = resolvedKey
                }
                let normalizedKey = recoveryKey.lowercased().replacingOccurrences(of: " ", with: "")
                
                // create user
                let passwordHash = try BCrypt.hash(data.password)
                let recoveryHash = try BCrypt.hash(normalizedKey)
                let user = User(
                    username: data.username,
                    password: passwordHash,
                    recoveryKey: recoveryHash,
                    verification: nil,
                    parentID: nil,
                    accessLevel: .unverified
                )
                
                // wrap in a transaction to ensure each user has an associated profile
                // (creates both, or neither)
                return req.transaction(on: .psql) {
                    (connection) in
                    return user.save(on: connection).flatMap {
                        (savedUser) in
                        // create profile
                        let profile = try UserProfile(
                            userID: savedUser.requireID(),
                            username: savedUser.username
                        )
                        return profile.save(on: connection).map {
                            (savedProfile) in
                            // touch savedUser.profileUpdatedAt
                            guard let profileUpdatedAt = savedProfile.updatedAt else {
                                throw Abort(.internalServerError, reason: "profile has no timestamp")
                            }
                            savedUser.profileUpdatedAt = profileUpdatedAt
                            _ = savedUser.save(on: connection)
                            // return user data as .created
                            let createdUserData = try CreatedUserData(
                                userID: savedUser.requireID(),
                                username: savedUser.username,
                                recoveryKey: recoveryKey
                            )
                            let response = Response(http: HTTPResponse(status: .created), using: req)
                            try response.content.encode(createdUserData)
                            return response
                        }
                    }
                }
        }
    }
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    /// `POST /api/v3/user/verify`
    ///
    /// Changes a `User.accessLevel` from `.unverified` to `.verified` on successful submission
    /// of a registration code.
    ///
    /// - Requires: `UserVerifyData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserVerifyData` struct containing a registration code.
    /// - Throws: 400 error if the user is already verified or the registration code is not
    ///   a valid one. 409 error if the registration code has already been allocated to
    ///   another user.
    /// - Returns: HTTP status 200 on success.
    func verifyHandler(_ req: Request, data: UserVerifyData) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        // abort if user is already verified
        guard user.verification == nil else {
            throw Abort(.badRequest, reason: "user is already verified")
        }
        // see `UserVerifyData.validations()`
        try data.validate()
        let normalizedCode = data.verification.lowercased().replacingOccurrences(of: " ", with: "")
        return RegistrationCode.query(on: req)
            .filter(\.code == normalizedCode)
            .first()
            .flatMap {
                (registrationCode) in
                // abort if code not found
                guard let registrationCode = registrationCode else {
                    throw Abort(.badRequest, reason: "registration code not found")
                }
                // abort if code is already used
                guard registrationCode.userID == nil else {
                    throw Abort(.conflict, reason: "registration code has already been used")
                }
                // update models and return 200
                return req.transaction(on: .psql) {
                    (connection) in
                    // update registrationCode
                    registrationCode.userID = try user.requireID()
                    return registrationCode.save(on: connection).flatMap {
                        (_) in
                        // update user
                        user.accessLevel = .verified
                        user.verification = registrationCode.code
                        return user.save(on: connection).transform(to: .ok)
                    }
                }
        }
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in *or* out)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/user/profile`
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
    func profileHandler(_ req: Request) throws -> Future<UserProfile.Edit> {
        let user = try req.requireAuthenticated(User.self)
        // retrieve profile
        return try user.profile.query(on: req).first().map {
            (profile) in
            guard let profile = profile else {
                throw Abort(.internalServerError, reason: "profile not found")
            }
            // return .Edit properties only
            return profile.convertToEdit()
        }
    }
    
    /// `POST /api/v3/user/profile`
    ///
    /// Updates the user's profile.
    ///
    /// This endpoint can be reached with either Basic or Bearer authenticaton, so that a user
    /// can customize their profile even if they do not yet have their registration code.
    ///
    /// - Note: All fields of the `UserProfileData` structure being submitted **must** be
    ///   present and have values. While the properties of the profile itself are optional, the
    ///   submitted values all *replace* the existing propety values. Submitting a value of `""`
    ///   resets its respective profile property to `nil`.
    ///
    /// - Requires: `UserProfileData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserProfileData` struct containing the editable properties of the profile.
    /// - Throws: 403 error if the user is banned.
    /// - Returns: A`UserProfile.Edit` object containing the updated editable properties of
    ///   the profile.
    func profileUpdateHander(_ req: Request, data: UserProfileData) throws -> Future<UserProfile.Edit> {
        let user = try req.requireAuthenticated(User.self)
        // abort if banned, profile might even be deleted
        guard user.accessLevel != .banned else {
            throw Abort(.forbidden, reason: "profile cannot be edited")
        }
        // retrieve profile
        return try user.profile.query(on: req).first().flatMap {
            (profile) in
            guard let profile = profile else {
                throw Abort(.internalServerError, reason: "profile not found")
            }
            // update fields, nil if no value supplied
            profile.about = data.about.isEmpty ? nil : data.about
            profile.displayName = data.displayName.isEmpty ? nil : data.displayName
            profile.email = data.email.isEmpty ? nil : data.email
            profile.homeLocation = data.homeLocation.isEmpty ? nil : data.homeLocation
            profile.message = data.message.isEmpty ? nil : data.message
            profile.preferredPronoun = data.message.isEmpty ? nil : data.preferredPronoun
            profile.realName = data.realName.isEmpty ? nil : data.realName
            profile.roomNumber = data.roomNumber.isEmpty ? nil : data.roomNumber
            profile.limitAccess = data.limitAccess
            return profile.save(on: req).flatMap {
                (savedProfile) in
                // touch savedUser.profileUpdatedAt
                guard let profileUpdatedAt = savedProfile.updatedAt else {
                    throw Abort(.internalServerError, reason: "profile has no timestamp")
                }
                user.profileUpdatedAt = profileUpdatedAt
                _ = user.save(on: req)
                // record update for accountability
                let profileEdit = try ProfileEdit(
                    profileID: profile.requireID(),
                    profileData: data,
                    profileImage: nil
                )
                return profileEdit.save(on: req).map {
                    (_) in
                    // return .Edit properties of updated profile
                    return savedProfile.convertToEdit()
                }
            }
        }
    }
    
    /// `GET /api/v3/user/whoami`
    ///
    /// Returns the current user's `.id`, `.username` and whether they're currently logged in.
    ///
    /// This endpoint can be reached with either Basic or Bearer authenticaton, and might be
    /// useful in a multi-account environment to determine which account's credentials are
    /// currently being used.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Returns: The current user's ID and username.
    func whoamiHandler(_ req: Request) throws -> Future<CurrentUserData> {
        let user = try req.authenticated(User.self)
        // well, we have to unwrap somewhere
        guard let me = user else {
            throw Abort(.internalServerError, reason: "this is seriously not possible")
        }
        let currentUserData = try CurrentUserData(
            userID: me.requireID(),
            username: me.username,
            // if there's a BasicAuthorization header, not logged in
            isLoggedIn: req.http.headers.basicAuthorization != nil ? false : true
        )
        return req.future(currentUserData)
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/user/add`
    ///
    /// Adds a new `User` sub-account and its associated `UserProfile` to the current user.
    /// If either fail, neither is created, since we want to ensure that all accounts
    /// have profiles.
    ///
    /// An `AddedUserData` structure is returned on success, containing the new user's ID
    /// and username.
    ///
    /// - Note: API v3 supports a sub-account model, rather than the creation of individual
    ///   accounts for multiple identities in prior versions. A sub-account inherits its parent
    ///   user's `.accessLevel`, `.recoveryKey` and `.verification` values. Each `User`
    ///   requires use of its own Bearer Authentication token and must log in individually;
    ///   multiple accounts can all be simultaneously logged in.
    ///
    /// - Requires: `UserAddData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserAddData` struct containing the user's desired username and password.
    /// - Throws: 403 error if the user is banned or currently quarantined. 409 errpr if the
    ///   username is not available.
    /// - Returns: The newly created user's ID and username.
    func addHandler(_ req: Request, data: UserAddData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // see `UserAddData.validations()`
        try data.validate()
        // only upstanding citizens need apply
        guard user.accessLevel.rawValue >= UserAccessLevel.verified.rawValue else {
            throw Abort(.forbidden, reason: "user not currently permitted to create sub-account")
        }
        // check if existing username
        return User.query(on: req)
            .filter(\.username == data.username)
            .first()
            .flatMap {
                (existingUser) in
                guard existingUser == nil else {
                    throw Abort(.conflict, reason: "username '\(data.username)' is not available")
                }
                // if user has a parent, sub-account has samee, else this account is parent
                let parentID = user.parentID ?? user.id
                let passwordHash = try BCrypt.hash(data.password)
                // sub-account inherits .accessLevel, .recoveryKey and .verification
                let subAccount = User(
                    username: data.username,
                    password: passwordHash,
                    recoveryKey: user.recoveryKey,
                    verification: user.verification,
                    parentID: parentID,
                    accessLevel: user.accessLevel
                )
                // both, or neither
                return req.transaction(on: .psql) {
                    (connection) in
                    return subAccount.save(on: connection).flatMap {
                        (savedUser) in
                        // create profile
                        let profile = try UserProfile(
                            userID: savedUser.requireID(),
                            username: savedUser.username
                        )
                        return profile.save(on: connection).map {
                            (savedProfile) in
                            // touch savedUser.profileUpdatedAt
                            guard let profileUpdatedAt = savedProfile.updatedAt else {
                                throw Abort(.internalServerError, reason: "profile has no timestamp")
                            }
                            savedUser.profileUpdatedAt = profileUpdatedAt
                            _ = savedUser.save(on: connection)
                            // return user data as .created
                            let addedUserData = try AddedUserData(
                                userID: savedUser.requireID(),
                                username: savedUser.username
                            )
                            let response = Response(http: HTTPResponse(status: .created), using: req)
                            try response.content.encode(addedUserData)
                            return response
                        }
                    }
                }
        }
    }
    
    /// `POST /api/v3/user/note`
    ///
    /// Updates a `UserNote` with the supplied note text.
    ///
    /// - Requires: `NoteUpdateData` payload in HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `NoteUpdateData` struct containing the note's ID and updated text.
    /// - Throws: 403 if the note is not owned by the user. A 5xx response should be reported
    ///   as a likely bug, please and thank you.
    /// - Returns: The updated note as a `NoteData` object.
    func noteHandler(_ req: Request, data: NoteUpdateData) throws -> Future<NoteData> {
        let user = try req.requireAuthenticated(User.self)
        // retrieve note
        return UserNote.find(data.noteID, on: req).flatMap {
            (note) in
            // ensure it belongs to user
            guard let note = note, try note.userID == user.requireID() else {
                throw Abort(.unauthorized, reason: "note does not belong to user")
            }
            note.note = data.note
            return note.save(on: req).map {
                (savedNote) in
                // unwrap Date? fields
                guard let createdAt = savedNote.createdAt,
                    let updatedAt = savedNote.updatedAt else {
                        throw Abort(.internalServerError, reason: "note has no timestamps")
                }
                // create NoteData
                var noteData = try NoteData(
                    noteID: note.requireID(),
                    createdAt: createdAt,
                    updataedAt: updatedAt,
                    profileID: savedNote.profileID,
                    profileUser: "",
                    note: savedNote.note
                )
                // .displayedName is probably best to send
                _ = savedNote.profile.query(on: req).first().map {
                    (profile) in
                    let publicProfile = try profile?.convertToPublic()
                    noteData.profileUser = publicProfile?.displayedName ?? "unknown (please report this bug)"
                }
                return noteData
            }
        }
    }
    
    /// `GET /api/v3/user/notes`
    ///
    /// Retrieves all `UserNote`s owned by the current user, as an array of `NoteData` objects.
    ///
    /// The `NoteData` object is intended to be display friendly, including fields for
    /// potential sorting, the ID of the profile which can be linked to, and the profile's user
    /// in the familiar .displayedName format. The .noteID is included as well to support
    /// editing of notes outside of a profile-viewing context.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: The user's notes as an array of `NoteData`, or an empty array if none exist.
    func notesHandler(_ req: Request) throws -> Future<[NoteData]> {
        let user = try req.requireAuthenticated(User.self)
        // FIXME: need to account for Blocks
        // fetch all notes
        return try user.notes.query(on: req).all().map {
            (notes) in
            // create array for return
            var notesData = [NoteData]()
            try notes.forEach {
                // unwrap Date? fields
                guard let createdAt = $0.createdAt,
                    let updatedAt = $0.updatedAt else {
                        throw Abort(.internalServerError, reason: "note has no timestamps")
                }
                // create NoteData
                var noteData = try NoteData(
                    noteID: $0.requireID(),
                    createdAt: createdAt,
                    updataedAt: updatedAt,
                    profileID: $0.profileID,
                    profileUser: "",
                    note: $0.note
                )
                // .displayedName is probably best to send
                _ = $0.profile.query(on: req).first().map {
                    (profile) in
                    let publicProfile = try profile?.convertToPublic()
                    noteData.profileUser = publicProfile?.displayedName ?? "unknown (please report this bug)"
                }
                notesData.append(noteData)
            }
            return notesData
        }
    }
    
    /// `POST /api/v3/user/password`
    ///
    /// Updates a user's password to the supplied value, encrypted.
    ///
    /// - Requires: `UserPasswordData` payload in the HTTP body.
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserPasswordData` struct containing the user's desired password.
    /// - Throws: 400 error if the supplied password is not at least 6 characters.
    /// - Returns: 201 Created on success.
    func passwordHandler(_ req: Request, data: UserPasswordData) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        // see `UserPasswordData.validations()`
        try data.validate()
        // encrypt, then update user
        let passwordHash = try BCrypt.hash(data.password)
        user.password = passwordHash
        return user.save(on: req).transform(to: .created)
    }
    
    /// `POST /api/v3/user/username`
    ///
    /// Changes a user's username to the supplied value, if possible. Also updates the
    /// username in the associated `UserProfile`.
    ///
    /// - Requires: `UserUsernameData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserUsernameData` containing the user's desired new username.
    /// - Throws: 409 errpr if the username is not available. A 5xx response should be reported
    ///   as a likely bug, please and thank you.
    /// - Returns: 201 Created on success.
    func usernameHandler(_ req: Request, data: UserUsernameData) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        // see `UserUsernameData.validations()`
        try data.validate()
        // check for existing username
        return User.query(on: req)
            .filter(\.username == data.username)
            .first()
            .flatMap {
                (existingUser) in
                // abort if name is already taken
                guard existingUser == nil else {
                    throw Abort(.conflict, reason: "username '\(data.username)' is not available")
                }
                // need to update profile too
                return try user.profile.query(on: req).first().flatMap {
                    (profile) in
                    guard let profile = profile else {
                        throw Abort(.internalServerError, reason: "user's profile not found")
                    }
                    user.username = data.username
                    profile.username = data.username
                    // update both, or neither
                    return req.transaction(on: .psql) {
                        (connection) in
                        return user.save(on: connection).flatMap {
                            (savedUser) in
                            return profile.save(on: connection).map {
                                (savedProfile) in
                                // touch savedUser.profileUpdatedAt
                                guard let profileUpdatedAt = savedProfile.updatedAt else {
                                    throw Abort(.internalServerError, reason: "profile has no timestamp")
                                }
                                savedUser.profileUpdatedAt = profileUpdatedAt
                                _ = savedUser.save(on: connection)
                                return .created
                            }
                        }
                    }
                }
        }
    }
    
    // MARK: - Helper Functions
    
    /// An array of words used to generate random phrases.
    static let words: [String] = [
        "aboriginal", "accept", "account", "acoustic", "adaptable", "adorable",
        "afternoon", "agreeable", "airport", "alive", "alluring", "amazing",
        "amused", "announce", "applause", "appreciate", "approve", "aquatic",
        "arithmetic", "aromatic", "arrive", "aspiring", "attractive", "aunt",
        "auspicious", "awake", "balance", "basin", "bat", "bath", "bed", "bee",
        "befitting", "believe", "beneficial", "best", "bikes", "birds", "black",
        "blue", "blush", "boat", "book", "bottle", "bouncy", "brains", "brass",
        "brave", "bravo", "breezy", "brown", "brunch", "bubble", "business",
        "cabbage", "cactus", "cake", "calm", "camera", "capable", "card",
        "caring", "cats", "cause", "celery", "cheerful", "cheese", "cherry",
        "chess", "chicken", "circle", "clean", "clover", "club", "coach",
        "collect", "colorful", "comfortable", "complete", "connect",
        "conscious", "cooperative", "cows", "crayon", "cuddly", "cute", "daily",
        "dance", "dapper", "dashing", "dazzling", "debonair", "decisive",
        "delicate", "delicious", "delight", "delightful", "design", "dinner",
        "dinosaurs", "discovery", "dock", "doggo", "donkey", "drawer", "dress",
        "drink", "drum", "dry", "duck", "dynamic", "earth", "eggs", "eight",
        "elated", "elegant", "enchanted", "enchanting", "encourage", "enjoy",
        "enormous", "entertain", "enthusiastic", "equal", "escape", "excellent",
        "excite", "exciting", "exist", "expect", "expert", "exuberant", "fairy",
        "familiar", "fancy", "fantastic", "farm", "fascinating", "feeling",
        "fez", "first", "five", "fixed", "float", "flood", "flower", "fluffy",
        "food", "fork", "frequent", "friend", "friendly", "frog", "fruit",
        "future", "futuristic", "garrulous", "geese", "ghost", "giants",
        "gifted", "gigantic", "giraffe", "glib", "glorious", "gorgeous",
        "grape", "grass", "grateful", "gratuity", "gray", "green", "grin",
        "groovy", "guide", "guitar", "hair", "haircut", "hand", "handsomely",
        "happy", "harbor", "harmonious", "hat", "heal", "heat", "heavenly",
        "hilarious", "hobbies", "honey", "horse", "hospitable", "hottub", "hug",
        "humor", "humorous", "hungry", "illustrious", "impartial", "imported",
        "improve", "impulse", "incredible", "inform", "instruct", "instrument",
        "interesting", "internal", "introduce", "invincible", "island", "jazzy",
        "jellyfish", "joke", "jolly", "joyous", "kind", "kindhearted", "kiss",
        "kitteh", "knit", "knowledge", "ladybug", "lamp", "language", "laugh",
        "learn", "lettuce", "library", "light", "like", "liquid", "listen",
        "lively", "lizard", "love", "love", "loving", "lunch", "magenta",
        "magical", "magnificent", "mailbox", "majestic", "marvelous", "melodic",
        "milk", "mint", "mitten", "monkey", "morning", "moustache", "mouth",
        "mysterious", "neighborly", "nest", "nifty", "oatmeal", "obtainable",
        "ocean", "orange", "pancake", "panoramic", "pants", "partner", "party",
        "pastoral", "peaceful", "pencil", "perfect", "person", "pet", "pets",
        "pickle", "pie", "piquant", "pizza", "placid", "plants", "play",
        "playground", "pleasant", "pleasure", "port", "porter", "position",
        "possible", "potato", "precious", "print", "profuse", "public",
        "pupper", "purple", "puzzle", "quaint", "quartz", "queen", "quiet",
        "rabbit", "radiate", "rainstorm", "rainy", "reading", "real", "red",
        "reflective", "rejoice", "respect", "responsible", "rest", "rhyme",
        "ritzy", "robin", "romantic", "rose", "round", "route", "safe", "sail",
        "sand", "savory", "science", "scientific", "scintillating", "scrabble",
        "sea", "seal", "seashore", "serious", "share", "shiny", "ship",
        "silent", "silk", "silly", "sincere", "skillful", "sleep", "sleepy",
        "smile", "snail", "soak", "soft", "solid", "song", "songs", "soothe",
        "sophisticated", "soup", "sparkling", "special", "spectacular",
        "spiffy", "splendid", "spooky", "spoon", "square", "squeal", "squirrel",
        "starboard", "stimulating", "stitch", "story", "succeed", "sun",
        "superb", "supreme", "surprise", "swanky", "sweater", "sweet", "swim",
        "table", "talented", "tasty", "team", "teeth", "terrific", "thankful",
        "thirsty", "thoughtful", "three", "throne", "thumb", "tiara", "ticket",
        "tiger", "tomato", "toothbrush", "toothpaste", "trail", "train",
        "tranquil", "tree", "two", "ubiquitous", "umbrella", "underwear",
        "unite", "unpack", "upbeat", "vacation", "verdant", "verse",
        "victorious", "view", "violet", "volcano", "walk", "warm", "water",
        "weather", "week", "welcome", "whimsical", "whirl", "whispering",
        "white", "witty", "wolves", "wonder", "wonderful", "word", "writing",
        "yarn", "year", "yellow", "yummy", "zealous", "zebra", "zesty", "zippy",
        "zombie"
    ]
    
    /// Generates a recovery key of 3 words randomly chosen from `words` array.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 500 error if the randomizer fails.
    /// - Returns: A recoveryKey String.
    static func generateRecoveryKey(on req: Request) throws -> Future<String> {
        guard let word1 = words.randomElement(),
            let word2 = words.randomElement(),
            let word3 = words.randomElement() else {
                throw Abort(.internalServerError, reason: "could not generate recovery key")
        }
        let recoveryKey = word1 + " " + word2 + " " + word3
        return req.future(recoveryKey)
    }
}

// MARK: - Helper Structs

/// Returned by `UserController.addHandler(_:data:)`.
struct AddedUserData: Content {
    /// The newly created sub-account's ID.
    let userID: UUID
    /// The newly created sub-account's username.
    let username: String
}
/// Returned by `UserController.createHandler(_:data:).`
struct CreatedUserData: Content {
    /// The newly created user's ID.
    let userID: UUID
    /// The newly created user's username.
    let username: String
    /// The newly created user's recoveryKey.
    let recoveryKey: String
}

/// Returned by `UserController.whoamiHandler(_:).`
struct CurrentUserData: Content {
    /// The currrent user's ID.
    let userID: UUID
    /// The current user's username.
    let username: String
    /// Whether the user is currently logged in.
    var isLoggedIn: Bool
}

/// Returned by `UserController.notesHandler(_:)` and `UserController.noteHandler(_:data:)`.
struct NoteData: Content {
    /// The ID of the note.
    let noteID: UUID
    /// Timestamp of the note's creation.
    let createdAt: Date
    /// Timestamp of the note's last update.
    let updataedAt: Date
    /// The ID of the associated profile.
    let profileID: UUID
    /// The .displayName of the profile's user.
    var profileUser: String
    /// The text of the note.
    let note: String
}

/// Used by `UserController.noteHandler(_:data:)` to update a user note.
struct NoteUpdateData: Content {
    /// The ID of the note being updated.
    let noteID: UUID
    /// The udated text of the note.
    let note: String
}

/// Used by `UserController.addHandler(_:data:) for adding a sub-account.
struct UserAddData: Content {
    /// The username for the sub-account.
    var username: String
    /// The password for the sub-account.
    var password: String
}

/// Used by `UserController.createHandler(_:data:) for initial creation of an account.
struct UserCreateData: Content {
    /// The user's username.
    var username: String
    /// The user's password.
    var password: String
}

/// Used by `UserController.passwordHandler(_:data:)` for changing a password.
struct UserPasswordData: Content {
    /// The user's desired new password.
    var password: String
}

/// Used by `UserController.profileUpdateHandler(_:data:)` for editing a profile.
struct UserProfileData: Content {
    /// An optional blurb about the user.
    var about: String
    /// An optional name for display alongside the username.
    var displayName: String
    /// An optional email address.
    var email: String
    /// An optional home location (e.g. city).
    var homeLocation: String
    /// An optional greeting/message to visitors of the profile.
    var message: String
    /// An optional preferred form of address.
    var preferredPronoun: String
    /// An optional real name of the user.
    var realName: String
    /// An optional ship cabin number.
    var roomNumber: String
    /// Whether display of the optional fields' data should be limited to logged in users.
    var limitAccess: Bool
}

/// Used by `UserController.usernameHandler(_:data:)` for changing a username.
struct UserUsernameData: Content {
    /// The user's desired new username.
    var username: String
}

/// Used by `UserController.verifyHandler(_:data:)` to verify a created but unverified
/// account.
struct UserVerifyData: Content {
    /// The registration code provided to the user.
    var verification: String
}

extension UserAddData: Validatable, Reflectable {
    /// Validates that `.username` is 1 or more alphanumeric characters,
    /// and `.password` is least 6 characters in length.
    static func validations() throws -> Validations<UserAddData> {
        var validations = Validations(UserAddData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        try validations.add(\.password, .count(6...))
        return validations
    }
}

extension UserCreateData: Validatable, Reflectable {
    /// Validates that `.username` is 1 or more alphanumeric characters,
    /// and `.password` is least 6 characters in length.
    static func validations() throws -> Validations<UserCreateData> {
        var validations = Validations(UserCreateData.self)
        // if testing allow "-" in name so that generated usernames can be UUID
        if (try Environment.detect().isRelease) {
            try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        } else {
            try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics + .dash))
        }
        try validations.add(\.password, .count(6...))
        return validations
    }
}

extension UserPasswordData: Validatable, Reflectable {
    /// Validates that the new password is at least 6 characters in length.
    static func validations() throws -> Validations<UserPasswordData> {
        var validations = Validations(UserPasswordData.self)
        try validations.add(\.password, .count(6...))
        return validations
    }
}

extension UserUsernameData: Validatable, Reflectable {
    /// Validates that the new username is 1 or more alphanumeric characters
    static func validations() throws -> Validations<UserUsernameData> {
        var validations = Validations(UserUsernameData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        return validations
    }
}

extension UserVerifyData: Validatable, Reflectable {
    /// Validates that a `.verification` registration code is either 6 or 7 alphanumeric
    /// characters in length (allows for inclusion or exclusion of the space).
    static func validations() throws -> Validations<UserVerifyData> {
        var validations = Validations(UserVerifyData.self)
        try validations.add(\.verification, .count(6...7) && .characterSet(.alphanumerics + .whitespaces))
        return validations
    }
}

extension CharacterSet {
    /// Define a character set containing just a "-", to allow UUID as username.
    /// This is only needed for our .testing environment.
    fileprivate static var dash: CharacterSet {
        var dash: CharacterSet = .init()
        dash.insert(charactersIn: "-")
        return dash
    }
}

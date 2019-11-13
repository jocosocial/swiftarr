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
        let basicAuthGroup = userRoutes.grouped(basicAuthMiddleware)
        let tokenAuthGroup = userRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        userRoutes.post(UserCreateData.self, at: "create", use: createHandler)
        
        // endpoints available only when not logged in
        basicAuthGroup.post(UserVerifyData.self, at: "verify", use: verifyHandler)
        
        // endpoints available only when logged in
        
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
    /// - Throws: 409 if the username is not available. A 5xx response should be reported as a
    ///   likely bug, please and thank you.
    /// - Returns: The newly created user's ID, username, and a recovery key string
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
                _ = try self.generateRecoveryKey(on: req).map {
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
                        guard let id = savedUser.id else {
                            throw Abort(.internalServerError, reason: "new user not saved")
                        }
                        let profile = UserProfile(userID: id, username: savedUser.username)
                        return profile.save(on: connection).map {
                            (savedProfile) in
                            let createdUserData = CreatedUserData(
                                userID: id,
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
                (existingCode) in
                // abort if code not found
                guard let registrationCode = existingCode else {
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
                        (savedCode) in
                        // update user
                        user.accessLevel = .verified
                        user.verification = registrationCode.code
                        return user.save(on: connection).transform(to: .ok)
                    }
                }
        }
    }

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.

    // MARK: - Helper Functions

    private let words: [String] = [
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
    private func generateRecoveryKey(on req: Request) throws -> Future<String> {
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

/// Returned by `UserController.createHandler(_:data:).`
struct CreatedUserData: Content {
    /// The newly created user's ID.
    let userID: UUID
    /// The newly created user's username
    let username: String
    /// If an optional `UserCreateData.verification` registration code was supplied in the
    /// request and this is a primary account, the generated recovery key, otherwise `nil`.
    /// A recoveryKey is generated only upon receipt of a successful registration.
    let recoveryKey: String?
}

/// Used by `UserController.createHandler(_:data:) for initial creation of an account.
struct UserCreateData: Content {
    /// The user's username.
    var username: String
    /// The user's password.
    var password: String
}

/// Used by `UserController.verifyHandler(_:)` to verify a created but unverified
/// account.
struct UserVerifyData: Content {
    /// The registration code provided to the user.
    var verification: String
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

import Vapor

/// Used to return a newly created sub-account's ID and username.
///
/// Returned by: `POST /api/v3/user/add`
///
/// See `UserController.addHandler(_:data:)`.
struct AddedUserData: Content {
    /// The newly created sub-account's ID.
    let userID: UUID
    /// The newly created sub-account's username.
    let username: String
}

/// Used to obtain the user's current list of alert keywords.
///
/// Returned by:
/// * `GET /api/v3/user/alertwords`
/// * `POST /api/v3/user/alertwords/add/STRING`
/// * `POST /api/v3/user/alertwords/remove/STRING`
///
/// See `UserController.alertwordsHandler(_:)`, `UserController.alertwordsAddHandler(_:)`,
/// `UserController.alertwordsRemoveHandler(_:)`.
struct AlertKeywordData: Content {
    /// The name of the barrel.
    let name: String
    /// The muted keywords.
    var keywords: [String]
}

/// Used to create a new user-owned `.seamonkey` or `.userWords` `Barrel`.
///
/// Required by: `POST /api/v3/user/barrel`
///
/// See `UserController.createBarrelHandler(_:data:)`.
struct BarrelCreateData: Content {
    /// The name of the barrel.
    var name: String
    /// An optional list of model UUIDs.
    var uuidList: [UUID]?
    /// An optional list of strings.
    var stringList: [String]?
}

/// Used to return the contents of a user-owned `.seamonkey` or `.userWords` `Barrel`.
///
/// Returned by:
/// * `POST /api/v3/user/barrel`
/// * `GET /api/v3/user/barrels/ID`
/// * `POST /api/v3/user/barrels/ID/add/STRING`
/// * `POST /api/v3/user/barrels/ID/remove/STRING`
/// * `POST /api/v3/user/barrels/ID/rename/STRING`
///
/// See `UserController.createBarrelHandler(_:data:)`, `UserController.barrelHandler(_:)`,
/// `UserController.barrelAddHandler(_:)`, `UserController.barrelRemoveHandler(_:)`,
/// `UserController.renameBarrelHandler(_:)`.
struct BarrelData: Content {
    /// The barrel's ID.
    let barrelID: UUID
    /// The name of the barrel.
    let name: String
    /// The barrel's `SeaMonkey` contents.
    var seamonkeys: [SeaMonkey]
    /// An optional list of strings.
    var stringList: [String]?
}

/// Used to obtain a list of user-owned `Barrel` names and IDs.
///
/// Returned by:
/// * `GET /api/v3/user/barrels`
/// * `GET /api/v3/user/barrels/seamonkey`
///
/// See `UserController.barrelsHandler(_:)`, `UserController.seamonkeyBarrelsHandler(_:)`.
struct BarrelListData: Content {
    /// The barrel's ID.
    let barrelID: UUID
    /// The name of the barrel.
    let name: String
}

/// Used to obtain the user's list of blocked users.
///
/// Returned by: `GET /api/v3/user/blocks`
///
/// See `UserController.blocksHandler(_:)`.
struct BlockedUserData: Content {
    /// The name of the barrel.
    let name: String
    /// The blocked `User`s.
    var seamonkeys: [SeaMonkey]
}

/// Used to return a newly created `UserNote` for display or further edit.
///
/// Returned by: `POST /api/v3/users/ID/note`
///
/// See `UsersController.noteCreateHandler(_:data:)`.
struct CreatedNoteData: Content {
    /// The ID of the note.
    var noteID: UUID
    /// The text of the note.
    var note: String
}

/// Used to return a newly created account's ID, username and recovery key.
///
/// Returned by: `POST /api/v3/user/create`
///
/// See `UserController.createHandler(_:data:).`
struct CreatedUserData: Content {
    /// The newly created user's ID.
    let userID: UUID
    /// The newly created user's username.
    let username: String
    /// The newly created user's recoveryKey.
    let recoveryKey: String
}

/// Used to obtain the current user's ID, username and logged-in status.
///
/// Returned by: `GET /api/v3/user/whoami`
///
/// See `UserController.whoamiHandler(_:).`
struct CurrentUserData: Content {
    /// The currrent user's ID.
    let userID: UUID
    /// The current user's username.
    let username: String
    /// Whether the user is currently logged in.
    var isLoggedIn: Bool
}

/// Used to obtain an event's details.
///
/// Returned by:
/// * `GET /api/v3/events`
/// * `GET /api/v3/events/official`
/// * `GET /api/v3/events/shadow`
/// * `GET /api/v3/events/now`
/// * `GET /api/v3/events/official/now`
/// * `GET /api/v3/events/shadow/now`
/// * `GET /api/v3/events/today`
/// * `GET /api/v3/events/official/today`
/// * `GET /api/v3/events/shadow/today`
/// * `GET /api/v3/events/match/STRING`
///
/// See `EventController.eventsHandler(_:)`, `EventController.officialHandler(_:)`,
/// `EventController.shadowHandler(_:)`, `EventController.eventsNowHandler(_:)`,
/// `EventController.officialNowHandler(_:)`,`EventController.shadowNowHandler(_:)`,
/// `EventController.eventsTodayHandler(_:)`, `EventController.officialTodayHandler(_:)`,
/// `EventController.shadowTodayHandler(_:)`, `EventController.eventsMatchHandler(_:)`.
struct EventData: Content {
    /// The event's ID.
    var eventID: UUID
    /// The event's title.
    var title: String
    /// A description of the event.
    var description: String
    /// Starting time of the event
    var startTime: Date
    /// Ending time of the event.
    var endTime: Date
    /// The location of the event.
    var location: String
    /// The event category.
    var eventType: String
    /// The event's associated `Forum`.
    var forum: Int?
}

/// Used to update the `Event` database.
///
/// Required by: `POST /api/v3/events/update`
///
/// See `EventController.eventsUpdateHandler(_:data:)`.
struct EventsUpdateData: Content {
    /// The `.ics` event schedule file.
    var schedule: String
}

/// Used to upload an image file.
///
/// Required by: `POST /api/v3/user/image`
///
/// See `UserController.imageHandler(_:data)`.
struct ImageUploadData: Content {
    /// The name of the image file.
    var filename: String
    /// The image in `Data` format.
    var image: Data
}

/// Used to obtain the user's current list of keywords for muting public content.
///
/// Returned by:
/// * `GET /api/v3/user/mutewords`
/// * `POST /api/v3/user/mutewords/add/STRING`
/// * `POST /api/v3/user/mutewords/remove/STRING`
///
/// See `UserController.mutewordsHandler(_:)`, `UserController.mutewordsAddHandler(_:)`,
/// `UserController.mutewordsRemoveHandler(_:)`.
struct MuteKeywordData: Content {
    /// The name of the barrel.
    let name: String
    /// The muted keywords.
    var keywords: [String]
}

/// Used to obtain the user's list of muted users.
///
/// Returned by: `GET /api/v3/user/mutes`
///
/// See `UserController.mutesHandler(_:)`.
struct MutedUserData: Content {
    /// The name of the barrel.
    let name: String
    /// The muted `User`s.
    var seamonkeys: [SeaMonkey]
}

/// Used to create a `UserNote` when viewing a user's profile.
///
/// Required by: `/api/v3/users/ID/note`
///
/// See `UsersController.noteCreateHandler(_:data:)`.
struct NoteCreateData: Content {
    /// The text of the note.
    var note: String
}

/// Used to obtain the contents of a `UserNote` for display in a non-profile-viewing context.
///
/// Returned by:
/// * `GET /api/v3/user/notes`
/// * `POST /api/v3/user/note`
///
/// See `UserController.notesHandler(_:)`, `UserController.noteHandler(_:data:)`.
struct NoteData: Content {
    /// The ID of the note.
    let noteID: UUID
    /// Timestamp of the note's creation.
    let createdAt: Date
    /// Timestamp of the note's last update.
    let updatedAt: Date
    /// The ID of the associated profile.
    let profileID: UUID
    /// The .displayName of the profile's user.
    var profileUser: String
    /// The text of the note.
    var note: String
}

/// Used to update a `UserNote` in a non-profile-viewing context.
///
/// Required by: `POST /api/v3/user/note`
///
/// See `UserController.noteHandler(_:data:)`.
struct NoteUpdateData: Content {
    /// The ID of the note being updated.
    let noteID: UUID
    /// The udated text of the note.
    let note: String
}

/// Returned by `Barrel`s as a unit representing a user.
struct SeaMonkey: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
}

/// Used to return a token string for use in HTTP Bearer Authentication.
///
/// Returned by:
/// * `POST /api/v3/auth/login`
/// * `POST /api/v3/auth/recovery`
///
/// See `AuthController.loginHandler(_:)` and `AuthController.recoveryHandler(_:data:)`.
struct TokenStringData: Content {
    /// The token string.
    let token: String
    /// Creates a `TokenStringData` from a `Token`.
    /// - Parameter token: The `Token` associated with the authenticated user.
    init(token: Token) {
        self.token = token.token
    }
}

/// Used to return a filename for an uploaded image.
///
/// Returned by: `POST /api/v3/user/image`
///
/// See `UserController.imageHandler(_:data:)`
struct UploadedImageData: Content {
    /// The generated name of the uploaded image.
    var filename: String
}

/// Used to create a new account or sub-account.
///
/// Required by:
/// * `POST /api/v3/user/create`
/// * `POST /api/v3/user/add`
///
/// See `UserController.createHandler(_:data:)`, `UserController.addHandler(_:data:)`.
struct UserCreateData: Content {
    /// The user's username.
    var username: String
    /// The user's password.
    var password: String
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

/// Used to obtain user identity and determine whether any cached information may be stale.
///
/// Returned by:
/// * `GET /api/v3/users/ID`
/// * `GET /api/v3/users/find/STRING`
/// * `GET /api/v3/client/user/updates/since/DATE`
///
/// See `UsersController.userHandler(_:)`, `UsersController.findHandler(_:)`,
/// `ClientController.userUpdatesHandler(_:)`.
struct UserInfo: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's username.
    var username: String
    /// Timestamp of last update to the user's profile.
    var updatedAt: Date
}

/// Used to change a user's password.
///
/// Required by: `POST /api/v3/user/password`
///
/// See `UserController.passwordHandler(_:data:)`.
struct UserPasswordData: Content {
    /// The user's desired new password.
    var password: String
}

/// Used to update a user's profile contents.
///
/// Required by: `POST /api/v3/user/profile`
///
/// See `UserController.profileUpdateHandler(_:data:)`.
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

/// Used to attempt to recover an account in a forgotten-password type scenario.
///
/// Required by: `POST /api/v3/auth/recovery`
///
/// See `AuthController.recoveryHandler(_:data:)`.
struct UserRecoveryData: Content {
    /// The user's username.
    var username: String
    /// The string to use – any one of: password / registration key / recovery key.
    var recoveryKey: String
}

/// Used to submit a message with a `Report`.
///
/// Required by:
/// * `POST /api/v3/users/ID/report`
///
/// See `UsersController.reportHandler(_:data:)`.
struct UserReportData: Content {
    /// An optional message from the submitting user.
    var message: String
}

/// Used to broad search for a user based on any of their name fields.
///
/// Returned by:
/// * `GET /api/v3/users/match/allnames/STRING`
/// * `GET /api/v3/client/usersearch`
///
/// See `UsersController.matchAllNamesHandler(_:)`, `ClientController.userSearchHandler(_:)`.
struct UserSearch: Content {
    /// The user's ID.
    var userID: UUID
    /// The user's composed displayName + username + realName.
    var userSearch: String
}

/// Used to change a user's username.
///
/// Required by: `POST /api/v3/user/username`
///
/// See `UserController.usernameHandler(_:data:)`.
struct UserUsernameData: Content {
    /// The user's desired new username.
    var username: String
}

/// Used to verify (register) a created but `.unverified` primary account.
///
/// Required by: `POST /api/v3/user/verify`
///
/// See `UserController.verifyHandler(_:data:)`.
struct UserVerifyData: Content {
    /// The registration code provided to the user.
    var verification: String
}

// MARK: - Validation

extension BarrelCreateData: Validatable, Reflectable {
    /// Validates that `.name` contains a value, and that only one of `.uuidList` or
    /// `.stringList` contains values.
    static func validations() throws -> Validations<BarrelCreateData> {
        var validations = Validations(BarrelCreateData.self)
        try validations.add(\.name, .count(1...))
        validations.add("'uuidList' and 'stringList' cannot both contain values") {
            (data) in
            guard data.uuidList == nil || data.stringList == nil else {
                throw Abort(.badRequest, reason: "'uuidList' and 'stringList' cannot both contain values")
            }
        }
        return validations
    }
}

extension UserCreateData: Validatable, Reflectable {
    /// Validates that `.username` is 1 or more characters beginning with an alphanumeric,
    /// and `.password` is least 6 characters in length.
    static func validations() throws -> Validations<UserCreateData> {
        var validations = Validations(UserCreateData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics + .separators))
        validations.add("username must start with an alphanumeric") {
            (data) in
            guard let first = data.username.unicodeScalars.first,
                !CharacterSet.separators.contains(first) else {
                    throw Abort(.badRequest, reason: "username must start with an alphanumeric")
            }
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

extension UserRecoveryData: Validatable, Reflectable {
    /// Validates that `.username` is 1 or more alphanumeric characters,
    /// and `.recoveryCode` is at least 6 character in length (minimum for
    /// both registration codes and passwords).
    static func validations() throws -> Validations<UserRecoveryData> {
        var validations = Validations(UserRecoveryData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        try validations.add(\.recoveryKey, .count(6...))
        return validations
    }
}

extension UserUsernameData: Validatable, Reflectable {
    /// Validates that the new username is 1 or more characters and begins with an
    /// alphanumeric.
    static func validations() throws -> Validations<UserUsernameData> {
        var validations = Validations(UserUsernameData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics + .separators))
        validations.add("username must start with an alphanumeric") {
            (data) in
            guard let first = data.username.unicodeScalars.first,
                !CharacterSet.separators.contains(first) else {
                    throw Abort(.badRequest, reason: "username must start with an alphanumeric")
            }
        }
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
    /// Defines a character set containing characters other than alphanumerics that are allowed
    /// in a username.
    static var separators: CharacterSet {
        var separatorChars: CharacterSet = .init()
        separatorChars.insert(charactersIn: "-.+_")
        return separatorChars
    }
}

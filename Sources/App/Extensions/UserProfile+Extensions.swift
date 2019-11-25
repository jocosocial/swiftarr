import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension UserProfile: PostgreSQLUUIDModel {}

// model and representations can be passed as HTTP body data
extension UserProfile: Content {}
extension UserProfile.Edit: Content {}
extension UserProfile.Header: Content {}
extension UserProfile.Public: Content {}
extension UserProfile.Search: Content {}

// model can be used as endpoint parameter
extension UserProfile: Parameter {}

// MARK: - Custom Migration

extension UserProfile: Migration {
    /// Required by `Migration` protocol. Creates the table, with unique contraint on
    /// `.username` and foreign key constraint to `User`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // enforce unique username, just because
            builder.unique(on: \.username)
            // foreign key contraint to User
            builder.reference(from: \.userID, to: \User.id)
        }
    }
}

// MARK: - Timestamping Conformance

extension UserProfile {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}

// MARK: - Parent

extension UserProfile {
    /// The parent `User` of the profile.
    var user: Parent<UserProfile, User> {
        return parent(\.userID)
    }
}

// MARK: - Children

extension UserProfile {
    /// The child `ProfileEdit` accountability records of the profile.
    var edits: Children<UserProfile, ProfileEdit> {
        return children(\.profileID)
    }
}

// MARK: - Methods

extension UserProfile {
    /// Converts a `UserProfile` model to a version intended for editing by the owning
    /// user. `.username` and `.displayedName` are provided for client display convenience
    /// only and may not be edited.
    func convertToEdit() -> UserProfile.Edit {
        return UserProfile.Edit(
            username: self.username,
            about: self.about ?? "",
            displayName: self.displayName ?? "",
            email: self.email ?? "",
            homeLocation: self.homeLocation ?? "",
            message: self.message ?? "",
            preferredPronoun: self.preferredPronoun ?? "",
            realName: self.realName ?? "",
            roomNumber: self.roomNumber ?? "",
            limitAccess: self.limitAccess
        )
    }
    
    /// Converts a `UserProfile` model to a version intended for content headers. Only the ID,
    /// generated `.displayedName` and name of the profile's user image are returned.
    func convertToHeader() throws -> UserProfile.Header {
        return UserProfile.Header(
            userID: self.userID,
            username: self.username,
            displayName: self.displayName ?? "",
            userImage: self.userImage
        )
    }
    
    /// Converts a `UserProfile` model to a version that is publicly viewable. Essentially,
    /// sensitive and unneeded data are omitted and the `.username` and `.displayName` properties
    /// are massaged into the more familiar "Display Name (@username)" or "@username" (if
    /// `.displayName` is empty) format as seen in posted content headers.
    func convertToPublic() throws -> UserProfile.Public {
        return UserProfile.Public(
            profileID: try self.requireID(),
            username: self.username,
            about: self.about ?? "",
            displayName: self.displayName ?? "",
            email: self.email ?? "",
            homeLocation: self.homeLocation ?? "",
            message: self.message ?? "",
            preferredPronoun: self.preferredPronoun ?? "",
            realName: self.realName ?? "",
            roomNumber: self.roomNumber ?? ""
        )
    }
    
    /// Converts a `UserProfile` model to a version intended for multi-field search. Only the ID
    /// and a precomposed `.displayName` + `.username` + `.realName` string are returned.
    func convertToSearch() throws -> UserProfile.Search {
        return UserProfile.Search(
            userID: self.userID,
            userSearch: self.userSearch
        )
    }
}

extension Future where T: UserProfile {
    // MARK: - where T: UserProfile

    /// Converts a `Future<UserProfile>` to a `Future<UserProfile.Header>`. This extension
    /// provides the convenience of simply using `profile.convertToHeader()` and allowing the
    /// compiler to choose the appropriate version for the context.
    func convertToHeader() throws -> Future<UserProfile.Header> {
        return self.map {
            (profile) in
            return try profile.convertToHeader()
        }
    }
    
    /// Converts a `Future<UserProfile>` to a `Future<UserProfile.Search>`. This extension
    /// provides the convenience of simply using `profile.convertToSearcg()` and allowing the
    /// compiler to choose the appropriate version for the context.
    func convertToSearch() throws -> Future<UserProfile.Search> {
        return self.map {
            (profile) in
            return try profile.convertToSearch()
        }
    }
}


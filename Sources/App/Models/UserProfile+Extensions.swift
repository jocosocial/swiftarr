import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension UserProfile: PostgreSQLUUIDModel {}

// model and representations can be passed as HTTP body data
extension UserProfile: Content {}
extension UserProfile.Edit: Content {}
extension UserProfile.Public: Content {}

// model can be used as endpoint parameter
extension UserProfile: Parameter {}

// MARK: - Custom Migration

extension UserProfile: Migration {
    /// Required by `Migration` protocol. Creates the table, with unique contraint on
    /// `.username` and foreign key constraint to `User`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // enforce unique username, just because
            builder.unique(on: \.username)
            // foreigh key contraint to User
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
}



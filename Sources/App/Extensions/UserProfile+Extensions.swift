import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension UserProfile: PostgreSQLUUIDModel {}

// model can be passed as HTTP body data
extension UserProfile: Content {}

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

// MARK: - Relations

extension UserProfile {
    /// The child `ProfileEdit` accountability records of the profile.
    var edits: Children<UserProfile, ProfileEdit> {
        return children(\.profileID)
    }

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
    func convertToData() -> UserProfileData {
        var userProfileData = UserProfileData(
            username: self.username,
            displayedName: "",
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
        if userProfileData.displayName.isEmpty {
            userProfileData.displayedName = "@\(self.username)"
        } else {
            userProfileData.displayedName = userProfileData.displayName + " (@\(self.username))"
        }
        return userProfileData
    }
    
    /// Converts a `UserProfile` model to a version intended for content headers. Only the ID,
    /// generated `.displayedName` and name of the profile's user image are returned.
    func convertToHeader() throws -> UserHeader {
        var userHeader = UserHeader(
            userID: self.userID,
            displayedName: "",
            userImage: self.userImage
        )
        if let displayName = self.displayName {
            userHeader.displayedName = displayName + " (@\(username))"
        } else {
            userHeader.displayedName = "@\(username)"
        }
        return userHeader
    }
    
    /// Converts a `UserProfile` model to a version that is publicly viewable. Essentially,
    /// sensitive and unneeded data are omitted and the `.username` and `.displayName` properties
    /// are massaged into the more familiar "Display Name (@username)" or "@username" (if
    /// `.displayName` is empty) format as seen in posted content headers.
    func convertToPublic() throws -> ProfilePublicData {
        var profilePublicData = ProfilePublicData(
            profileID: try self.requireID(),
            displayedName: "",
            about: self.about ?? "",
            email: self.email ?? "",
            homeLocation: self.homeLocation ?? "",
            message: self.message ?? "",
            preferredPronoun: self.preferredPronoun ?? "",
            realName: self.realName ?? "",
            roomNumber: self.roomNumber ?? "",
            note: nil
        )
        let displayName = self.displayName ?? ""
        if displayName.isEmpty {
            profilePublicData.displayedName = "@\(self.username)"
        } else {
            profilePublicData.displayedName = displayName + " (@\(self.username))"
        }
        return profilePublicData
    }
    
    /// Converts a `UserProfile` model to a version intended for multi-field search. Only the ID
    /// and a precomposed `.displayName` + `.username` + `.realName` string are returned.
    func convertToSearch() throws -> UserSearch {
        return UserSearch(
            userID: self.userID,
            userSearch: self.userSearch
        )
    }
}

extension Future where T: UserProfile {
    /// Converts a `Future<UserProfile>` to a `Future<UserHeader>`. This extension
    /// provides the convenience of simply using `profile.convertToHeader()` and allowing the
    /// compiler to choose the appropriate version for the context.
    func convertToHeader() throws -> Future<UserHeader> {
        return self.map {
            (profile) in
            return try profile.convertToHeader()
        }
    }
    
    /// Converts a `Future<UserProfile>` to a `Future<UserSearch>`. This extension
    /// provides the convenience of simply using `profile.convertToSearch()` and allowing the
    /// compiler to choose the appropriate version for the context.
    func convertToSearch() throws -> Future<UserSearch> {
        return self.map {
            (profile) in
            return try profile.convertToSearch()
        }
    }
}


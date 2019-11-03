@testable import App
import FluentPostgreSQL
import Authentication

extension User {
    
    /// Convenience utility to create a test User and its associated profile.
    ///
    /// - Parameters:
    ///   - username: An optional username (or randomly generated if `nil`).
    ///   - accessLevel: The desired `UserAccessLevel` for this user.
    ///   - connection: The database connection.
    /// - Returns: An initialized `User` object.
    static func create(
        username: String? = nil,
        accessLevel: UserAccessLevel,
        on connection: PostgreSQLConnection
    ) throws -> User {
        // generate random username if none specified
        var createUsername: String
        if let suppliedUsername = username {
            createUsername = suppliedUsername
        } else {
            createUsername = UUID().uuidString
        }
        // test users all have default password and recovery key
        let passwordHash = try BCrypt.hash("password")
        let recoveryHash = try BCrypt.hash("recovery key")
        // create user directly
        let user = User(
            username: createUsername,
            password: passwordHash,
            recoveryKey: recoveryHash,
            verification: nil,
            parentID: nil,
            accessLevel: accessLevel
        )
        // save user and create associated profile
        return try user.save(on: connection).flatMap {
            (savedUser) in
            // create placeholder image file named ID.jpg
            let imageName = try "\(savedUser.requireID()).jpg"
            let filePath = "images/profile/full/" + imageName
            FileManager().createFile(atPath: filePath, contents: Data(count: 1), attributes: nil)
            // create profile
            let profile = UserProfile(
                userID: savedUser.id!,
                username: savedUser.username,
                userImage: imageName,
                limitAccess: false
            )
            // save profile and return the user object
            return profile.save(on: connection).map {
                (savedProfile) in
                return savedUser
            }
        }.wait()
    }
}

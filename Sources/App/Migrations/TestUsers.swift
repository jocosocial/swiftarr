import Vapor
import FluentPostgreSQL
import Crypto

/// A `Migration` that creates a set of test users during startup, so that there exists one
/// at each `.accessLevel`. This migration should only be run in non-production environments.

struct TestUsers: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Creates a set of test users at each `.accessLevel`.
    ///
    /// - Parameter conn: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on conn: PostgreSQLConnection) -> Future<Void> {
        let usernames: [String: UserAccessLevel] = [
            "unverified": .unverified,
            "banned": .banned,
            "quarantined": .quarantined,
            "verified": .verified,
            "moderator": .moderator,
            "tho": .tho
        ]
        // create users
        var users: [User] = []
        for username in usernames {
            let password = try? BCrypt.hash("password")
            guard let passwordHash = password else {
                fatalError("could not create test users: password hash failed")
            }
            let user = User(
                username: username.key,
                password: passwordHash,
                recoveryKey: "recovery key",
                accessLevel: username.value
            )
            users.append(user)
        }
        return users.map { $0.save(on: conn) }.flatten(on: conn).map {
            (savedUsers) in
            // create profile and default barrels
            var profiles: [UserProfile] = []
            savedUsers.forEach {
                guard let id = $0.id else { fatalError("user has no id") }
                let profile = UserProfile(userID: id, username: $0.username)
                profiles.append(profile)
                var barrels: [Barrel] = []
                let alertKeywordsBarrel = Barrel(
                    ownerID: id,
                    barrelType: .keywordAlert,
                    name: "Alert Keywords"
                )
                alertKeywordsBarrel.userInfo.updateValue([], forKey: "alertWords")
                barrels.append(alertKeywordsBarrel)
                let blocksBarrel = Barrel(
                    ownerID: id,
                    barrelType: .userBlock,
                    name: "Blocked Users"
                )
                barrels.append(blocksBarrel)
                let mutesBarrel = Barrel(
                    ownerID: id,
                    barrelType: .userMute,
                    name: "Muted Users"
                )
                barrels.append(mutesBarrel)
                let muteKeywordsBarrel = Barrel(
                    ownerID: id,
                    barrelType: .keywordMute,
                    name: "Muted Keywords"
                )
                muteKeywordsBarrel.userInfo.updateValue([], forKey: "muteWords")
                barrels.append(muteKeywordsBarrel)
                // save barrels
                _ = barrels.map { $0.save(on: conn) }
            }
            // save profiles
            profiles.map { $0.save(on: conn) }.always(on: conn) { return }
        }
    }
    
    /// Required by`Migration` protocol, but no point removing the test users, so
    /// just return a pre-completed `Future`.
    /// 
    /// - Parameter conn: The database connection.
    /// - Returns: Void.
    static func revert(on conn: PostgreSQLConnection) -> Future<Void> {
        return .done(on: conn)
    }
}


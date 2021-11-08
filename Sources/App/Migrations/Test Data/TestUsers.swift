import Vapor
import Fluent
import Crypto

/// A `Migration` that creates a set of test users during startup, so that there exists one
/// at each `.accessLevel`. This migration should only be run in non-production environments.

struct CreateTestUsers: Migration {    
    /// Required by `Migration` protocol. Creates a set of test users at each `.accessLevel`.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        let usernames: [String: UserAccessLevel] = [
            "unverified": .unverified,
            "banned": .banned,
            "quarantined": .quarantined,
            "verified": .verified,
            "james": .verified,
            "heidi": .verified,
            "sam": .verified,
            "moderator": .moderator,
            "tho": .tho
        ]
        // create users
        var users: [User] = []
        for username in usernames {
            let password = try? Bcrypt.hash("password")
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
        return users.map { $0.save(on: database) }.flatten(on: database.eventLoop).throwingFlatMap { (savedUsers) in
            // create default barrels
			var barrels: [Barrel] = []
            users.forEach {
                guard let id = $0.id else { fatalError("user has no id") }
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
            }
			// save barrels
			return barrels.map { $0.save(on: database) }.flatten(on: database.eventLoop)
        }
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    /// 
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("users").delete()
    }
}


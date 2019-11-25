import Vapor
import FluentPostgreSQL
import Crypto

/// A `Migration` that creates the admin user upon startup. The password and recovery key are
/// read from environment variables `ADMIN_PASSWORD` and `RECOVERY_KEY` if present, otherwise
/// defaults are used.
///
/// The defaults are intended and fine for development and testing, but should **never** be
/// used in production. If not set to proper values in `docker-compose.yml` (or whatever
/// other environment of your choice), reminders are printed to console during startup.

struct AdminUser: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Creates the admin user after a bit of sanity
    /// check caution.
    ///
    /// - Parameter connection: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        // retrieve password and recovery key from environment, else use defaults
        let password = Environment.get("ADMIN_PASSWORD") ?? "password"
        let recoveryKey = Environment.get("RECOVERY_KEY") ?? "recovery key"
        
        // default values should never be used in production
        do {
            if (try Environment.detect().isRelease) {
                if password == "password" {
                    print("Please set a proper ADMIN_PASSWORD environment variable.")
                }
                if recoveryKey == "recovery key" {
                    print("Please set a proper RECOVERY_KEY environment variable.")
                }
            }
        } catch let error {
            fatalError("Environment.detect() failed! error: \(error)")
        }
        
        // abort if no sane values or encryption fails
        guard !password.isEmpty, !recoveryKey.isEmpty,
            let passwordHash = try? BCrypt.hash(password),
            let recoveryHash = try? BCrypt.hash(recoveryKey) else {
                fatalError("admin user creation failure: invalid password or recoveryKey")
        }
        
        // create admin user directly
        let user = User(
            username: "admin",
            password: passwordHash,
            recoveryKey: recoveryHash,
            verification: "generated user",
            parentID: nil,
            accessLevel: .admin
        )
        // save user
        return user.save(on: connection).flatMap {
            (savedUser) in
            // ensure we're good to go
            guard let id = savedUser.id else {
                fatalError("admin user creation failure: savedUser.id not found")
            }
            // create default barrels
            var barrels: [Future<Barrel>] = .init()
            let blocksBarrel = Barrel(
                ownerID: id,
                barrelType: .userBlock,
                name: "Blocked Users"
            )
            barrels.append(blocksBarrel.save(on: connection))
            let mutesBarrel = Barrel(
                ownerID: id,
                barrelType: .userMute,
                name: "Muted Users"
            )
            barrels.append(mutesBarrel.save(on: connection))
            let keywordsBarrel = Barrel(
                ownerID: id,
                barrelType: .keywordMute,
                name: "Muted Keywords"
            )
            keywordsBarrel.userInfo.updateValue([], forKey: "keywords")
            barrels.append(keywordsBarrel.save(on: connection))
            // resolve futures, return void
            return barrels.flatten(on: connection).flatMap {
                (savedBarrels) in
                // create associated profile directly
                let profile = UserProfile(userID: id, username: savedUser.username)
                return profile.save(on: connection).transform(to: ())
            }
        }
    }
    
    /// Required by`Migration` protocol, but removing the admin would be an exceptionally poor
    /// idea, so override the default implementation to just return a pre-completed `Future`.
    static func revert(on connection: PostgreSQLConnection) -> Future<Void> {
        return Future.done(on: connection)
    }
    
}

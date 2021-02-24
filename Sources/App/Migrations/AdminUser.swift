import Vapor
import Fluent
import Crypto

/// A `Migration` that creates the admin user upon startup. The password and recovery key are
/// read from environment variables `ADMIN_PASSWORD` and `RECOVERY_KEY` if present, otherwise
/// defaults are used.
///
/// The defaults are intended and fine for development and testing, but should **never** be
/// used in production. If not set to proper values in `docker-compose.yml` (or whatever
/// other environment of your choice), reminders are printed to console during startup.

struct CreateAdminUser: Migration {    
    /// Required by `Migration` protocol. Creates the admin user after a bit of sanity
    /// check caution.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
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
            let passwordHash = try? Bcrypt.hash(password),
            let recoveryHash = try? Bcrypt.hash(recoveryKey) else {
                fatalError("admin user creation failure: invalid password or recoveryKey")
        }
        
        // create admin user directly
        let user = User(
            username: "admin",
            password: passwordHash,
            recoveryKey: recoveryHash,
            verification: "generated user",
			parent: nil,
            accessLevel: .admin
        )
        // save user
        return user.save(on: database).flatMap {
            // ensure we're good to go
            guard let id = user.id else {
                fatalError("admin user creation failure: savedUser.id not found")
            }
            // create default barrels
            var barrels = [EventLoopFuture<Void>]()
            let alertKeywordsBarrel = Barrel(
                ownerID: id,
                barrelType: .keywordAlert,
                name: "Alert Keywords"
            )
            alertKeywordsBarrel.userInfo.updateValue([], forKey: "alertWords")
            barrels.append(alertKeywordsBarrel.save(on: database))
            let blocksBarrel = Barrel(
                ownerID: id,
                barrelType: .userBlock,
                name: "Blocked Users"
            )
            barrels.append(blocksBarrel.save(on: database))
            let mutesBarrel = Barrel(
                ownerID: id,
                barrelType: .userMute,
                name: "Muted Users"
            )
            barrels.append(mutesBarrel.save(on: database))
            let muteKeywordsBarrel = Barrel(
                ownerID: id,
                barrelType: .keywordMute,
                name: "Muted Keywords"
            )
            muteKeywordsBarrel.userInfo.updateValue([], forKey: "muteWords")
            barrels.append(muteKeywordsBarrel.save(on: database))
            // resolve futures, return void
			return barrels.flatten(on: database.eventLoop).transform(to: ())
        }
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    ///
    /// - Parameter conn: The database connection.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("users").delete()
    }
    
}

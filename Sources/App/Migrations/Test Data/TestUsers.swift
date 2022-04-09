import Vapor
import Fluent
import Crypto

/// A `Migration` that creates a set of test users during startup, so that there exists one
/// at each `.accessLevel`. This migration should only be run in non-production environments.

struct CreateTestUsers: AsyncMigration {
	static let usernames: [String: UserAccessLevel] = [
			"unverified": .unverified,
			"banned": .banned,
			"quarantined": .quarantined,
			"verified": .verified,
			"james": .verified,
			"heidi": .verified,
			"sam": .verified,
		]
   
	/// Required by `Migration` protocol. Creates a set of test users at each `.accessLevel`.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		let users: [User] = CreateTestUsers.usernames.map { (username, accessLevel) in
			guard let passwordHash = try? Bcrypt.hash("password", cost: 9) else {
				fatalError("could not create test users: password hash failed")
			}
			return User(username: username, password: passwordHash, recoveryKey: "recovery key", accessLevel: accessLevel)
		}
		try await users.create(on: database)
	}
	
	/// Deletes the test users. May not be safe--we haven't actually tested deleting users much as it's not a server feature.
	/// 
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		let nameArray = CreateTestUsers.usernames.keys
		try await User.query(on: database).filter(\.$username ~~ nameArray).delete()
	}
}


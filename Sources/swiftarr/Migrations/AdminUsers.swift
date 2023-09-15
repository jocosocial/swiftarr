import Crypto
import Fluent
import Vapor

/// A `Migration` that creates the admin user upon startup. The password and recovery key are
/// read from environment variables `ADMIN_PASSWORD` and `RECOVERY_KEY` if present, otherwise
/// defaults are used.
///
/// The defaults are intended and fine for development and testing, but should **never** be
/// used in production. If not set to proper values in `docker-compose.yml` (or whatever
/// other environment of your choice), reminders are printed to console during startup.

struct CreateAdminUsers: AsyncMigration {
	/// Required by `Migration` protocol. Creates the admin user after a bit of sanity
	/// check caution.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		try await createAdminUser(on: database)
		try await createPrometheusUser(on: database)
		try await createTHOUser(on: database)
		try await createModeratorUser(on: database)
		try await createTwitarrTeamUser(on: database)
	}

	/// Required by `Migration` protocol. Deletes all admin users.
	///
	/// - Parameter conn: The database connection.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await User.query(on: database).filter(\.$username ~~ ["admin", "THO", "moderator", "TwitarrTeam"]).delete()
	}

	/// Admin user gets their password and recovery key from the `ADMIN_PASSWORD` and `ADMIN_RECOVERY_KEY`
	/// environment variables. These are usually set in the appropriate .env file in "Private Swiftarr Config" directory.
	/// For the production environment, this file will be "production.env".
	func createAdminUser(on database: Database) async throws {
		// retrieve password and recovery key from environment, else use defaults
		let password = Environment.get("ADMIN_PASSWORD") ?? "password"
		let recoveryKey = Environment.get("ADMIN_RECOVERY_KEY") ?? "recovery key"

		// default values should never be used in production
		do {
			if try Environment.detect().isRelease {
				if password == "password" {
					database.logger.log(level: .critical, "Please set a proper ADMIN_PASSWORD environment variable.")
				}
				if recoveryKey == "recovery key" {
					database.logger.log(
						level: .critical,
						"Please set a proper ADMIN_RECOVERY_KEY environment variable."
					)
				}
			}
		}
		catch let error {
			fatalError("Environment.detect() failed! error: \(error)")
		}

		// abort if no sane values or encryption fails
		guard !password.isEmpty, !recoveryKey.isEmpty,
			let passwordHash = try? Bcrypt.hash(password),
			let recoveryHash = try? Bcrypt.hash(recoveryKey)
		else {
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
		try await user.save(on: database)
	}

	/// Prometheus user gets their password from the `PROMETHEUS_PASSWORD`. Recovery key is randomly generated and thrown away.
	/// environment variables. These are usually set in the appropriate .env file in "Private Swiftarr Config" directory.
	/// For the production environment, this file will be "production.env".
	func createPrometheusUser(on database: Database) async throws {
		let password = Environment.get("PROMETHEUS_PASSWORD") ?? "password"
		var recoveryKey = ""
		for _ in 0...50 {
			recoveryKey.append(String(Unicode.Scalar(Int.random(in: 33...126))!))
		}

		// default values should never be used in production
		do {
			if try Environment.detect().isRelease {
				if password == "password" {
					database.logger.log(
						level: .critical,
						"Please set a proper PROMETHEUS_PASSWORD environment variable."
					)
				}
			}
		}
		catch let error {
			fatalError("Environment.detect() failed! error: \(error)")
		}

		// abort if no sane values or encryption fails
		guard !password.isEmpty, !recoveryKey.isEmpty,
			let passwordHash = try? Bcrypt.hash(password),
			let recoveryHash = try? Bcrypt.hash(recoveryKey)
		else {
			fatalError("prometheus user creation failure: invalid password or recoveryKey")
		}

		// create prometheus user directly
		let user = User(
			username: "prometheus",
			password: passwordHash,
			recoveryKey: recoveryHash,
			verification: "generated user",
			parent: nil,
			accessLevel: .client
		)
		// save user
		try await user.save(on: database)
	}

	/// THO is a special acct for JoCo home office. There's several specific things this account can do, such as settings announcements and daily themes.
	/// This account's password and recovery key are set up in the same way as the admin acct.
	func createTHOUser(on database: Database) async throws {
		// retrieve password and recovery key from environment, else use defaults
		let password = Environment.get("THO_PASSWORD") ?? "password"
		let recoveryKey = Environment.get("THO_RECOVERY_KEY") ?? "recovery key"

		// default values should never be used in production
		do {
			if try Environment.detect().isRelease {
				if password == "password" {
					database.logger.log(level: .critical, "Please set a proper THO_PASSWORD environment variable.")
				}
				if recoveryKey == "recovery key" {
					database.logger.log(level: .critical, "Please set a proper THO_RECOVERY_KEY environment variable.")
				}
			}
		}
		catch let error {
			fatalError("Environment.detect() failed! error: \(error)")
		}
		// abort if no sane values or encryption fails
		guard !password.isEmpty, !recoveryKey.isEmpty, let passwordHash = try? Bcrypt.hash(password),
			let recoveryHash = try? Bcrypt.hash(recoveryKey)
		else {
			fatalError("THO user creation failure: invalid password or recoveryKey")
		}
		// create THO user directly
		let user = User(
			username: "THO",
			password: passwordHash,
			recoveryKey: recoveryHash,
			verification: "generated user",
			parent: nil,
			accessLevel: .tho
		)
		try await user.save(on: database)
	}

	/// By design, nobody can log in as Moderator--the password is set to a randomly-generated value that is immediately forgotten.
	/// However, anyone with moderotor access may post content *as* moderator, in which case the moderator account becomes
	/// the author of the content instead of the current user.
	///
	/// ''Content' in this sense means tweets, forum posts, fez messages.
	func createModeratorUser(on database: Database) async throws {
		var password = ""
		var recoveryKey = ""
		for _ in 0...50 {
			password.append(String(Unicode.Scalar(Int.random(in: 33...126))!))
			recoveryKey.append(String(Unicode.Scalar(Int.random(in: 33...126))!))
		}
		// abort if no sane values or encryption fails
		guard let passwordHash = try? Bcrypt.hash(password), let recoveryHash = try? Bcrypt.hash(recoveryKey) else {
			fatalError("Moderator user creation failure: invalid password or recoveryKey")
		}
		// create user directly
		let user = User(
			username: "moderator",
			password: passwordHash,
			recoveryKey: recoveryHash,
			verification: "generated user",
			parent: nil,
			accessLevel: .moderator
		)
		try await user.save(on: database)
	}

	/// By design, nobody can log in as TwitarrTeam--the password is set to a randomly-generated value that is immediately forgotten.
	/// However, anyone with TwitarrTeam access may post content *as* TwitarrTeam, in which case the TwitarrTeam account becomes
	/// the author of the content instead of the current user.
	///
	/// ''Content' in this sense means tweets, forum posts, fez messages.
	func createTwitarrTeamUser(on database: Database) async throws {
		var password = ""
		var recoveryKey = ""
		for _ in 0...50 {
			password.append(String(Unicode.Scalar(Int.random(in: 33...126))!))
			recoveryKey.append(String(Unicode.Scalar(Int.random(in: 33...126))!))
		}
		// abort if no sane values or encryption fails
		guard let passwordHash = try? Bcrypt.hash(password), let recoveryHash = try? Bcrypt.hash(recoveryKey) else {
			fatalError("TwitarrTeam user creation failure: invalid password or recoveryKey")
		}
		// create user directly
		let user = User(
			username: "TwitarrTeam",
			password: passwordHash,
			recoveryKey: recoveryHash,
			verification: "generated user",
			parent: nil,
			accessLevel: .twitarrteam
		)
		try await user.save(on: database)
	}
}

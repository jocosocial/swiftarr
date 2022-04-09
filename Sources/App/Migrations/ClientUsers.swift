import Vapor
import Fluent
import Crypto

/// A `Migration` that creates a set of registered client users during startup, from a
/// `registered-clients.txt` file located in the `seeds/` subdirectory of the project. The file
/// must be of the format:
///
///	 clientUsername1:password1:recoveryKey1
///	 clientUsername2:password2:recoveryKey2
///	 ...
///
/// - Note: Each API client that wishes to make use of `ClientController` endpoints **must**
///  provide a client `username:password:recovery key` triplet prior to production startup.

struct CreateClientUsers: AsyncMigration {
	struct ClientUserData {
		var clientName: String
		var clientPassword: String
		var clientRecoveryKey: String
	}

	/// Required by `Migration` protocol. Reads either a test or production text file in the
	/// `seeds/` subdirectory, converts the lines into elements of an array, then iterates over
	/// them to create new `User` models with `UserAccessLevel` of `.client`.
	///
	/// - Requires: `registered-clients.txt` file in seeds subdirectory.
	/// - Parameter conn: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		// get file containing client triplets
		let clients = getClients().map { client in
			User(username: client.clientName, password: client.clientPassword, recoveryKey: client.clientRecoveryKey, accessLevel: .client)
		}
		try await clients.create(on: database)
	}
	
	/// Required by `Migration` protocol, but this isn't a model update, so just return a
	/// pre-completed `Future`.
	///
	/// - Parameter conn: The database connection.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		// get all the names of all the clients we created in prepare()
		let clientNames = getClients().map { $0.clientName }
		try await User.query(on: database).filter(\.$username ~~ clientNames).delete()
	}
	
	func getClients() -> [ClientUserData] {
		// get file containing client triplets
		let clientsFile: String
		do {
			if (try Environment.detect().isRelease) {
				// use static set of clients if just testing
				clientsFile = "registered-clients.txt"
			} else {
				clientsFile = "test-registered-clients.txt"
			}
			// read file as string
			let clientsPath = Settings.shared.seedsDirectoryPath.appendingPathComponent(clientsFile)
			guard let data = FileManager.default.contents(atPath: clientsPath.path),
					let dataString = String(bytes: data, encoding: .utf8) else {
				fatalError("Could not read clients file at \(clientsPath).")
			}
			// transform to array
			let clientsArray = dataString.components(separatedBy: .newlines)
			
			// add as `User`s
			var clients: [ClientUserData] = []
			for clientString in clientsArray {
				// stray newlines make empty elements
				guard !clientString.isEmpty else {
					continue
				}
				let triad = clientString.components(separatedBy: ":")
				// abort startup if client entry is not valid
				guard triad.count == 3 else {
					fatalError("client entry is malformed")
				}
				let clientName = triad[0].trimmingCharacters(in: .whitespaces)
				if clientName == "client" {
					continue
				}
				// normalize recoveryKey, then encrypt
				let normalizedKey = triad[2].lowercased().replacingOccurrences(of: " ", with: "")
				let password = try? Bcrypt.hash(triad[1].trimmingCharacters(in: .whitespaces))
				let recovery = try? Bcrypt.hash(normalizedKey)
				guard let passwordHash = password,
					let recoveryHash = recovery else {
						fatalError("could not create client users: password hash failed")
				}
				let newClient = ClientUserData(clientName: clientName, clientPassword: passwordHash, clientRecoveryKey:recoveryHash)
				clients.append(newClient)
			}
			return clients
		} catch let error {
			fatalError("Environment.detect() failed! error: \(error)")
		}
	}
}


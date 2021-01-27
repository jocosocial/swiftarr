import Vapor
import Fluent
import Crypto

/// A `Migration` that creates a set of registered client users during startup, from a
/// `registered-clients.txt` file located in the `seeds/` subdirectory of the project. The file
/// must be of the format:
///
///     clientUsername1:password1:recoveryKey1
///     clientUsername2:password2:recoveryKey2
///     ...
///
/// - Note: Each API client that wishes to make use of `ClientController` endpoints **must**
///  provide a client `username:password:recovery key` triplet prior to production startup.

struct CreateClientUsers: Migration {    
    /// Required by `Migration` protocol. Reads either a test or production text file in the
    /// `seeds/` subdirectory, converts the lines into elements of an array, then iterates over
    /// them to create new `User` models with `UserAccessLevel` of `.client`.
    ///
    /// - Requires: `registered-clients.txt` file in seeds subdirectory.
    /// - Parameter conn: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        // get file containing client triplets
        let clientsFile: String
        do {
            if (try Environment.detect().isRelease) {
                // use static set of clients if just testing
                clientsFile = "registered-clients.txt"
            } else {
                clientsFile = "test-registered-clients.txt"
            }
            let directoryConfig = DirectoryConfiguration.detect()
            let clientsPath = directoryConfig.workingDirectory.appending("seeds/").appending(clientsFile)
            // read file as string
            guard let data = FileManager.default.contents(atPath: clientsPath),
                let dataString = String(bytes: data, encoding: .utf8) else {
                    fatalError("Could not read clients file.")
            }
            // transform to array
            let clientsArray = dataString.components(separatedBy: .newlines)
            
            // add as `User`s
            var clients: [User] = []
            for client in clientsArray {
                // stray newlines make empty elements
                guard !client.isEmpty else {
                    continue
                }
                let triad = client.components(separatedBy: ":")
                // abort startup if client entry is not valid
                guard triad.count == 3 else {
                    fatalError("client entry is malformed")
                }
                // normalize recoveryKey, then encrypt
                let normalizedKey = triad[2].lowercased().replacingOccurrences(of: " ", with: "")
                let password = try? Bcrypt.hash(triad[1].trimmingCharacters(in: .whitespaces))
                let recovery = try? Bcrypt.hash(normalizedKey)
                guard let passwordHash = password,
                    let recoveryHash = recovery else {
                        fatalError("could not create client users: password hash failed")
                }
                let user = User(
                    username: triad[0].trimmingCharacters(in: .whitespaces),
                    password: passwordHash,
                    recoveryKey: recoveryHash,
                    accessLevel: .client
                )
                clients.append(user)
            }
            // save clients
            return clients.map { $0.save(on: database) }.flatten(on: database.eventLoop).throwingFlatMap {
                (savedUsers) in
                // add profiles
                var profiles: [UserProfile] = []
				try clients.forEach {
                    guard $0.id != nil else { fatalError("user has no id") }
                    let profile = try UserProfile(user: $0, username: $0.username)
                    profiles.append(profile)
                }
                return profiles.map { $0.save(on: database) }.flatten(on: database.eventLoop)
            }
        } catch let error {
            fatalError("Environment.detect() failed! error: \(error)")
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


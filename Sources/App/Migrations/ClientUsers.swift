import Vapor
import FluentPostgreSQL
import Crypto

/// A `Migration` that creates a set of registered client users during startup, from a
/// `registered-clients.txt` file located at the root level of the project. The file must
/// be of the format:
///
///     clientUsername1:password1:recoveryKey1
///     clientUsername2:password2:recoveryKey2
///     ...
///
/// - Note: Each API client that wishes to make use of `ClientController` endpoints **must**
///  provide a client `username:password:recovery key` triplet prior to production startup.

struct ClientUsers: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Reads either a test or production text file at the
    /// root project level, converts the lines into elements of an arrar, then iterates over
    /// them to create new `User` models with `UserAccessLevel` of `.client`.
    ///
    /// - Requires: `registered-clients.txt` file in root directory.
    /// - Parameter connection: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
         // get file containing client pairs
        let clientsFile: String
        do {
            if (try Environment.detect().isRelease) {
                // use static set of clients if just testing
                clientsFile = "registered-clients.txt"
            } else {
                clientsFile = "test-registered-clients.txt"
            }
            let directoryConfig = DirectoryConfig.detect()
            let clientsPath = directoryConfig.workDir.appending(clientsFile)
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
                let password = try? BCrypt.hash(triad[1].trimmingCharacters(in: .whitespaces))
                let recovery = try? BCrypt.hash(normalizedKey)
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
            return clients.map { $0.save(on: connection) }.flatten(on: connection).map {
                (savedUsers) in
                // add profiles
                var profiles: [UserProfile] = []
                savedUsers.forEach {
                    guard let id = $0.id else { fatalError("user has no id") }
                    let profile = UserProfile(userID: id, username: $0.username)
                    profiles.append(profile)
                }
                profiles.map { $0.save(on: connection) }.always(on: connection) { return }
            }
        } catch let error {
            fatalError("Environment.detect() failed! error: \(error)")
        }
    }
    
    /// Required by`Migration` protocol, but no point removing the client users, so
    /// just return a pre-completed `Future`.
    static func revert(on connection: PostgreSQLConnection) -> Future<Void> {
        return .done(on: connection)
    }
}


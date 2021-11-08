import Vapor
import Fluent


/// A `Migration` that populates the `RegistrationCode` database from a `registration-codes.txt`
/// file located in the `seeds/` subdirectory of the project.

struct ImportRegistrationCodes: Migration {
    
    /// Required by `Migration` protocol. Reads either a test or production text file in the
    /// `seeds/` subdirectory, converts the lines into elements of an array, then iterates over
    /// them to create new `RegistrationCode` models.
    ///
    /// - Requires: `registration-codes.txt` file in seeds subdirectory.
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void
    func prepare(on database: Database) -> EventLoopFuture<Void> {
    	database.logger.info("Starting registration code import")
        // get file containing registration codes
        let codesFile: String
        // Environment.detect() can throw, so wrap it all in do/catch
        do {
            // use static simple set of codes if just testing
            if (try Environment.detect().isRelease) {
                codesFile = "registration-codes.txt"
            } else {
                codesFile = "test-registration-codes.txt"
            }
            let directoryConfig = DirectoryConfiguration.detect()
            let codesPath = directoryConfig.workingDirectory.appending("seeds/").appending(codesFile)
            // read file as string
            guard let data = FileManager.default.contents(atPath: codesPath),
                let dataString = String(bytes: data, encoding: .utf8) else {
                    fatalError("Could not read registration codes file.")
            }
            // normalize contents
            let normalizedString = dataString.lowercased().replacingOccurrences(of: " ", with: "")
            // transform to array
            let codesArray = normalizedString.components(separatedBy: .newlines)
            
            // populate the RegistrationCodes database
            var savedCodes = [EventLoopFuture<Void>]()
            for code in codesArray {
                // stray newlines make empty elements
                guard !code.isEmpty else {
                    continue
                }
                let registrationCode = RegistrationCode(code: code)
                savedCodes.append(registrationCode.save(on: database))
            }
            // resolve the futures and return Void
            return savedCodes.flatten(on: database.eventLoop).transform(to: ())
        
        } catch let error {
            fatalError("Import Registration Codes failed! error: \(error)")
        }
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    /// 
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
		return database.schema("registrationcodes").delete()
    }
}

import Vapor
import Fluent


/// A `Migration` that populates the `RegistrationCode` database from a `registration-codes.txt`
/// file located in the `seeds/` subdirectory of the project.
/// 

// Python Test Reg Code Generator:
// for x in range(2000):
//	"".join(random.choices(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'], k=6))
	
struct ImportRegistrationCodes: AsyncMigration {
	
	/// Required by `Migration` protocol. Reads either a test or production text file in the
	/// `seeds/` subdirectory, converts the lines into elements of an array, then iterates over
	/// them to create new `RegistrationCode` models.
	///
	/// - Requires: `registration-codes.txt` file in seeds subdirectory.
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void
	func prepare(on database: Database) async throws {
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
			let codesPath = Settings.shared.seedsDirectoryPath.appendingPathComponent(codesFile)
			// read file as string
			guard let data = FileManager.default.contents(atPath: codesPath.path),
				let dataString = String(bytes: data, encoding: .utf8) else {
					fatalError("Could not read registration codes file.")
			}
			// normalize contents
			let normalizedString = dataString.lowercased().replacingOccurrences(of: " ", with: "")
			// transform to array
			let codesArray = normalizedString.components(separatedBy: .newlines)
			
			// Creating one reg code at a time is slow, but we get timeout errros if we try to stuff too many
			// creates into a single flatten. So, chunking the creates into batches of 100. 
			for startIndex in stride(from: 0, through: codesArray.count, by: 100) {
				let endIndex = min(startIndex + 100, codesArray.count)
				var regCodes: [RegistrationCode] = []
				for codeIndex in startIndex..<endIndex {
					let registrationCode = RegistrationCode(code: codesArray[codeIndex])
					regCodes.append(registrationCode)
				}
				try await regCodes.create(on: database)
				database.logger.info("Imported \(endIndex) registration codes.")
			}

		} catch let error {
			fatalError("Import Registration Codes failed! error: \(error)")
		}
	}
	
	/// Deletes all registration codes in the "registrationcode" table.
	/// 
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await RegistrationCode.query(on: database).delete()
	}
}

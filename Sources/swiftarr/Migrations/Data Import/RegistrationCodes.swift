import Fluent
import Vapor

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
			if try Environment.detect().isRelease {
				codesFile = "registration-codes.txt"
			}
			else {
				codesFile = "test-registration-codes.txt"
			}
			let codesPath = Settings.shared.seedsDirectoryPath.appendingPathComponent(codesFile)
			// read file as string
			guard let data = FileManager.default.contents(atPath: codesPath.path),
				let dataString = String(bytes: data, encoding: .utf8)
			else {
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
				for codeIndex in startIndex..<endIndex where codesArray[codeIndex].count == 6 {
					let registrationCode = RegistrationCode(code: codesArray[codeIndex])
					regCodes.append(registrationCode)
				}
				try await regCodes.create(on: database)
				database.logger.info("Imported \(endIndex) registration codes.")
			}

		}
		catch let error {
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

struct GenerateDiscordRegistrationCodes: AsyncMigration {

	/// Required by `Migration` protocol. Generates 100 unique registration codes and adds them to the regCode table as Discord codes. 
	/// Members of TwitarrTeam may then hand these codes out to Discord users via Discord private message so that Discord users can then make
	/// Twitarr accounts on the public test server. 
	/// 
	/// These registration codes all have `isDiscordUser` set to TRUE and should only exist on the public test server, not on production.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void
	func prepare(on database: Database) async throws {
		database.logger.info("Starting Discord registration code generation")
		// Do not perform this migration on the boat server
		if (try? Environment.detect().isRelease) == true {
			return
		}
		do {
			var existingCodes = try await RegistrationCode.query(on: database).all().map { $0.code }
			
			var newCodes = [RegistrationCode]()
			while newCodes.count < 100 {
				var newRegCode = ""
				for _ in 1...6 {
					newRegCode.append(String(Unicode.Scalar((Unicode.Scalar("a").value...Unicode.Scalar("z").value).randomElement()!)!))
				}
				if existingCodes.contains(newRegCode) {
					continue
				}
				existingCodes.append(newRegCode)
				let newCode = RegistrationCode(code: newRegCode, isForDiscord: true)
				newCodes.append(newCode)
			}
			try await newCodes.create(on: database)
			database.logger.info("Generated \(newCodes.count) Discord registration codes.")
		}
		catch let error {
			fatalError("Generate Discord Registration Codes failed! error: \(error)")
		}
	}

	/// Deletes all registration codes in the "registrationcode" table.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		// Always delete on revert, either it's preprod and we delete 100 codes, or prod and we delete 0 because prod has none.
		try await RegistrationCode.query(on: database).filter(\.$isDiscordUser == true).delete()
	}
}

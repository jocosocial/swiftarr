import Fluent
import Foundation
import Vapor

/// A `RegistrationCode` associates a specific pre-generated code with a specific `User`
/// account, as well as tracks when the association occurred.
///
/// To maintain accountability for conduct on Twit-arr, a user must first register their
/// primary account before gaining the ability to post any content, either public or private.
/// This is done with a unique registration code provided to each participant by Management.
/// The full set of codes (which contain no identifying information) is provided to the
/// Twit-arr admins prior to the event, and they are loaded by a `Migration` during system
/// startup.

final class RegistrationCode: Model, @unchecked Sendable {
	static let schema = "registrationcode"

	// MARK: Properties

	/// The registration code's ID, provisioned automatically.
	@ID(key: .id) var id: UUID?

	/// The registration code, normalized to lowercase without spaces.
	@Field(key: "code") var code: String
	
	/// TRUE if this reg code is allocated for members of TwitarrTeam to give to Discord users on the preprod server. Accounts created from these regcodes are 
	/// not valid on prod (and Prod should not have any regcodes with this flag set to true).
	@Field(key: "is_discord_user") var isDiscordUser: Bool
	
	/// When this regcode gets given to a Discord user, the username of the user that has it. This ties the account they eventually make to the user's Discord username.
	/// nil if this regcode has yet to be allocated to anyone. Should always be nil on production server.
	@OptionalField(key: "discord_username") var discordUsername: String?

	/// Timestamp of the model's last update, set automatically.
	/// Used to track when the code was assigned.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	// MARK: Relations

	/// The User to which this code is associated, if any.
	@OptionalParent(key: "user") var user: User?

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new RegistrationCode.
	///
	/// - Parameters:
	///   - code: The registration code string.
	init(code: String, isForDiscord: Bool = false) {
		self.code = code
		self.isDiscordUser = isForDiscord
	}
}

struct CreateRegistrationCodeSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("registrationcode")
			.id()
			.field("code", .string, .required)
			.field("updated_at", .datetime)
			.field("user", .uuid, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("registrationcode").delete()
	}
}

// Modifies the RegistrationCode table to add fields required to create the Discord-associated class of reg codes.
struct AddDiscordRegistrationMigration: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("registrationcode")
			.field("is_discord_user", .bool, .required, .sql(.default(false)))
			.field("discord_username", .string)
			.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("registrationcode")
			.deleteField("is_discord_user")
			.deleteField("discord_username")
			.update()
	}
}

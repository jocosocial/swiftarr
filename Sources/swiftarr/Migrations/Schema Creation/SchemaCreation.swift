import Fluent
import Foundation

// This file contains Migrations that create the initial database schema.
// These migrations do not migrate from an old schema to a new one--they migrate from nothing.

// This migration creates custom enum types used by the database. Other migrations then use these
// custom types to define enum-valued fields.
struct CreateCustomEnums: AsyncMigration {
	func prepare(on database: Database) async throws {
		database.logger.log(level: .info, "Starting Migrations -- Creating enums.")
		_ = try await database.enum("moderation_status")
			.case("normal")
			.case("autoQuarantined")
			.case("quarantined")
			.case("modReviewed")
			.case("locked")
			.create()
		_ = try await database.enum("user_access_level")
			.case("unverified")
			.case("banned")
			.case("quarantined")
			.case("verified")
			.case("client")
			.case("moderator")
			.case("twitarrteam")
			.case("tho")
			.case("admin")
			.create()
		_ = try await database.enum("call_in_result")
			.case("incorrect")
			.case("hint")
			.case("correct")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.enum("moderation_status").delete()
		try await database.enum("user_access_level").delete()
		try await database.enum("call_in_result").delete()
	}
}

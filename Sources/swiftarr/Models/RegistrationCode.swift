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

final class RegistrationCode: Model {
	static let schema = "registrationcode"

	// MARK: Properties

	/// The registration code's ID, provisioned automatically.
	@ID(key: .id) var id: UUID?

	/// The registration code, normalized to lowercase without spaces.
	@Field(key: "code") var code: String

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
	///   - user: The `User` to which the code is associated, `nil` if not yet
	///   assigned.
	///   - code: The registration code string.
	init(user: User? = nil, code: String) {
		self.$user.id = user?.id
		self.$user.value = user
		self.code = code
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

import Fluent
import Vapor

/// A pivot recording that a `NotificationLogEntry` was sent to a particular `User`.
///
/// Kept separate from `NotificationLogEntry` itself so a broadcast notification sent to many users
/// (e.g. an `.announcement`) stores its content once instead of once per recipient.
final class NotificationRecipient: Model, @unchecked Sendable {
	static let schema = "notification+recipient"

	// MARK: Properties

	/// The pivot's ID.
	@ID(key: .id) var id: UUID?

	// MARK: Relations

	/// The `NotificationLogEntry` that was sent.
	@Parent(key: "notification") var notification: NotificationLogEntry

	/// The `User` it was sent to.
	@Parent(key: "user") var user: User

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new NotificationRecipient.
	init(notificationID: UUID, userID: UUID) {
		self.$notification.id = notificationID
		self.$user.id = userID
	}
}

struct CreateNotificationRecipientSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("notification+recipient")
			.id()
			.field("notification", .uuid, .required, .references("notification", "id", onDelete: .cascade))
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			// `user` leads so the index serves the one read pattern this table has (GET /notification/log
			// filters by user, never by notification alone); it still enforces the same uniqueness either way.
			.unique(on: "user", "notification")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("notification+recipient").delete()
	}
}

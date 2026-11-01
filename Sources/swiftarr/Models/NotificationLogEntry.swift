import Fluent
import Vapor

/// A single notification event that was pushed to one or more users' notification websockets.
///
/// Named `NotificationLogEntry` rather than `Notification` to avoid colliding with `Foundation.Notification`
/// (NotificationCenter's type)--that name is ambiguous outside this module (e.g. in `AppTests`), where it
/// silently resolves to the wrong type instead of raising a redeclaration error.
///
/// One row is written per fan-out event, not per recipient--who received it is recorded separately in
/// `NotificationRecipient`, so a broadcast notification (e.g. an `.announcement`) sent to every user only
/// stores its content once. The row's `id` doubles as the `notificationID` included in the live
/// `SocketNotificationData` push, letting clients de-dupe a live push against a later fetch of
/// `GET /api/v3/notification/log`.
final class NotificationLogEntry: Model, @unchecked Sendable {
	static let schema = "notification"

	// MARK: Properties

	/// The entry's ID. Also sent to socket clients as `SocketNotificationData.notificationID`.
	@ID(key: .id) var id: UUID?

	/// The type of event that happened, stored as `SocketNotificationData.NotificationTypeData.databaseKey`.
	/// See `NotificationLogData.init(_:)` for how this is decoded back into a `NotificationTypeData`.
	@Field(key: "type") var typeKey: String

	/// A string describing what happened, suitable for adding to a notification alert.
	@Field(key: "info") var info: String

	/// An ID of an Announcement, Fez, Twarrt, ForumPost, or Event.
	@Field(key: "content_id") var contentID: String

	/// An ID of a related parent object, when one exists. See `SocketNotificationData.secondaryContentID`.
	@OptionalField(key: "secondary_content_id") var secondaryContentID: String?

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new NotificationLogEntry.
	init(type: SocketNotificationData.NotificationTypeData, info: String, contentID: String, secondaryContentID: String? = nil) {
		self.typeKey = type.databaseKey
		self.info = info
		self.contentID = contentID
		self.secondaryContentID = secondaryContentID
	}
}

struct CreateNotificationLogEntrySchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("notification")
			.id()
			.field("type", .string, .required)
			.field("info", .string, .required)
			.field("content_id", .string, .required)
			.field("secondary_content_id", .string)
			.field("created_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("notification").delete()
	}
}

import Fluent
import Vapor

/// Writes a durable log entry for a notification event that's about to be (or was just) pushed to live
/// sockets--see `GET /api/v3/notification/log`. One `NotificationLogEntry` row is created for the event itself,
/// plus one `NotificationRecipient` row per user in `recipients`, so a broadcast notification sent to many users
/// doesn't duplicate its content once per recipient.
///
/// The log is a convenience history, not the source of truth for notification delivery, so a failure here is
/// logged and swallowed rather than thrown--it should never prevent the actual notification from going out.
///
/// - Returns: The new entry's ID (to be included in the live socket push as `notificationID`), or nil if there
///   were no recipients or the write failed.
func logNotification(type: NotificationType, info: String, recipients: [UUID], db: Database, logger: Logger) async -> UUID? {
	guard !recipients.isEmpty else {
		return nil
	}
	let entry = NotificationLogEntry(
		type: SocketNotificationData.NotificationTypeData(type),
		info: info,
		contentID: type.objectID(),
		secondaryContentID: type.secondaryObjectID()
	)
	do {
		try await entry.save(on: db)
		let notificationID = try entry.requireID()
		try await recipients.map { NotificationRecipient(notificationID: notificationID, userID: $0) }.create(on: db)
		return notificationID
	}
	catch {
		logger.error("Failed to write notification log entry for \(type): \(error)")
		return nil
	}
}

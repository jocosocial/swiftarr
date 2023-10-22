import Fluent
import Vapor

// ChatGroups can be reported
extension ChatGroup: Reportable {
	/// The report type for `ChatGroup` reports.
	var reportType: ReportType { .chatgroup }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $owner.id }

	/// No auto quarantine for chatgroups.
	var autoQuarantineThreshold: Int { Int.max }
}

extension ChatGroup {
	func notificationType() throws -> NotificationType {
		if [.closed, .open].contains(chatGroupType) {
			return try .seamailUnreadMsg(requireID())
		}
		return try .chatGroupUnreadMsg(requireID())
	}
}

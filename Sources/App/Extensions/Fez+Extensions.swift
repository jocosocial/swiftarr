import Fluent
import Vapor

// Groups can be reported
extension FriendlyGroup: Reportable {
	/// The report type for `FriendlyGroup` reports.
	var reportType: ReportType { .group }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $owner.id }

	/// No auto quarantine for groups.
	var autoQuarantineThreshold: Int { Int.max }
}

extension FriendlyGroup {
	func notificationType() throws -> NotificationType {
		if [.closed, .open].contains(groupType) {
			return try .seamailUnreadMsg(requireID())
		}
		return try .groupUnreadMsg(requireID())
	}
}

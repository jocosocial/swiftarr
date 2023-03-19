import Fluent
import Vapor

// Fezzes can be reported
extension FriendlyFez: Reportable {
	/// The report type for `FriendlyFez` reports.
	var reportType: ReportType { .fez }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $owner.id }

	/// No auto quarantine for fezzes.
	var autoQuarantineThreshold: Int { Int.max }
}

extension FriendlyFez {
	func notificationType() throws -> NotificationType {
		if [.closed, .open].contains(fezType) {
			return try .seamailUnreadMsg(requireID())
		}
		return try .fezUnreadMsg(requireID())
	}
}

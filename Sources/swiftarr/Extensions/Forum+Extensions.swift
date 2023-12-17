import Fluent
import Vapor

// forums can be reported
extension Forum: Reportable {
	/// The report type for `Forum` reports.
	var reportType: ReportType { .forum }

	var authorUUID: UUID { $creator.id }

	var autoQuarantineThreshold: Int { Settings.shared.forumAutoQuarantineThreshold }
}

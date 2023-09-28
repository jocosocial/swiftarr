import Fluent
import Vapor

// MARK: - Functions

// groupposts can be filtered by author and content
extension GroupPost: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

// Group posts can be reported
extension GroupPost: Reportable {
	/// The report type for `GroupPost` reports.
	var reportType: ReportType { .groupPost }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $author.id }

	/// No auto quarantine for group posts.
	var autoQuarantineThreshold: Int { Int.max }
}

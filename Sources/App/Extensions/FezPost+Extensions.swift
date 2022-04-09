import Vapor
import Fluent

// MARK: - Functions

// fezposts can be filtered by author and content
extension FezPost: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

// Fez posts can be reported
extension FezPost: Reportable {
	/// The report type for `FezPost` reports.
	var reportType: ReportType { .fezPost }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $author.id }

	/// No auto quarantine for fez posts.
	var autoQuarantineThreshold: Int { Int.max }
}

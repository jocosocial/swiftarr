import Fluent
import Vapor

// MARK: - Functions

// ChatGroupPosts can be filtered by author and content
extension ChatGroupPost: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

// ChatGroup posts can be reported
extension ChatGroupPost: Reportable {
	/// The report type for `ChatGroupPost` reports.
	var reportType: ReportType { .chatGroupPost }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $author.id }

	/// No auto quarantine for chatgroup posts.
	var autoQuarantineThreshold: Int { Int.max }
}

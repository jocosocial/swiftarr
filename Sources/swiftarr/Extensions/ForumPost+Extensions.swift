import Fluent
import Vapor

// MARK: - Functions

// posts can be filtered by author and content
extension ForumPost: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

extension ForumPost: Reportable {
	var reportType: ReportType { .forumPost }

	var authorUUID: UUID { $author.id }

	var autoQuarantineThreshold: Int { Settings.shared.postAutoQuarantineThreshold }
}

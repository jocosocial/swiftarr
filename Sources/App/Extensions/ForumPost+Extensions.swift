import Vapor
import Fluent

// MARK: - Functions

// posts can be bookmarked
extension ForumPost: UserBookmarkable {
    /// The barrel type for `ForumPost` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .bookmarkedPost
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// posts can be filtered by author and content
extension ForumPost: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

extension ForumPost: Reportable {
    /// The barrel type for `ForumPost` bookmarking.
	var reportType: ReportType { .forumPost }
    
	var authorUUID: UUID { $author.id }
	
	var autoQuarantineThreshold: Int { Settings.shared.postAutoQuarantineThreshold }
}

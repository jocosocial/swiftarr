import Vapor
import Fluent

// MARK: - Functions

// twarrts can be filtered by author and content
extension Twarrt: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

// twarrts can be bookmarked
extension Twarrt: UserBookmarkable {
    /// The barrel type for `Twarrt` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .bookmarkedTwarrt
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// twarrts can be reported
extension Twarrt: Reportable {
    /// The type for `Twarrt` reports.
	var reportType: ReportType { .twarrt }
    
	var authorUUID: UUID { $author.id }
	
	var autoQuarantineThreshold: Int { Settings.shared.postAutoQuarantineThreshold }
}

import Vapor
import Fluent

// MARK: - Functions

// twarrts can be filtered by author and content
extension Twarrt: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

// twarrts can be reported
extension Twarrt: Reportable {
	/// The type for `Twarrt` reports.
	var reportType: ReportType { .twarrt }
	
	var authorUUID: UUID { $author.id }
	
	var autoQuarantineThreshold: Int { Settings.shared.postAutoQuarantineThreshold }
}

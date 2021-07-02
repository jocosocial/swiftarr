import Vapor
import Fluent


// forums can be bookmarked
extension Forum: UserBookmarkable {
    /// The barrel type for `Twarrt` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .taggedForum
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// forums can be reported
extension Forum: Reportable {
    /// The report type for `Forum` reports.
	var reportType: ReportType { .forum }
    
	var authorUUID: UUID { $creator.id }

	var autoQuarantineThreshold: Int { Settings.shared.forumAutoQuarantineThreshold }
}

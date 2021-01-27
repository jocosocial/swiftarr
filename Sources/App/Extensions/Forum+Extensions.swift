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
	var reportType: ReportType {
        return .forum
    }
    
	func checkAutoQuarantine(reportCount: Int, on req: Request) -> EventLoopFuture<Void> {
		// quarantine if threshold is met
		// FIXME: use separate lock from user's
		// FIXME: Also, this will re-lock the forum on every new report, even after
		// mod review. Add self.isReviewed to forums.
		if reportCount >= Settings.shared.forumAutoQuarantineThreshold {
			self.isLocked = true
			return self.save(on: req.db)
		}
		return req.eventLoop.future()
	}
}

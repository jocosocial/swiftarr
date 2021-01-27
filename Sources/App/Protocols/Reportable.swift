import Vapor
import Fluent

protocol Reportable {
	/// The type of report to use when reportong on this object type.
	var reportType: ReportType { get }
	
	func checkAutoQuarantine(reportCount: Int, on req: Request) -> EventLoopFuture<Void>
}

extension Reportable {
	
	func fileReport(_ report: Report, on req: Request) -> EventLoopFuture<HTTPStatus> {
		return Report.query(on: req.db)
		.filter(\.$reportedID == report.reportedID)
		.filter(\.$submitter.$id == report.$submitter.id)
		.count()
		.flatMap { (count) in
			guard count == 0 else {
				return req.eventLoop.makeFailedFuture(Abort(.conflict, reason: "user has already reported this"))
			}
			return report.save(on: req.db).flatMap { (_) in
				// quarantine if threshold is met
				return Report.query(on: req.db)
					.filter(\.$reportedID == report.reportedID)
					.count()
					.flatMap { (reportCount) in
						self.checkAutoQuarantine(reportCount: reportCount, on: req)
								.transform(to: .created)
					}
			}
		}
	}
}

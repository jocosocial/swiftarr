import Vapor
import Fluent

protocol Reportable: Model {
	/// The type of report to use when reportong on this object type.
	var reportType: ReportType { get }
	
    /// The UUID of the content's author.
	var authorUUID: UUID { get }	
	
	/// How many reports on this type of content must accrue before triggering auto-quarantine.
	var autoQuarantineThreshold: Int { get }

	/// Things that can get reported can get moderated by the mod team. This shows the moderation status of the reportable item.
	var moderationStatus: ContentModerationStatus { get set }
		
	/// The database ID of the content. Depending on `reportType`, this could encode either a UUID or an Int. Don't use this for concrete types
	/// where the actual @id type is available.
	func reportableContentID() throws -> String
}

extension Reportable {

	// TRUE if the content's moderation state is .quarantined or .autoquarantined. If true, the content should be hidden from
	// users without moderator access level, replaced with something like "This content is under review."
	var isQuarantined: Bool { self.moderationStatus == .quarantined || self.moderationStatus == .autoQuarantined }
	
	/// Creates and saves a Report. Reports are always submitted by the parent account of any sub-account. 
	/// A user may only file one report against a piece of content.
	/// If enough reports are filed against the same piece of content, this function will mark the content auto-quarantined.
	func fileReport(submitter: User, submitterMessage: String, on req: Request) throws -> EventLoopFuture<HTTPStatus> {
		return try submitter.parentAccount(on: req).throwingFlatMap { parent in
			let report = try Report(reportedContent: self, submitter: parent, submitterMessage: submitterMessage)
			return Report.query(on: req.db)
					.filter(\.$reportType == report.reportType)
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
							.filter(\.$reportType == report.reportType)
							.filter(\.$reportedID == report.reportedID)
							.count()
							.flatMap { (reportCount) in
						// As a comporomise between re-quarantining for every report after the threshold is met
						// and making already-reviewed posts immune from auto-quarantine (remember the user can in some
						// cases still edit their post after it's reviewed) this code re-quarantines after another
						// <Threshold> more reports come in.
						if reportCount >= self.autoQuarantineThreshold &&
								(reportCount % self.autoQuarantineThreshold == 0) && 
								self.moderationStatus == .normal {
							self.moderationStatus = .autoQuarantined
							return self.save(on: req.db).transform(to: .created)
						}
						return req.eventLoop.future(.created)
					}
				}
			}
		}
	}
	
	/// If the change being made to the receiver is a mod exercising their mod powers, record the change in the ModeratorAction log.
	/// If the change isn't the result of mod powers, do nothing. Most calls don't need to wait for completion, and can ignore the result.
	/// Only call this function after you're sure the action is actually going to occur.
	@discardableResult func logIfModeratorAction(_ action: ModeratorActionType, user: User, on req: Request) -> EventLoopFuture<Void> {
		// Only log actions where a mod has to use their mod powers. That is, if a mod deletes their own tweet, don't log it.
		// I believe "mod powers" == any change to content where the user making the change isn't the user who created the content.
		// But, there's edge cases, such as a mod editing @admin auto-generated content, or one mod updating a post made by another mod.
		do {
			guard try authorUUID != user.requireID() else {
				return req.eventLoop.future()
			}
			let modAction = try ModeratorAction(content: self, action: action, moderator: user)
			return modAction.save(on: req.db)
		}
		catch {
			req.logger.report(error: error)
		}
		return req.eventLoop.future()
	}
}

extension Reportable where IDValue == Int {
    func reportableContentID() throws -> String { try String(requireID()) }
}

extension Reportable where IDValue == UUID {
    func reportableContentID() throws -> String { try String(requireID()) }
}

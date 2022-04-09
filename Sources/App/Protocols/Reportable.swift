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
	func fileReport(submitter: UserCacheData, submitterMessage: String, on req: Request) async throws -> HTTPStatus {
		guard let submitterUser = try await User.find(submitter.userID, on: req.db) else {
			throw Abort(.internalServerError, reason: "No User record matching UserCacheData")
		}
		let parent = try await submitterUser.parentAccount(on: req)
		let report = try Report(reportedContent: self, submitter: parent, submitterMessage: submitterMessage)
		let alreadyReportedCount = try await Report.query(on: req.db)
					.filter(\.$reportType == report.reportType)
					.filter(\.$reportedID == report.reportedID)
					.filter(\.$submitter.$id == report.$submitter.id)
					.count()
		guard alreadyReportedCount == 0 else {
			throw Abort(.conflict, reason: "user has already reported this")
		}
		try await report.save(on: req.db)
		// quarantine if threshold is met
		let reportCount = try await Report.query(on: req.db)
				.filter(\.$reportType == report.reportType)
				.filter(\.$reportedID == report.reportedID)
				.count()
		// As a comporomise between re-quarantining for every report after the threshold is met
		// and making already-reviewed posts immune from auto-quarantine (remember the user can in some
		// cases still edit their post after it's reviewed) this code re-quarantines after another
		// <Threshold> more reports come in.
		if reportCount >= self.autoQuarantineThreshold &&
				(reportCount % self.autoQuarantineThreshold == 0) && 
				moderationStatus == .normal {
			moderationStatus = .autoQuarantined
			try await save(on: req.db)
		}
		return .created
	}
	
	/// If the change being made to the receiver is a mod exercising their mod powers, record the change in the ModeratorAction log.
	/// If the change isn't the result of mod powers, do nothing. Most calls don't need to wait for completion, and can ignore the result.
	/// Only call this function after you're sure the action is actually going to occur.
	func logIfModeratorAction(_ action: ModeratorActionType, user: UserCacheData, on req: Request) async {
		// Only log actions where a mod has to use their mod powers. That is, if a mod deletes their own tweet, don't log it.
		// I believe "mod powers" == any change to content where the user making the change isn't the user who created the content.
		// But, there's edge cases, such as a mod editing @admin auto-generated content, or one mod updating a post made by another mod.
		do {
			guard authorUUID != user.userID else {
				return
			}
			if let modUser = try await User.find(user.userID, on: req.db) {
				let modAction = try ModeratorAction(content: self, action: action, moderator: modUser)
				try await modAction.save(on: req.db)
			}
		}
		catch {
			req.logger.report(error: error)
		}
	}
	
	/// If the change being made to the receiver is a mod exercising their mod powers, record the change in the ModeratorAction log.
	/// If the change isn't the result of mod powers, do nothing. Most calls don't need to wait for completion, and can ignore the result.
	/// Only call this function after you're sure the action is actually going to occur.
	func logIfModeratorAction(_ action: ModeratorActionType, moderatorID: UUID, on req: Request) async throws {
		// Only log actions where a mod has to use their mod powers. That is, if a mod deletes their own tweet, don't log it.
		// I believe "mod powers" == any change to content where the user making the change isn't the user who created the content.
		// But, there's edge cases, such as a mod editing @admin auto-generated content, or one mod updating a post made by another mod.
		guard authorUUID != moderatorID else {
			return
		}
		do {
			if let moderator = try await User.find(moderatorID, on: req.db) {
				let modAction = try ModeratorAction(content: self, action: action, moderator: moderator)
				try await modAction.save(on: req.db)
			}
		}
		catch {
			req.logger.report(error: error)
		}
	}
}

extension Reportable where IDValue == Int {
	func reportableContentID() throws -> String { try String(requireID()) }
}

extension Reportable where IDValue == UUID {
	func reportableContentID() throws -> String { try String(requireID()) }
}

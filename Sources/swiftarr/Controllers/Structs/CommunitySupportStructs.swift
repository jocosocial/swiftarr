import Vapor

// DTOs for the Community Support report API (`/api/v3/communitysupport/*`), served by `CommunitySupportController`.

/// Used to file a Community Support report. Only Community Support role holders may submit one.
///
/// Required: `memberName`, `experienceTime`, `experienceLocation`, `experienceDescription`.
///
/// Submitted to: `POST /api/v3/communitysupport/report`
public struct CommunitySupportReportCreateData: Content {
	/// The name of the team member filing the report.
	var memberName: String
	/// Name of the reporter. Optional.
	var reporterName: String?
	/// The reporter's account, if they have one and the team member picked it.
	var reporterUserID: UUID?
	/// Free-text handle for the reporter, if not picked from the user list.
	var reporterHandleText: String?
	var reporterCabin: String?
	/// The person the report is about, if picked from the user list.
	var subjectUserID: UUID?
	/// Free-text name of the person the report is about.
	var subjectName: String?
	/// The reporter experienced this themselves.
	var reporterExperienced: Bool
	/// The reporter witnessed this happen to someone else.
	var reporterWitnessed: Bool
	/// Whether the reporter wants follow-up. `infoOnly` or `followUp`.
	var intent: CommunitySupportReportIntent
	/// May JoCo Cruise contact the reporter?
	var mayContact: Bool
	/// When it happened, in the reporter's words.
	var experienceTime: String
	var experienceLocation: String
	var experienceDescription: String
	var preferredOutcome: String?
	var livedExperiences: String?
}

extension CommunitySupportReportCreateData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(!memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, forKey: .memberName, or: "member name is required")
		tester.validate(memberName.count <= 100, forKey: .memberName, or: "member name has a 100 character limit")
		tester.validate(
			!experienceTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			forKey: .experienceTime,
			or: "when it happened is required"
		)
		tester.validate(experienceTime.count <= 200, forKey: .experienceTime, or: "time has a 200 character limit")
		tester.validate(
			!experienceLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			forKey: .experienceLocation,
			or: "location is required"
		)
		tester.validate(experienceLocation.count <= 200, forKey: .experienceLocation, or: "location has a 200 character limit")
		tester.validate(
			!experienceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			forKey: .experienceDescription,
			or: "description is required"
		)
		tester.validate(
			experienceDescription.count <= 10_000,
			forKey: .experienceDescription,
			or: "description has a 10000 character limit"
		)
		tester.validate((preferredOutcome ?? "").count <= 5_000, forKey: .preferredOutcome, or: "preferred outcome has a 5000 character limit")
		tester.validate((livedExperiences ?? "").count <= 5_000, forKey: .livedExperiences, or: "lived experiences has a 5000 character limit")
		tester.validate((reporterName ?? "").count <= 100, forKey: .reporterName, or: "reporter name has a 100 character limit")
		tester.validate((reporterHandleText ?? "").count <= 100, forKey: .reporterHandleText, or: "reporter handle has a 100 character limit")
		tester.validate((reporterCabin ?? "").count <= 50, forKey: .reporterCabin, or: "cabin has a 50 character limit")
		tester.validate((subjectName ?? "").count <= 100, forKey: .subjectName, or: "subject name has a 100 character limit")
	}
}

/// Used to change a report's status, optionally with a note explaining why.
///
/// Submitted to: `POST /api/v3/communitysupport/report/:report_id/status`
public struct CommunitySupportStatusChangeData: Content {
	/// The new status: `new`, `inProgress`, `resolved`, or `infoOnly`.
	var status: CommunitySupportReportStatus
	var note: String?
}

extension CommunitySupportStatusChangeData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate((note ?? "").count <= 5_000, forKey: .note, or: "note has a 5000 character limit")
	}
}

/// Used to add a comment to a report.
///
/// Submitted to: `POST /api/v3/communitysupport/report/:report_id/note`
public struct CommunitySupportNoteData: Content {
	var note: String
}

extension CommunitySupportNoteData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(!note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, forKey: .note, or: "note cannot be empty")
		tester.validate(note.count <= 5_000, forKey: .note, or: "note has a 5000 character limit")
	}
}

/// One entry in the Community Support log.
///
/// Returned by: `GET /api/v3/communitysupport/actionlog`, and inside `CommunitySupportReportData`.
public struct CommunitySupportActionData: Content {
	var id: UUID
	var actionType: CommunitySupportActionType
	/// A readable name for `actionType`, suitable for showing directly.
	var actionLabel: String
	/// The team member who did it.
	var actor: UserHeader
	/// The report it was done to. Nil for team-wide entries.
	var reportID: UUID?
	var oldStatus: CommunitySupportReportStatus?
	var newStatus: CommunitySupportReportStatus?
	/// The text of a note, or empty.
	var note: String
	var createdAt: Date
}

extension CommunitySupportActionData {
	init(_ action: CommunitySupportAction, on req: Request) throws {
		self.id = try action.requireID()
		self.actionType = action.actionType
		self.actionLabel = action.actionType.label
		self.actor = try req.userCache.getHeader(action.$actor.id)
		self.reportID = action.$report.id
		self.oldStatus = action.oldStatus
		self.newStatus = action.newStatus
		self.note = action.note
		self.createdAt = action.createdAt ?? Date()
	}
}

/// A row in the report queue.
///
/// Returned by: `GET /api/v3/communitysupport/reports`
public struct CommunitySupportReportListData: Content {
	var id: UUID
	var createdAt: Date
	var status: CommunitySupportReportStatus
	var statusLabel: String
	var intent: CommunitySupportReportIntent
	/// Where it happened, in the reporter's words.
	var experienceLocation: String
	/// The team member who filed it.
	var author: UserHeader
	/// True if a discussion thread has been started in the private forum.
	var hasDiscussion: Bool
}

extension CommunitySupportReportListData {
	init(_ report: CommunitySupportReport, hasDiscussion: Bool, on req: Request) throws {
		self.id = try report.requireID()
		self.createdAt = report.createdAt ?? Date()
		self.status = report.status
		self.statusLabel = report.status.label
		self.intent = report.intent
		self.experienceLocation = report.experienceLocation
		self.author = try req.userCache.getHeader(report.$author.id)
		self.hasDiscussion = hasDiscussion
	}
}

/// A whole report with its timeline.
///
/// Returned by: `POST /api/v3/communitysupport/report`, `GET /api/v3/communitysupport/report/:report_id`
public struct CommunitySupportReportData: Content {
	var id: UUID
	var createdAt: Date
	var updatedAt: Date
	var status: CommunitySupportReportStatus
	var statusLabel: String
	/// The team member who filed it.
	var author: UserHeader
	var memberName: String
	var reporterName: String
	var reporter: UserHeader?
	var reporterHandleText: String
	var reporterCabin: String
	var subject: UserHeader?
	var subjectName: String
	var reporterExperienced: Bool
	var reporterWitnessed: Bool
	var intent: CommunitySupportReportIntent
	var mayContact: Bool
	var experienceTime: String
	var experienceLocation: String
	var experienceDescription: String
	var preferredOutcome: String
	var livedExperiences: String
	/// The discussion thread in the private Community Support forum, if one has been started. Open it at `/api/v3/forum/ID`.
	var forumID: UUID?
	/// Everything done to this report, oldest first.
	var actions: [CommunitySupportActionData]
}

extension CommunitySupportReportData {
	/// - Parameter forumID: The report's discussion thread, if it still exists. Pass this rather than `report.$forum.id`, which still points at
	///   a thread that has been (soft) deleted.
	init(_ report: CommunitySupportReport, actions: [CommunitySupportAction], forumID: UUID?, on req: Request) throws {
		self.id = try report.requireID()
		self.createdAt = report.createdAt ?? Date()
		self.updatedAt = report.updatedAt ?? Date()
		self.status = report.status
		self.statusLabel = report.status.label
		self.author = try req.userCache.getHeader(report.$author.id)
		self.memberName = report.memberName
		self.reporterName = report.reporterName
		self.reporter = try report.$reporter.id.map { try req.userCache.getHeader($0) }
		self.reporterHandleText = report.reporterHandleText
		self.reporterCabin = report.reporterCabin
		self.subject = try report.$subject.id.map { try req.userCache.getHeader($0) }
		self.subjectName = report.subjectName
		self.reporterExperienced = report.reporterExperienced
		self.reporterWitnessed = report.reporterWitnessed
		self.intent = report.intent
		self.mayContact = report.mayContact
		self.experienceTime = report.experienceTime
		self.experienceLocation = report.experienceLocation
		self.experienceDescription = report.experienceDescription
		self.preferredOutcome = report.preferredOutcome
		self.livedExperiences = report.livedExperiences
		self.forumID = forumID
		self.actions = try actions.map { try CommunitySupportActionData($0, on: req) }
	}
}

/// The result of asking for a report's discussion thread.
///
/// Returned by: `POST /api/v3/communitysupport/report/:report_id/discussion`
public struct CommunitySupportDiscussionData: Content {
	/// The thread in the private Community Support forum. Open it at `/api/v3/forum/ID`.
	var forumID: UUID
	/// True if this request started the thread; false if the report already had one.
	var created: Bool
}

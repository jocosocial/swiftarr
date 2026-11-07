import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/communitysupport/*` route endpoints and handler functions for Community Support reports.
///
/// Community Support team members (holders of `UserRoleType.communitysupport`) file reports about things attendees tell them. Anyone on the team,
/// and TwitarrTeam and above, can read the reports, change their status, comment on them, and start or open a discussion thread about one in the
/// private Community Support forum category. Plain moderators have no access. Everything is recorded in an append-only log.
///
/// - Important: `allowedRoles` and `minAccess` are OR'd by `MinUserAccessLevelMiddleware`, and `minAccess` defaults to `.banned`--so a
///   role-only route that omits `minAccess` would admit every logged-in user. Every route here sets `minAccess` explicitly.
struct CommunitySupportController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		let baseRoutes = app.grouped("api", "v3", "communitysupport")

		// Filing a report is for the team only; TwitarrTeam can read but not write on the team's behalf.
		let memberAuthGroup = baseRoutes.tokenRoutes(feature: .communitySupport, minAccess: .admin, allowedRoles: [.communitysupport])
		memberAuthGroup.post("report", use: createReportHandler)

		// Everything else: role holders, or TwitarrTeam and above.
		let teamAuthGroup = baseRoutes.tokenRoutes(feature: .communitySupport, minAccess: .twitarrteam, allowedRoles: [.communitysupport])
		teamAuthGroup.get("reports", use: reportsHandler)
		teamAuthGroup.get("report", reportIDParam, use: reportHandler)
		teamAuthGroup.post("report", reportIDParam, "status", use: statusHandler)
		teamAuthGroup.post("report", reportIDParam, "note", use: noteHandler)
		teamAuthGroup.post("report", reportIDParam, "discussion", use: discussionHandler)
		teamAuthGroup.get("actionlog", use: actionLogHandler)

		// Bulk export is for THO and above only; not even the team itself, and not TwitarrTeam.
		let thoAuthGroup = baseRoutes.tokenRoutes(feature: .communitySupport, minAccess: .tho)
		thoAuthGroup.get("export", use: exportHandler)
	}

	// MARK: - Access

	/// Whether the user is on the Community Support team, or is TwitarrTeam or above.
	static func canAccess(_ user: UserCacheData) -> Bool {
		user.userRoles.contains(.communitysupport) || user.accessLevel.hasAccess(.twitarrteam)
	}

	/// Throws 403 unless the user is on the Community Support team, or is TwitarrTeam or above. The route middleware already checks this; the in-handler
	/// check keeps a route that's mistakenly registered without the right group from becoming open.
	private func guardCanAccess(_ user: UserCacheData) throws {
		guard Self.canAccess(user) else {
			throw Abort(.forbidden, reason: "Community Support access required.")
		}
	}

	// MARK: - Handlers

	/// `POST /api/v3/communitysupport/report`
	///
	/// Files a Community Support report. Only Community Support role holders can file reports.
	///
	/// - Parameter requestBody: `CommunitySupportReportCreateData`
	/// - Throws: 403 if the user doesn't hold the Community Support role.
	/// - Returns: 201 Created with a `CommunitySupportReportData`.
	func createReportHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.userRoles.contains(.communitysupport) else {
			throw Abort(.forbidden, reason: "Only Community Support team members can file reports.")
		}
		// see `CommunitySupportReportCreateData.runValidations(using:)`
		let data = try ValidatingJSONDecoder().decode(CommunitySupportReportCreateData.self, fromBodyOf: req)
		try await guardUserExists(data.reporterUserID, on: req)
		try await guardUserExists(data.subjectUserID, on: req)
		let report = CommunitySupportReport(author: cacheUser.userID, data: data)
		let action = try await req.db.transaction { db -> CommunitySupportAction in
			try await report.save(on: db)
			let action = CommunitySupportAction(actor: cacheUser.userID, report: try report.requireID(), type: .reportCreated, newStatus: report.status)
			try await action.save(on: db)
			return action
		}
		let reportData = try CommunitySupportReportData(report, actions: [action], forumID: nil, on: req)
		let response = Response(status: .created)
		try response.content.encode(reportData)
		return response
	}

	/// `GET /api/v3/communitysupport/reports`
	///
	/// The report queue, newest first.
	///
	/// **URL Query Parameters:**
	/// - status=STRING	Only reports with this status: `new`, `inProgress`, `resolved`, or `infoOnly`. May be given more than once.
	/// - start=INT, limit=INT	Pagination.
	///
	/// - Returns: `Paginated<CommunitySupportReportListData>`
	func reportsHandler(_ req: Request) async throws -> Paginated<CommunitySupportReportListData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try guardCanAccess(cacheUser)
		let pagination = Pagination(on: req, maxPageSize: 200)
		let query = CommunitySupportReport.query(on: req.db)
		let statusStrings: [String] = (try? req.query.get([String].self, at: "status")) ?? []
		if !statusStrings.isEmpty {
			let statuses = try statusStrings.map { string -> CommunitySupportReportStatus in
				guard let status = CommunitySupportReportStatus(rawValue: string) else {
					throw Abort(.badRequest, reason: "Unknown status value '\(string)'.")
				}
				return status
			}
			query.filter(\.$status ~~ statuses)
		}
		let total = try await query.count()
		let reports = try await query.copy().sort(\.$createdAt, .descending).range(pagination.range).all()
		let liveForums = try await liveForumIDs(for: reports, on: req.db)
		let items = try reports.map {
			try CommunitySupportReportListData($0, hasDiscussion: $0.$forum.id.map { liveForums.contains($0) } ?? false, on: req)
		}
		return Paginated(items: items, paginator: Paginator(total: total, start: pagination.start, limit: pagination.limit))
	}

	/// `GET /api/v3/communitysupport/report/:report_id`
	///
	/// One report, with its timeline.
	///
	/// - Returns: `CommunitySupportReportData`
	func reportHandler(_ req: Request) async throws -> CommunitySupportReportData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try guardCanAccess(cacheUser)
		let report = try await CommunitySupportReport.findFromParameter(reportIDParam, on: req)
		return try await buildReportData(report, on: req)
	}

	/// `POST /api/v3/communitysupport/report/:report_id/status`
	///
	/// Changes a report's status, optionally with a note saying why.
	///
	/// - Parameter requestBody: `CommunitySupportStatusChangeData`
	/// - Throws: 400 if the status is unknown or is already the report's status.
	/// - Returns: The updated `CommunitySupportReportData`.
	func statusHandler(_ req: Request) async throws -> CommunitySupportReportData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try guardCanAccess(cacheUser)
		let data = try ValidatingJSONDecoder().decode(CommunitySupportStatusChangeData.self, fromBodyOf: req)
		let report = try await CommunitySupportReport.findFromParameter(reportIDParam, on: req)
		guard report.status != data.status else {
			throw Abort(.badRequest, reason: "Report status is already \(data.status.label).")
		}
		let oldStatus = report.status
		report.status = data.status
		let note = (data.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		try await req.db.transaction { db in
			try await report.save(on: db)
			try await CommunitySupportAction(
				actor: cacheUser.userID,
				report: try report.requireID(),
				type: .statusChanged,
				oldStatus: oldStatus,
				newStatus: data.status,
				note: note
			).save(on: db)
		}
		return try await buildReportData(report, on: req)
	}

	/// `POST /api/v3/communitysupport/report/:report_id/note`
	///
	/// Adds a comment to a report.
	///
	/// - Parameter requestBody: `CommunitySupportNoteData`
	/// - Returns: The updated `CommunitySupportReportData`.
	func noteHandler(_ req: Request) async throws -> CommunitySupportReportData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try guardCanAccess(cacheUser)
		let data = try ValidatingJSONDecoder().decode(CommunitySupportNoteData.self, fromBodyOf: req)
		let report = try await CommunitySupportReport.findFromParameter(reportIDParam, on: req)
		try await CommunitySupportAction(
			actor: cacheUser.userID,
			report: try report.requireID(),
			type: .noteAdded,
			note: data.note.trimmingCharacters(in: .whitespacesAndNewlines)
		).save(on: req.db)
		return try await buildReportData(report, on: req)
	}

	/// `POST /api/v3/communitysupport/report/:report_id/discussion`
	///
	/// Starts a discussion thread about the report in the private Community Support forum category, or--if one already exists--returns it.
	/// The first post of a new thread is a full copy of the report (cut down to fit the forum's post length limit), and the thread's ID is
	/// recorded on the report. Two people asking at the same moment get the same thread.
	///
	/// - Returns: `CommunitySupportDiscussionData`
	func discussionHandler(_ req: Request) async throws -> CommunitySupportDiscussionData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try guardCanAccess(cacheUser)
		let reportID = try UUID(uuidString: req.parameters.get(reportIDParam.paramString) ?? "")
			?? { throw Abort(.badRequest, reason: "Request parameter \(reportIDParam.paramString) is missing.") }()
		// Serialize per report, so two people clicking at once get one thread. This is deliberately not a database transaction: starting the thread
		// takes more connections from the (small) pool, and holding one open across that can deadlock concurrent requests. It's an in-process lock,
		// which is enough for a single-instance deployment.
		await Self.discussionLock.lock(reportID)
		do {
			let result = try await findOrCreateDiscussion(reportID: reportID, cacheUser: cacheUser, on: req)
			await Self.discussionLock.unlock(reportID)
			return result
		}
		catch {
			await Self.discussionLock.unlock(reportID)
			throw error
		}
	}

	/// Serializes `discussionHandler` per report.
	static let discussionLock = KeyedAsyncLock()

	/// The body of `discussionHandler`. Callers must hold `discussionLock` for the report.
	private func findOrCreateDiscussion(reportID: UUID, cacheUser: UserCacheData, on req: Request) async throws
		-> CommunitySupportDiscussionData
	{
		guard let report = try await CommunitySupportReport.find(reportID, on: req.db) else {
			throw Abort(.notFound, reason: "Report not found.")
		}
		if let existingID = report.$forum.id, try await Forum.find(existingID, on: req.db) != nil {
			return CommunitySupportDiscussionData(forumID: existingID, created: false)
		}
		guard let category = try await Category.query(on: req.db).filter(\.$requiredRole == .communitysupport).first() else {
			throw Abort(.internalServerError, reason: "The Community Support forum category doesn't exist.")
		}
		let (forum, _) = try await ForumController().createForum(
			in: category,
			title: report.discussionTitle(),
			text: report.discussionPostText(),
			effectiveAuthor: cacheUser,
			actingUser: cacheUser,
			on: req
		)
		let forumID = try forum.requireID()
		report.$forum.id = forumID
		try await report.save(on: req.db)
		try await CommunitySupportAction(actor: cacheUser.userID, report: reportID, type: .discussionStarted).save(on: req.db)
		return CommunitySupportDiscussionData(forumID: forumID, created: true)
	}

	/// `GET /api/v3/communitysupport/actionlog`
	///
	/// The team-wide audit log: everything done to any report, newest first.
	///
	/// **URL Query Parameters:**
	/// - start=INT, limit=INT	Pagination.
	///
	/// - Returns: `Paginated<CommunitySupportActionData>`
	func actionLogHandler(_ req: Request) async throws -> Paginated<CommunitySupportActionData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try guardCanAccess(cacheUser)
		let pagination = Pagination(on: req, maxPageSize: 200)
		let total = try await CommunitySupportAction.query(on: req.db).count()
		let actions = try await CommunitySupportAction.query(on: req.db).sort(\.$createdAt, .descending).range(pagination.range).all()
		let items = try actions.map { try CommunitySupportActionData($0, on: req) }
		return Paginated(items: items, paginator: Paginator(total: total, start: pagination.start, limit: pagination.limit))
	}

	/// `GET /api/v3/communitysupport/export`
	///
	/// Every Community Support report, oldest first, for a CSV download. THO and above only. Each export is recorded in the action log.
	/// The returned reports' `actions` arrays are empty; use `GET /report/:report_id` for a report's timeline.
	///
	/// - Returns: `[CommunitySupportReportData]`
	func exportHandler(_ req: Request) async throws -> [CommunitySupportReportData] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO access required.")
		}
		let reports = try await CommunitySupportReport.query(on: req.db).sort(\.$createdAt, .ascending).all()
		let liveForums = try await liveForumIDs(for: reports, on: req.db)
		let result = try reports.map { report in
			try CommunitySupportReportData(
				report,
				actions: [],
				forumID: report.$forum.id.flatMap { liveForums.contains($0) ? $0 : nil },
				on: req
			)
		}
		try await CommunitySupportAction(
			actor: cacheUser.userID,
			report: nil,
			type: .reportsExported,
			note: "\(result.count) reports"
		).save(on: req.db)
		return result
	}

	// MARK: - Utilities

	/// Builds the full report DTO: the report, its timeline oldest first, and its discussion thread if that still exists.
	func buildReportData(_ report: CommunitySupportReport, on req: Request) async throws -> CommunitySupportReportData {
		let actions = try await report.$actions.query(on: req.db).sort(\.$createdAt, .ascending).all()
		let forumID = try await liveForumIDs(for: [report], on: req.db).first
		return try CommunitySupportReportData(report, actions: actions, forumID: forumID, on: req)
	}

	/// Of the discussion threads the given reports point at, the IDs of the ones that haven't been deleted. A soft-deleted forum leaves its ID
	/// on the report, so the stored ID alone can't be trusted.
	func liveForumIDs(for reports: [CommunitySupportReport], on db: Database) async throws -> Set<UUID> {
		let forumIDs = reports.compactMap { $0.$forum.id }
		guard !forumIDs.isEmpty else {
			return []
		}
		return Set(try await Forum.query(on: db).filter(\.$id ~~ forumIDs).all().compactMap { $0.id })
	}

	/// Throws 400 if a user ID is given but no such user exists.
	private func guardUserExists(_ userID: UUID?, on req: Request) async throws {
		if let userID = userID, req.userCache.getUser(userID) == nil {
			throw Abort(.badRequest, reason: "User \(userID) not found.")
		}
	}
}

/// A mutual-exclusion lock keyed by ID: callers asking for the same key wait their turn, and callers with different keys don't affect each other.
actor KeyedAsyncLock {
	private var held: Set<UUID> = []
	private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

	/// Waits until nobody else holds `key`, then holds it. Every `lock` must be paired with an `unlock`.
	func lock(_ key: UUID) async {
		if held.contains(key) {
			await withCheckedContinuation { waiters[key, default: []].append($0) }
		}
		else {
			held.insert(key)
		}
	}

	/// Releases `key`, handing it straight to the longest waiter if there is one.
	func unlock(_ key: UUID) {
		if var queue = waiters[key], !queue.isEmpty {
			let next = queue.removeFirst()
			waiters[key] = queue.isEmpty ? nil : queue
			next.resume()
		}
		else {
			held.remove(key)
		}
	}
}

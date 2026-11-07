import Vapor

/// The site routes under `/communitysupport`: filing and reviewing Community Support reports, the action log, and a CSV export.
///
/// Like the other site controllers these call the API (`CommunitySupportController`) rather than touching the database, so every
/// access rule lives in one place. These are all private routes: they never accept token auth, and aren't shareable between users.
struct SiteCommunitySupportController: SiteControllerUtils {

	/// Form data posted by the report form. Checkboxes are absent when unchecked.
	struct ReportFormContent: Codable {
		var memberName: String
		var reporterName: String?
		var reporterHandle: String?
		var reporterCabin: String?
		var subjectHandle: String?
		var reporterExperienced: Bool?
		var reporterWitnessed: Bool?
		var intent: CommunitySupportReportIntent
		var mayContact: Bool?
		var experienceTime: String
		var experienceLocation: String
		var experienceDescription: String
		var preferredOutcome: String?
		var livedExperiences: String?
	}

	/// Form data posted by the status form.
	struct StatusFormContent: Codable {
		var status: CommunitySupportReportStatus
		var note: String?
	}

	func registerRoutes(_ app: Application) throws {
		// Role holders, and TwitarrTeam and above. (`minAccess` defaults to `.banned`, and role/level are OR'd, so a role-only group
		// must pass `minAccess` explicitly or it would admit everybody.)
		let teamRoutes = getPrivateRoutes(
			app,
			feature: .communitySupport,
			minAccess: .twitarrteam,
			allowedRoles: [.communitysupport],
			path: "communitysupport"
		)
		teamRoutes.get(use: root)
		teamRoutes.get("reports", use: reports)
		teamRoutes.get("report", reportIDParam, use: report)
		teamRoutes.post("report", reportIDParam, "status", use: postStatus)
		teamRoutes.post("report", reportIDParam, "discussion", use: postDiscussion)
		teamRoutes.get("log", use: actionLog)
		teamRoutes.get("seamail") { req -> Response in req.redirect(to: "/seamail?foruser=communitysupport") }

		// Only role holders file reports.
		let memberRoutes = getPrivateRoutes(
			app,
			feature: .communitySupport,
			minAccess: .admin,
			allowedRoles: [.communitysupport],
			path: "communitysupport"
		)
		memberRoutes.get("newreport", use: reportForm)
		memberRoutes.post("report", use: postReport)

		// THO and above only, role or not.
		let thoRoutes = getPrivateRoutes(app, feature: .communitySupport, minAccess: .tho, path: "communitysupport")
		thoRoutes.get("reports", "download", use: downloadReports)
	}

	/// Sends a form's `@handle` text to the API as a user link when it names a real account. The text is kept either way.
	private func userID(forHandle handle: String?, on req: Request) -> UUID? {
		guard let handle = handle?.trimmingCharacters(in: .whitespaces), !handle.isEmpty else {
			return nil
		}
		return req.userCache.getUser(username: handle.hasPrefix("@") ? String(handle.dropFirst()) : handle)?.userID
	}

	// MARK: - Pages

	/// `GET /communitysupport`
	///
	/// The landing page: links to everything, with unread/open counts.
	func root(_ req: Request) async throws -> View {
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var canFileReports: Bool
			var canDownload: Bool
			init(_ req: Request, canFileReports: Bool, canDownload: Bool) {
				trunk = .init(req, title: "Community Support", tab: .communitySupport)
				self.canFileReports = canFileReports
				self.canDownload = canDownload
			}
		}
		let user = try req.auth.require(UserCacheData.self)
		let ctx = PageContext(
			req,
			canFileReports: user.userRoles.contains(.communitysupport),
			canDownload: user.accessLevel.hasAccess(.tho)
		)
		return try await req.view.render("CommunitySupport/root", ctx)
	}

	/// `GET /communitysupport/newreport`
	///
	/// The form for filing a report.
	func reportForm(_ req: Request) async throws -> View {
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var formAction = "/communitysupport/report"
			var successURL = "/communitysupport/reports"
			init(_ req: Request) {
				trunk = .init(req, title: "New Community Support Report", tab: .communitySupport)
			}
		}
		return try await req.view.render("CommunitySupport/reportForm", PageContext(req))
	}

	/// `POST /communitysupport/report`
	///
	/// Files the report from the form.
	func postReport(_ req: Request) async throws -> HTTPStatus {
		let form = try req.content.decode(ReportFormContent.self)
		let data = CommunitySupportReportCreateData(
			memberName: form.memberName,
			reporterName: form.reporterName,
			reporterUserID: userID(forHandle: form.reporterHandle, on: req),
			reporterHandleText: form.reporterHandle,
			reporterCabin: form.reporterCabin,
			subjectUserID: userID(forHandle: form.subjectHandle, on: req),
			subjectName: form.subjectHandle,
			reporterExperienced: form.reporterExperienced ?? false,
			reporterWitnessed: form.reporterWitnessed ?? false,
			intent: form.intent,
			mayContact: form.mayContact ?? false,
			experienceTime: form.experienceTime,
			experienceLocation: form.experienceLocation,
			experienceDescription: form.experienceDescription,
			preferredOutcome: form.preferredOutcome,
			livedExperiences: form.livedExperiences
		)
		try await apiQuery(req, endpoint: "/communitysupport/report", method: .POST, encodeContent: data)
		return .created
	}

	/// `GET /communitysupport/reports`
	///
	/// The report queue. Takes the API's `status`, `start`, and `limit` query parameters.
	func reports(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/communitysupport/reports")
		let reports = try response.content.decode(Paginated<CommunitySupportReportListData>.self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var reports: Paginated<CommunitySupportReportListData>
			var statusFilter: String?
			var statuses: [StatusChoice]
			var paginator: PaginatorContext
			init(_ req: Request, reports: Paginated<CommunitySupportReportListData>) {
				trunk = .init(req, title: "Community Support Reports", tab: .communitySupport)
				self.reports = reports
				let filter = req.query[String.self, at: "status"]
				statusFilter = filter
				statuses = CommunitySupportReportStatus.allCases.map {
					StatusChoice(value: $0.rawValue, label: $0.label, selected: $0.rawValue == filter)
				}
				paginator = .init(reports.paginator) {
					"/communitysupport/reports?start=\($0)&limit=\(reports.paginator.limit)"
				}
			}
		}
		return try await req.view.render("CommunitySupport/reports", PageContext(req, reports: reports))
	}

	/// `GET /communitysupport/report/:report_id`
	///
	/// One report, its timeline, and the status and discussion controls.
	func report(_ req: Request) async throws -> View {
		let id = try reportID(req)
		let response = try await apiQuery(req, endpoint: "/communitysupport/report/\(id)")
		let report = try response.content.decode(CommunitySupportReportData.self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var report: CommunitySupportReportData
			var statuses: [StatusChoice]
			init(_ req: Request, report: CommunitySupportReportData) {
				trunk = .init(req, title: "Community Support Report", tab: .communitySupport)
				self.report = report
				statuses = CommunitySupportReportStatus.allCases.map {
					StatusChoice(value: $0.rawValue, label: $0.label, selected: $0 == report.status)
				}
			}
		}
		return try await req.view.render("CommunitySupport/report", PageContext(req, report: report))
	}

	/// `POST /communitysupport/report/:report_id/status`
	func postStatus(_ req: Request) async throws -> HTTPStatus {
		let id = try reportID(req)
		let form = try req.content.decode(StatusFormContent.self)
		try await apiQuery(
			req,
			endpoint: "/communitysupport/report/\(id)/status",
			method: .POST,
			encodeContent: CommunitySupportStatusChangeData(status: form.status, note: form.note)
		)
		return .ok
	}

	/// `POST /communitysupport/report/:report_id/discussion`
	///
	/// Starts the report's discussion thread, if it doesn't have one. The page reloads and shows a link to it.
	func postDiscussion(_ req: Request) async throws -> HTTPStatus {
		let id = try reportID(req)
		try await apiQuery(req, endpoint: "/communitysupport/report/\(id)/discussion", method: .POST)
		return .ok
	}

	/// `GET /communitysupport/log`
	///
	/// The team-wide action log.
	func actionLog(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/communitysupport/actionlog")
		let log = try response.content.decode(Paginated<CommunitySupportActionData>.self)
		struct PageContext: Encodable {
			var trunk: TrunkContext
			var log: Paginated<CommunitySupportActionData>
			var paginator: PaginatorContext
			init(_ req: Request, log: Paginated<CommunitySupportActionData>) {
				trunk = .init(req, title: "Community Support Log", tab: .communitySupport)
				self.log = log
				paginator = .init(log.paginator) { "/communitysupport/log?start=\($0)&limit=\(log.paginator.limit)" }
			}
		}
		return try await req.view.render("CommunitySupport/actionLog", PageContext(req, log: log))
	}

	/// `GET /communitysupport/reports/download`
	///
	/// A CSV of every report. THO and above only.
	func downloadReports(_ req: Request) async throws -> Response {
		// The report fields are free text typed by volunteers, and THO will open this in a spreadsheet. A cell that starts with
		// `=`, `+`, `-`, `@`, tab, or carriage return can be run as a formula, so those get a leading apostrophe (which spreadsheets
		// treat as "this is text" and don't display).
		func neutralized(_ field: String) -> String {
			if let first = field.unicodeScalars.first, ["=", "+", "-", "@", "\t", "\r"].contains(Character(first)) {
				return "'" + field
			}
			return field
		}
		func buildCSVRecord(fields: [String]) -> String {
			return fields.map { "\"\(neutralized($0).replacingOccurrences(of: "\"", with: "\"\""))\"" }
				.joined(separator: ",").appending("\n")
		}
		let response = try await apiQuery(req, endpoint: "/communitysupport/export")
		let reports = try response.content.decode([CommunitySupportReportData].self)
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "MMM d, h:mm a z"
		let header =
			"\u{FEFF}"
			+ buildCSVRecord(fields: [
				"Report ID", "Filed", "Status", "Filed By (Username)", "Member Name", "Reporter Name",
				"Reporter Account", "Reporter Handle",
				"Cabin", "Subject Account", "Subject Name", "Experienced", "Witnessed", "Intent", "May Contact", "When",
				"Where",
				"Description", "Preferred Outcome", "Lived Experiences", "Discussion Thread",
			])
		let csv = reports.reduce(into: header) { str, report in
			str.append(
				buildCSVRecord(fields: [
					report.id.uuidString,
					dateFormatter.string(from: report.createdAt),
					report.statusLabel,
					report.author.username,
					report.memberName,
					report.reporterName,
					report.reporter?.username ?? "",
					report.reporterHandleText,
					report.reporterCabin,
					report.subject?.username ?? "",
					report.subjectName,
					report.reporterExperienced ? "yes" : "no",
					report.reporterWitnessed ? "yes" : "no",
					report.intent.label,
					report.mayContact ? "yes" : "no",
					report.experienceTime,
					report.experienceLocation,
					report.experienceDescription,
					report.preferredOutcome,
					report.livedExperiences,
					report.forumID.map { "/forum/\($0.uuidString)" } ?? "",
				])
			)
		}
		guard let data = csv.data(using: .utf8) else {
			throw Abort(.internalServerError, reason: "Could not convert CSV String into Data.")
		}
		var headers: HTTPHeaders = [:]
		headers.contentType = HTTPMediaType(type: "text", subType: "csv", parameters: ["charset": "UTF-8"])
		headers.contentDisposition = .init(.attachment, filename: "community_support_reports.csv")
		return Response(status: .ok, headers: headers, body: Response.Body(data: data))
	}

	// MARK: - Utilities

	/// The `:report_id` path parameter.
	private func reportID(_ req: Request) throws -> UUID {
		guard let string = req.parameters.get(reportIDParam.paramString), let id = UUID(uuidString: string) else {
			throw Abort(.badRequest, reason: "Missing report ID parameter.")
		}
		return id
	}

	/// One option of a status `<select>`.
	struct StatusChoice: Encodable {
		var value: String
		var label: String
		var selected: Bool
	}
}

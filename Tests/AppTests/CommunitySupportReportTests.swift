import XCTVapor

@testable import swiftarr

// Tests for the Community Support report API: who can file and read reports, validation, the status/note log, and the
// discussion thread that a report can start in the private forum.
class CommunitySupportReportTests: XCTestCase, SwiftarrBaseTest {

	private struct Fixture {
		let memberToken: String
		let memberID: UUID
		let ttToken: String
		let thoToken: String
		let moderatorToken: String
		let verifiedToken: String
	}

	private func makeUser(_ app: Application, username: String, accessLevel: UserAccessLevel, role: UserRoleType? = nil)
		async throws -> (token: String, id: UUID)
	{
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: accessLevel
		)
		try await user.save(on: app.db)
		if let role = role {
			try await UserRole(user: user.requireID(), role: role).save(on: app.db)
		}
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return (token.token, try user.requireID())
	}

	private func makeFixture(_ app: Application) async throws -> Fixture {
		let suffix = UUID().uuidString.prefix(8).lowercased()
		let member = try await makeUser(app, username: "csm-\(suffix)", accessLevel: .verified, role: .communitysupport)
		let tt = try await makeUser(app, username: "cstt-\(suffix)", accessLevel: .twitarrteam)
		let tho = try await makeUser(app, username: "cstho-\(suffix)", accessLevel: .tho)
		let mod = try await makeUser(app, username: "csmod-\(suffix)", accessLevel: .moderator)
		let verified = try await makeUser(app, username: "csv-\(suffix)", accessLevel: .verified)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		return Fixture(
			memberToken: member.token,
			memberID: member.id,
			ttToken: tt.token,
			thoToken: tho.token,
			moderatorToken: mod.token,
			verifiedToken: verified.token
		)
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	private func makeCreateData(
		intent: CommunitySupportReportIntent = .followUp,
		description: String = "Something happened near the pool."
	) -> CommunitySupportReportCreateData {
		CommunitySupportReportCreateData(
			memberName: "Pat",
			reporterName: "Sam",
			reporterUserID: nil,
			reporterHandleText: "@sam",
			reporterCabin: "8123",
			subjectUserID: nil,
			subjectName: nil,
			reporterExperienced: true,
			reporterWitnessed: false,
			intent: intent,
			mayContact: true,
			experienceTime: "Tuesday evening",
			experienceLocation: "Lido deck",
			experienceDescription: description,
			preferredOutcome: nil,
			livedExperiences: nil
		)
	}

	/// Files a report as the fixture's team member and returns it.
	private func fileReport(
		_ app: Application,
		_ f: Fixture,
		data: CommunitySupportReportCreateData? = nil
	) async throws -> CommunitySupportReportData {
		var result: CommunitySupportReportData?
		try await app.test(
			.POST,
			"/api/v3/communitysupport/report",
			headers: bearer(f.memberToken),
			beforeRequest: { req throws in try req.content.encode(data ?? makeCreateData()) },
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .created)
				result = try res.content.decode(CommunitySupportReportData.self)
			}
		)
		return try XCTUnwrap(result)
	}

	// MARK: - Pure logic

	func testStatusOpenness() {
		XCTAssertTrue(CommunitySupportReportStatus.new.isOpen)
		XCTAssertTrue(CommunitySupportReportStatus.inProgress.isOpen)
		XCTAssertFalse(CommunitySupportReportStatus.resolved.isOpen)
		XCTAssertFalse(CommunitySupportReportStatus.infoOnly.isOpen)
	}

	func testValidationRequiresTheRequiredFields() throws {
		let decoder = ValidatingJSONDecoder()
		func errors(_ json: String) throws -> [String] {
			try decoder.validate(CommunitySupportReportCreateData.self, from: json.data(using: .utf8)!)?.validationFailures.map { $0.errorString } ?? []
		}
		let base = """
			"reporterExperienced":true,"reporterWitnessed":false,"intent":"followUp","mayContact":true
			"""
		XCTAssertEqual(
			try errors(
				#"{"memberName":"Pat","experienceTime":"now","experienceLocation":"here","experienceDescription":"it happened",\#(base)}"#
			),
			[]
		)
		let blank = try errors(
			#"{"memberName":" ","experienceTime":"","experienceLocation":"","experienceDescription":"",\#(base)}"#
		)
		XCTAssertEqual(blank.count, 4, "\(blank)")
		let tooLong = String(repeating: "a", count: 10_001)
		let long = try errors(
			#"{"memberName":"Pat","experienceTime":"now","experienceLocation":"here","experienceDescription":"\#(tooLong)",\#(base)}"#
		)
		XCTAssertEqual(long, ["description has a 10000 character limit"])
	}

	func testUnknownIntentFailsToDecode() {
		let json = #"""
			{"memberName":"Pat","experienceTime":"now","experienceLocation":"here","experienceDescription":"x",
			"reporterExperienced":true,"reporterWitnessed":false,"intent":"whatever","mayContact":true}
			"""#
		XCTAssertThrowsError(try ValidatingJSONDecoder().validate(CommunitySupportReportCreateData.self, from: json.data(using: .utf8)!))
	}

	func testInfoOnlyIntentStartsAsInfoOnlyStatus() {
		let report = CommunitySupportReport(author: UUID(), data: makeCreateData(intent: .infoOnly))
		XCTAssertEqual(report.status, .infoOnly)
		let followUp = CommunitySupportReport(author: UUID(), data: makeCreateData(intent: .followUp))
		XCTAssertEqual(followUp.status, .new)
	}

	func testDiscussionPostTextFitsTheForumLimitAndKeepsEveryField() {
		let short = CommunitySupportReport(author: UUID(), data: makeCreateData())
		short.id = UUID()
		let shortText = short.discussionPostText()
		XCTAssertTrue(shortText.contains("Something happened near the pool."))
		XCTAssertTrue(shortText.contains("/communitysupport/report/\(short.id!.uuidString)"))
		XCTAssertFalse(shortText.contains("cut short"))

		var data = makeCreateData(description: String(repeating: "d", count: 9_000))
		data.preferredOutcome = String(repeating: "p", count: 4_000)
		data.livedExperiences = "short lived note"
		let long = CommunitySupportReport(author: UUID(), data: data)
		long.id = UUID()
		let longText = long.discussionPostText()
		XCTAssertLessThan(longText.count, 2048, "must fit PostContentData's 2048 character limit")
		XCTAssertTrue(longText.contains("cut short"))
		XCTAssertTrue(longText.contains("short lived note"), "short fields shouldn't be cut")
		XCTAssertTrue(longText.contains("Lido deck"))
		XCTAssertTrue(longText.contains("Preferred outcome: p"), "no field should be dropped entirely")
	}

	func testDiscussionTitleIsAtMost100Characters() {
		let report = CommunitySupportReport(author: UUID(), data: makeCreateData())
		report.experienceLocation = String(repeating: "L", count: 200)
		XCTAssertEqual(report.discussionTitle().count, 100)
	}

	// MARK: - Access control

	func testOnlyRoleHoldersCanFileReports() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			// The `minAccess` default is `.banned`, so a role-only route could silently admit every logged-in user.
			for token in [f.verifiedToken, f.moderatorToken, f.ttToken, f.thoToken] {
				try await app.test(
					.POST,
					"/api/v3/communitysupport/report",
					headers: bearer(token),
					beforeRequest: { req throws in try req.content.encode(makeCreateData()) },
					afterResponse: { res async throws in XCTAssertEqual(res.status, .forbidden) }
				)
			}
			_ = try await fileReport(app, f)
		}
	}

	func testReadAccessIsRoleHoldersAndTwitarrTeamButNotModerators() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f)
			let paths = ["/api/v3/communitysupport/reports", "/api/v3/communitysupport/report/\(report.id)", "/api/v3/communitysupport/actionlog"]
			for path in paths {
				for (token, expected) in [
					(f.memberToken, HTTPResponseStatus.ok), (f.ttToken, .ok), (f.thoToken, .ok),
					(f.moderatorToken, .forbidden), (f.verifiedToken, .forbidden),
				] {
					try await app.test(
						.GET,
						path,
						headers: bearer(token),
						afterResponse: { res async throws in XCTAssertEqual(res.status, expected, "GET \(path)") }
					)
				}
			}
			// Writes by people who can't read.
			for token in [f.moderatorToken, f.verifiedToken] {
				try await app.test(
					.POST,
					"/api/v3/communitysupport/report/\(report.id)/note",
					headers: bearer(token),
					beforeRequest: { req throws in try req.content.encode(CommunitySupportNoteData(note: "hi")) },
					afterResponse: { res async throws in XCTAssertEqual(res.status, .forbidden) }
				)
				try await app.test(
					.POST,
					"/api/v3/communitysupport/report/\(report.id)/discussion",
					headers: bearer(token),
					afterResponse: { res async throws in XCTAssertEqual(res.status, .forbidden) }
				)
			}
		}
	}

	// MARK: - Lifecycle

	func testFilingCreatesReportAndLogEntry() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f)
			XCTAssertEqual(report.status, .new)
			XCTAssertEqual(report.actions.map { $0.actionType }, [.reportCreated])
			XCTAssertEqual(report.author.userID, f.memberID)
			XCTAssertNil(report.forumID)
		}
	}

	func testInfoOnlyReportStartsInfoOnly() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f, data: makeCreateData(intent: .infoOnly))
			XCTAssertEqual(report.status, .infoOnly)
		}
	}

	func testStatusChangeAndNoteAppearInTimelineAndLog() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f)
			// A different reader (TwitarrTeam) updates it.
			try await app.test(
				.POST,
				"/api/v3/communitysupport/report/\(report.id)/status",
				headers: bearer(f.ttToken),
				beforeRequest: { req throws in
					try req.content.encode(CommunitySupportStatusChangeData(status: .inProgress, note: "Calling them back"))
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let updated = try res.content.decode(CommunitySupportReportData.self)
					XCTAssertEqual(updated.status, .inProgress)
				}
			)
			try await app.test(
				.POST,
				"/api/v3/communitysupport/report/\(report.id)/note",
				headers: bearer(f.memberToken),
				beforeRequest: { req throws in try req.content.encode(CommunitySupportNoteData(note: "Reached them.")) },
				afterResponse: { res async throws in XCTAssertEqual(res.status, .ok) }
			)
			try await app.test(
				.GET,
				"/api/v3/communitysupport/report/\(report.id)",
				headers: bearer(f.memberToken),
				afterResponse: { res async throws in
					let detail = try res.content.decode(CommunitySupportReportData.self)
					XCTAssertEqual(detail.actions.map { $0.actionType }, [.reportCreated, .statusChanged, .noteAdded])
					XCTAssertEqual(detail.actions[1].oldStatus, .new)
					XCTAssertEqual(detail.actions[1].newStatus, .inProgress)
					XCTAssertEqual(detail.actions[1].note, "Calling them back")
					XCTAssertEqual(detail.actions[2].note, "Reached them.")
					XCTAssertEqual(detail.actions[2].actionLabel, "Note added")
				}
			)
			try await app.test(
				.GET,
				"/api/v3/communitysupport/reports?status=inProgress",
				headers: bearer(f.memberToken),
				afterResponse: { res async throws in
					let list = try res.content.decode(Paginated<CommunitySupportReportListData>.self)
					XCTAssertTrue(list.items.contains { $0.id == report.id })
					XCTAssertTrue(list.items.allSatisfy { $0.status == .inProgress })
				}
			)
		}
	}

	func testUnknownOrUnchangedStatusIsRejected() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f)
			try await app.test(
				.POST,
				"/api/v3/communitysupport/report/\(report.id)/status",
				headers: bearer(f.memberToken),
				beforeRequest: { req throws in
					req.headers.contentType = .json
					req.body = ByteBuffer(string: #"{"status":"banana"}"#)
				},
				afterResponse: { res async throws in XCTAssertEqual(res.status, .badRequest) }
			)
			try await app.test(
				.POST,
				"/api/v3/communitysupport/report/\(report.id)/status",
				headers: bearer(f.memberToken),
				beforeRequest: { req throws in try req.content.encode(CommunitySupportStatusChangeData(status: .new, note: nil)) },
				afterResponse: { res async throws in XCTAssertEqual(res.status, .badRequest) }
			)
			try await app.test(
				.GET,
				"/api/v3/communitysupport/reports?status=banana",
				headers: bearer(f.memberToken),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .badRequest) }
			)
		}
	}

	// MARK: - Discussion thread

	func testDiscussionCreatesThreadInPrivateCategoryOnceAndIsReused() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f)
			let first = try await startDiscussion(app, token: f.memberToken, reportID: report.id)
			XCTAssertTrue(first.created)
			// A different reader gets the same thread.
			let second = try await startDiscussion(app, token: f.ttToken, reportID: report.id)
			XCTAssertFalse(second.created)
			XCTAssertEqual(second.forumID, first.forumID)

			let forum = try await Forum.find(first.forumID, on: app.db)
			let category = try await forum?.$category.get(on: app.db)
			XCTAssertEqual(category?.requiredRole, .communitysupport)
			let post = try await forum?.$posts.query(on: app.db).first()
			XCTAssertTrue(post?.text.contains("Something happened near the pool.") ?? false, "first post is a copy of the report")
			XCTAssertTrue(post?.text.contains("/communitysupport/report/\(report.id)") ?? false)

			try await app.test(
				.GET,
				"/api/v3/communitysupport/report/\(report.id)",
				headers: bearer(f.memberToken),
				afterResponse: { res async throws in
					let detail = try res.content.decode(CommunitySupportReportData.self)
					XCTAssertEqual(detail.forumID, first.forumID)
					XCTAssertEqual(detail.actions.filter { $0.actionType == .discussionStarted }.count, 1)
				}
			)
			// Role holders and TwitarrTeam can open the thread; a plain moderator can't.
			for (token, expected) in [(f.memberToken, HTTPResponseStatus.ok), (f.ttToken, .ok), (f.moderatorToken, .notFound)] {
				try await app.test(
					.GET,
					"/api/v3/forum/\(first.forumID)",
					headers: bearer(token),
					afterResponse: { res async throws in XCTAssertEqual(res.status, expected) }
				)
			}
		}
	}

	func testConcurrentDiscussionRequestsCreateOneThread() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f)
			async let a = startDiscussion(app, token: f.memberToken, reportID: report.id)
			async let b = startDiscussion(app, token: f.ttToken, reportID: report.id)
			let (first, second) = try await (a, b)
			XCTAssertEqual(first.forumID, second.forumID)
			XCTAssertEqual([first.created, second.created].filter { $0 }.count, 1, "exactly one request should create the thread")
		}
	}

	func testDeletingTheThreadLetsAnotherBeStarted() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = try await fileReport(app, f)
			let first = try await startDiscussion(app, token: f.memberToken, reportID: report.id)
			// Soft-delete leaves the ID on the report, so reads must check that the thread is still there.
			try await Forum.find(first.forumID, on: app.db)?.delete(on: app.db)
			try await app.test(
				.GET,
				"/api/v3/communitysupport/report/\(report.id)",
				headers: bearer(f.memberToken),
				afterResponse: { res async throws in
					XCTAssertNil(try res.content.decode(CommunitySupportReportData.self).forumID)
				}
			)
			let second = try await startDiscussion(app, token: f.memberToken, reportID: report.id)
			XCTAssertTrue(second.created)
			XCTAssertNotEqual(second.forumID, first.forumID)
		}
	}

	// MARK: - Shared mailbox account

	func testSharedMailboxAccountCannotBeBlocked() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let phantom = try XCTUnwrap(
				Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
					.userCache.getUser(username: PrivilegedUser.CommunitySupport.rawValue)
			)
			XCTAssertTrue(PrivilegedUser.isSharedMailboxAccount("communitysupport"))
			XCTAssertTrue(PrivilegedUser.isSharedMailboxAccount("Moderator"))
			XCTAssertFalse(PrivilegedUser.isSharedMailboxAccount("admin"))
			try await app.test(
				.POST,
				"/api/v3/users/\(phantom.userID)/block",
				headers: bearer(f.verifiedToken),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .badRequest) }
			)
		}
	}
}

/// Asks for a report's discussion thread. A free function (rather than a test-case method) so tests can call it concurrently with `async let`.
private func startDiscussion(_ app: Application, token: String, reportID: UUID) async throws -> CommunitySupportDiscussionData {
	var headers = HTTPHeaders()
	headers.bearerAuthorization = BearerAuthorization(token: token)
	var result: CommunitySupportDiscussionData?
	try await app.test(
		.POST,
		"/api/v3/communitysupport/report/\(reportID)/discussion",
		headers: headers,
		afterResponse: { res async throws in
			XCTAssertEqual(res.status, .ok)
			result = try res.content.decode(CommunitySupportDiscussionData.self)
		}
	)
	return try XCTUnwrap(result)
}

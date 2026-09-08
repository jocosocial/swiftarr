import Fluent
import XCTVapor

@testable import swiftarr

// Shutternaut Manager photography-coverage report (issue #510).
class EventPhotographerReportTests: XCTestCase, SwiftarrBaseTest {

	private func makeUser(_ app: Application, username: String, accessLevel: UserAccessLevel) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: accessLevel
		)
		try await user.save(on: app.db)
		return user
	}

	private func makeToken(_ app: Application, for user: User) async throws -> String {
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return token.token
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	private func bootCache(_ app: Application) async throws {
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
	}

	private func makeEvent(
		_ app: Application,
		title: String,
		startTime: Date,
		needsPhotographer: Bool = false,
		uid: String
	) async throws -> Event {
		let event = Event(
			startTime: startTime,
			endTime: startTime.addingTimeInterval(3600),
			title: title,
			description: "fixture",
			location: "Deck 5",
			eventType: .general,
			uid: uid
		)
		event.needsPhotographer = needsPhotographer
		try await event.save(on: app.db)
		return event
	}

	private func assignPhotographer(_ app: Application, user: User, event: Event) async throws {
		let favorite = try EventFavorite(user.requireID(), event)
		favorite.favorite = false
		favorite.photographer = true
		try await favorite.save(on: app.db)
	}

	private func hourOnCruiseDay(_ dayIndex: Int, hour: Int = 10) -> Date {
		let portCalendar = Settings.shared.getPortCalendar()
		let start = Settings.shared.cruiseStartDate()
		return portCalendar.date(byAdding: DateComponents(day: dayIndex, hour: hour), to: start) ?? start
	}

	func testManagerCanFetchReport() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let manager = try await makeUser(app, username: "snmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: manager.requireID(), role: .shutternautmanager).create(on: app.db)
			let event = try await makeEvent(
				app,
				title: "Needs Coverage \(suffix)",
				startTime: hourOnCruiseDay(0),
				needsPhotographer: true,
				uid: "report-flagged-\(suffix)"
			)
			let token = try await makeToken(app, for: manager)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<ShutternautScheduleReportData>.self)
					XCTAssertTrue(data.items.contains { $0.eventID == event.id })
					let row = data.items.first { $0.eventID == event.id }
					XCTAssertEqual(row?.title, "Needs Coverage \(suffix)")
					XCTAssertEqual(row?.needsPhotographer, true)
					XCTAssertEqual(row?.photographers.count, 0)
				}
			)
		}
	}

	func testVerifiedUserForbidden() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let verified = try await makeUser(app, username: "verified-\(suffix)", accessLevel: .verified)
			let token = try await makeToken(app, for: verified)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .forbidden)
				}
			)
		}
	}

	func testShutternautWithoutManagerRoleForbidden() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let naut = try await makeUser(app, username: "naut-\(suffix)", accessLevel: .verified)
			try await UserRole(user: naut.requireID(), role: .shutternaut).create(on: app.db)
			let token = try await makeToken(app, for: naut)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .forbidden)
				}
			)
		}
	}

	func testTwitarrTeamCanFetchReport() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let staff = try await makeUser(app, username: "tt-\(suffix)", accessLevel: .twitarrteam)
			_ = try await makeEvent(
				app,
				title: "TT Coverage \(suffix)",
				startTime: hourOnCruiseDay(0),
				needsPhotographer: true,
				uid: "report-tt-\(suffix)"
			)
			let token = try await makeToken(app, for: staff)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
				}
			)
		}
	}

	func testIncludesAssignedAndFlaggedOmitsUnmarked() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let manager = try await makeUser(app, username: "snmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: manager.requireID(), role: .shutternautmanager).create(on: app.db)
			let photographer = try await makeUser(app, username: "sn-\(suffix)", accessLevel: .verified)
			try await UserRole(user: photographer.requireID(), role: .shutternaut).create(on: app.db)
			photographer.displayName = "Camera \(suffix)"
			try await photographer.save(on: app.db)

			let flagged = try await makeEvent(
				app,
				title: "Flagged Only \(suffix)",
				startTime: hourOnCruiseDay(0, hour: 10),
				needsPhotographer: true,
				uid: "report-flagged-\(suffix)"
			)
			let assigned = try await makeEvent(
				app,
				title: "Assigned Only \(suffix)",
				startTime: hourOnCruiseDay(0, hour: 11),
				needsPhotographer: false,
				uid: "report-assigned-\(suffix)"
			)
			try await assignPhotographer(app, user: photographer, event: assigned)
			let unmarked = try await makeEvent(
				app,
				title: "Unmarked \(suffix)",
				startTime: hourOnCruiseDay(0, hour: 12),
				needsPhotographer: false,
				uid: "report-unmarked-\(suffix)"
			)
			let token = try await makeToken(app, for: manager)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<ShutternautScheduleReportData>.self)
					let ids = Set(data.items.compactMap { $0.eventID })
					XCTAssertTrue(ids.contains(try flagged.requireID()))
					XCTAssertTrue(ids.contains(try assigned.requireID()))
					XCTAssertFalse(ids.contains(try unmarked.requireID()))

					let assignedRow = data.items.first { $0.eventID == assigned.id }
					XCTAssertEqual(assignedRow?.needsPhotographer, false)
					XCTAssertEqual(assignedRow?.photographers.count, 1)
					XCTAssertEqual(assignedRow?.photographers.first?.userID, photographer.id)
					XCTAssertEqual(assignedRow?.photographers.first?.displayName, "Camera \(suffix)")

					let flaggedRow = data.items.first { $0.eventID == flagged.id }
					XCTAssertEqual(flaggedRow?.needsPhotographer, true)
					XCTAssertEqual(flaggedRow?.photographers.count, 0)
				}
			)
		}
	}

	func testMultiplePhotographersOnOneEvent() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let manager = try await makeUser(app, username: "snmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: manager.requireID(), role: .shutternautmanager).create(on: app.db)
			let first = try await makeUser(app, username: "sn-a-\(suffix)", accessLevel: .verified)
			let second = try await makeUser(app, username: "sn-b-\(suffix)", accessLevel: .verified)
			let event = try await makeEvent(
				app,
				title: "Two Shooters \(suffix)",
				startTime: hourOnCruiseDay(0),
				needsPhotographer: true,
				uid: "report-two-\(suffix)"
			)
			try await assignPhotographer(app, user: first, event: event)
			try await assignPhotographer(app, user: second, event: event)
			let token = try await makeToken(app, for: manager)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<ShutternautScheduleReportData>.self)
					let row = data.items.first { $0.eventID == event.id }
					XCTAssertEqual(row?.photographers.count, 2)
					let photographerIDs = Set(row?.photographers.map { $0.userID } ?? [])
					XCTAssertEqual(photographerIDs, Set([try first.requireID(), try second.requireID()]))
				}
			)
		}
	}

	func testCruiseDayUsesEventIndexing() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let manager = try await makeUser(app, username: "snmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: manager.requireID(), role: .shutternautmanager).create(on: app.db)
			let embarkEvent = try await makeEvent(
				app,
				title: "Embark Day \(suffix)",
				startTime: hourOnCruiseDay(0),
				needsPhotographer: true,
				uid: "report-day1-\(suffix)"
			)
			let dayTwoEvent = try await makeEvent(
				app,
				title: "Day Two \(suffix)",
				startTime: hourOnCruiseDay(1),
				needsPhotographer: true,
				uid: "report-day2-\(suffix)"
			)
			let token = try await makeToken(app, for: manager)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport?cruiseday=1",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<ShutternautScheduleReportData>.self)
					let ids = Set(data.items.compactMap { $0.eventID })
					XCTAssertTrue(ids.contains(try embarkEvent.requireID()), "cruiseday=1 is embarkation (Event indexing)")
					XCTAssertFalse(ids.contains(try dayTwoEvent.requireID()))
				}
			)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport?cruiseday=2",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<ShutternautScheduleReportData>.self)
					let ids = Set(data.items.compactMap { $0.eventID })
					XCTAssertFalse(ids.contains(try embarkEvent.requireID()))
					XCTAssertTrue(ids.contains(try dayTwoEvent.requireID()))
				}
			)
		}
	}

	func testPaginationStartAndLimit() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let manager = try await makeUser(app, username: "snmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: manager.requireID(), role: .shutternautmanager).create(on: app.db)
			var created = [Event]()
			for hour in 10..<13 {
				let event = try await makeEvent(
					app,
					title: "Page \(hour) \(suffix)",
					startTime: hourOnCruiseDay(0, hour: hour),
					needsPhotographer: true,
					uid: "report-page-\(hour)-\(suffix)"
				)
				created.append(event)
			}
			let token = try await makeToken(app, for: manager)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport?start=0&limit=2",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<ShutternautScheduleReportData>.self)
					XCTAssertEqual(data.paginator.limit, 2)
					XCTAssertEqual(data.paginator.start, 0)
					XCTAssertGreaterThanOrEqual(data.paginator.total, 3)
					XCTAssertEqual(data.items.count, 2)
				}
			)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport?start=2&limit=2",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					let data = try res.content.decode(Paginated<ShutternautScheduleReportData>.self)
					XCTAssertEqual(data.paginator.start, 2)
					XCTAssertGreaterThanOrEqual(data.items.count, 1)
					let firstPageIDs = Set(created.prefix(2).compactMap { $0.id })
					XCTAssertFalse(firstPageIDs.contains(data.items[0].eventID))
				}
			)
		}
	}

	func testCSVHelperUsesUsernameAndEscapesFields() throws {
		let photographer = UserHeader(
			userID: UUID(),
			username: "camera-bob",
			displayName: "Bob \"The Lens\"",
			userImage: nil,
			preferredPronoun: nil
		)
		let event = ShutternautScheduleReportData(
			eventID: UUID(),
			title: "Show, featuring \"quotes\"",
			startTime: Date(timeIntervalSince1970: 0),
			endTime: Date(timeIntervalSince1970: 3600),
			timeZone: "EST",
			location: "Deck 5",
			needsPhotographer: true,
			photographers: [photographer]
		)
		let csvData = ShutternautScheduleReport.buildCSV(from: [event])
		XCTAssertEqual(Array(csvData.prefix(3)), [0xEF, 0xBB, 0xBF])
		let csv = String(data: csvData.dropFirst(3), encoding: .utf8) ?? ""
		XCTAssertTrue(csv.contains("camera-bob"))
		XCTAssertFalse(csv.contains("The Lens"))
		XCTAssertTrue(csv.contains("\"Show, featuring \"\"quotes\"\"\""))
		XCTAssertTrue(csv.contains("true"))
		XCTAssertTrue(csv.contains("Start Time"))
	}

	func testManagerCanDownloadCSVUsesUsername() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let manager = try await makeUser(app, username: "snmgr-\(suffix)", accessLevel: .verified)
			try await UserRole(user: manager.requireID(), role: .shutternautmanager).create(on: app.db)
			let photographer = try await makeUser(app, username: "sn-\(suffix)", accessLevel: .verified)
			try await UserRole(user: photographer.requireID(), role: .shutternaut).create(on: app.db)
			photographer.displayName = "Camera \(suffix)"
			try await photographer.save(on: app.db)
			let event = try await makeEvent(
				app,
				title: "CSV Coverage \(suffix)",
				startTime: hourOnCruiseDay(0),
				needsPhotographer: true,
				uid: "report-csv-\(suffix)"
			)
			try await assignPhotographer(app, user: photographer, event: event)
			let token = try await makeToken(app, for: manager)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport/download",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					XCTAssertEqual(res.headers.contentType?.subType, "csv")
					let csv = String(buffer: res.body)
					XCTAssertTrue(csv.contains("CSV Coverage \(suffix)"))
					XCTAssertTrue(csv.contains("sn-\(suffix)"))
					XCTAssertFalse(csv.contains("Camera \(suffix)"))
					XCTAssertTrue(csv.contains("true"))
				}
			)
		}
	}

	func testVerifiedUserForbiddenOnCSVDownload() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let verified = try await makeUser(app, username: "verified-\(suffix)", accessLevel: .verified)
			let token = try await makeToken(app, for: verified)
			try await bootCache(app)

			try await app.test(
				.GET,
				"/api/v3/events/photographerreport/download",
				headers: bearer(token),
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .forbidden)
				}
			)
		}
	}
}

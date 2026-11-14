import Fluent
import XCTVapor

@testable import swiftarr

// Staging a schedule in sched.com API format via POST /api/v3/admin/schedule/upload.
class SchedScheduleUploadTests: XCTestCase, SwiftarrBaseTest {

	private func makeToken(_ app: Application, username: String, accessLevel: UserAccessLevel) async throws -> String {
		let user = User(username: username, password: try Bcrypt.hash("password1"),
				recoveryKey: try Bcrypt.hash("recovery key"), accessLevel: accessLevel)
		try await user.save(on: app.db)
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
		return token.token
	}

	private func headers(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		headers.contentType = .json
		return headers
	}

	private func exportFixture() throws -> ByteBuffer {
		let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("TestData/SchedExport2026.json")
		return ByteBuffer(data: try Data(contentsOf: url))
	}

	func testUploadThenVerify() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let ttToken = try await makeToken(app, username: "schedtt-\(suffix)", accessLevel: .twitarrteam)
			let verifiedToken = try await makeToken(app, username: "schedv-\(suffix)", accessLevel: .verified)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			try await app.test(.POST, "/api/v3/admin/schedule/upload", headers: headers(verifiedToken),
					body: try exportFixture(), afterResponse: { res async throws in
				XCTAssertEqual(res.status, .forbidden)
			})
			try await app.test(.POST, "/api/v3/admin/schedule/upload", headers: headers(ttToken),
					body: ByteBuffer(string: "ERR: Authorization failed."), afterResponse: { res async throws in
				XCTAssertEqual(res.status, .badRequest)
			})
			try await app.test(.POST, "/api/v3/admin/schedule/upload", headers: headers(ttToken),
					body: try exportFixture(), afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok, res.body.string)
			})

			// The test db is seeded from the same schedule's .ics export, so the only changes are the added age ratings.
			try await app.test(.GET, "/api/v3/admin/schedule/verify", headers: headers(ttToken),
					afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
				let diff = try res.content.decode(EventUpdateDifferenceData.self)
				XCTAssertEqual(diff.createdEvents.count, 0)
				XCTAssertEqual(diff.timeChangeEvents.count, 0)
				XCTAssertEqual(diff.locationChangeEvents.count, 0)
				XCTAssertEqual(diff.minorChangeEvents.count, 233)
				let changes = try XCTUnwrap(diff.minorChanges)
				XCTAssertEqual(changes.count, 233)
				for change in changes {
					XCTAssertEqual(change.changedFields.map(\.fieldName), ["Age Rating"], change.event.uid)
					XCTAssertEqual(change.changedFields.first?.oldValue, "None")
				}
			})

			// An .ics upload replaces the staged Sched upload.
			try await app.test(.POST, "/api/v3/admin/schedule/update", headers: headers(ttToken),
					beforeRequest: { req in try req.content.encode(EventsUpdateData(schedule: "")) },
					afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
			})
			XCTAssertFalse(FileManager.default.fileExists(atPath: try AdminController().uploadScheduleJSONPath().path))
			try await app.test(.GET, "/api/v3/admin/schedule/verify", headers: headers(ttToken),
					afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
				let diff = try res.content.decode(EventUpdateDifferenceData.self)
				XCTAssertEqual(diff.createdEvents.count, 0)
				XCTAssertEqual(diff.minorChangeEvents.count, 0)
				XCTAssertGreaterThanOrEqual(diff.deletedEvents.count, 517)
			})
		}
	}
}

import Fluent
import XCTVapor

@testable import swiftarr

// Bulk performer import (Sched API speaker data and scraped uploads), and merge vs. overwrite apply modes.
final class PerformerBulkImportTests: XCTestCase, SwiftarrBaseTest {

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

	// Just Jonathan Coulton's entry from the speaker fixture. Applying the whole fixture would fetch every new performer's
	// photo from sched.com.
	private func coultonSpeakerData() throws -> ByteBuffer {
		let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("TestData/SchedSpeakers2026.json")
		let speakers = try JSONDecoder().decode([SchedSpeaker].self, from: Data(contentsOf: url))
		return ByteBuffer(data: try JSONEncoder().encode(speakers.filter { $0.name == "Jonathan Coulton" }))
	}

	private func verify(_ app: Application, token: String, overwrite: Bool) async throws -> PerformerUpdateDifferenceData {
		var diff: PerformerUpdateDifferenceData?
		try await app.test(.GET, "/api/v3/admin/performer/bulk/verify\(overwrite ? "?overwrite=true" : "")",
				headers: headers(token), afterResponse: { res async throws in
			XCTAssertEqual(res.status, .ok, res.body.string)
			diff = try res.content.decode(PerformerUpdateDifferenceData.self)
		})
		return try XCTUnwrap(diff)
	}

	func testSchedUpload_MergeKeepsFieldsSchedDoesNotHave() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let ttToken = try await makeToken(app, username: "perfsched-tt-\(suffix)", accessLevel: .twitarrteam)
			let verifiedToken = try await makeToken(app, username: "perfsched-v-\(suffix)", accessLevel: .verified)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let performer = Performer()
			performer.name = "Jonathan Coulton"
			performer.sortOrder = "COULTON"
			performer.pronouns = "he/him"
			performer.bio = "Old bio"
			performer.xURL = "https://x.com/jonathancoulton"
			performer.yearsAttended = [2011, 2012]
			performer.officialPerformer = true
			try await performer.save(on: app.db)
			let performerID = try performer.requireID()

			try await app.test(.POST, "/api/v3/admin/performer/bulk/sched/upload", headers: headers(verifiedToken),
					body: try coultonSpeakerData(), afterResponse: { res async throws in
				XCTAssertEqual(res.status, .forbidden)
			})
			try await app.test(.POST, "/api/v3/admin/performer/bulk/sched/upload", headers: headers(ttToken),
					body: ByteBuffer(string: "ERR: Authorization failed."), afterResponse: { res async throws in
				XCTAssertEqual(res.status, .badRequest)
			})
			try await app.test(.POST, "/api/v3/admin/performer/bulk/sched/upload", headers: headers(ttToken),
					body: try coultonSpeakerData(), afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok, res.body.string)
			})

			// Merge: only fields Sched has show as changes. The test db's schedule is seeded from the same cruise's export.
			let merged = try await verify(app, token: ttToken, overwrite: false)
			let mergedFields = try XCTUnwrap(merged.updatedPerformers.first { $0.header.id == performerID }).changedFields
			XCTAssertEqual(mergedFields.map(\.fieldName), ["Bio"])
			XCTAssertEqual(merged.newPerformers.count, 0)
			XCTAssertEqual(merged.eventLinksToAdd.filter { $0.performerName == "Jonathan Coulton" }.count, 6)
			XCTAssertEqual(merged.unmatchedScrapedEvents.count, 0)

			// Overwrite: fields Sched doesn't have would be blanked.
			let overwritten = try await verify(app, token: ttToken, overwrite: true)
			let overwriteFields = try XCTUnwrap(overwritten.updatedPerformers.first { $0.header.id == performerID }).changedFields
			XCTAssertEqual(Set(overwriteFields.map(\.fieldName)), ["Bio", "Pronouns", "X"])

			try await app.test(.POST, "/api/v3/admin/performer/bulk/apply", headers: headers(ttToken),
					afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok, res.body.string)
			})
			let found = try await Performer.find(performerID, on: app.db)
			let updated = try XCTUnwrap(found)
			XCTAssertEqual(updated.pronouns, "he/him")
			XCTAssertEqual(updated.xURL, "https://x.com/jonathancoulton")
			XCTAssertTrue(updated.bio?.hasPrefix("**Jonathan Coulton** is from the Internet.") == true)
			XCTAssertTrue(updated.yearsAttended.contains(2011))
			let links = try await EventPerformer.query(on: app.db).filter(\.$performer.$id == performerID).count()
			XCTAssertEqual(links, 6)

			try await EventPerformer.query(on: app.db).filter(\.$performer.$id == performerID).delete()
			try await updated.delete(force: true, on: app.db)
		}
	}

	// The jococruise.com scraper uploads PerformerData directly; merge mode applies the same way.
	func testScrapedUpload_MergeAndOverwrite() async throws {
		try await withApp { app in
			let suffix = UUID().uuidString.prefix(8).lowercased()
			let ttToken = try await makeToken(app, username: "perfbulk-tt-\(suffix)", accessLevel: .twitarrteam)
			try await app.asyncBoot()
			try await app.initializeUserCache(app)

			let name = "Bulk Merge \(suffix)"
			let performer = Performer()
			performer.name = name
			performer.sortOrder = name.uppercased()
			performer.bio = "Sched bio"
			performer.organization = "Sched org"
			performer.xURL = "https://x.com/old"
			performer.yearsAttended = [2011]
			performer.officialPerformer = true
			try await performer.save(on: app.db)
			let performerID = try performer.requireID()

			// Like a jococruise.com scrape: has pronouns, X, and years, but no organization, and a blank bio.
			var scraped = PerformerData()
			scraped.header.name = name
			scraped.header.isOfficialPerformer = true
			scraped.pronouns = "they/them"
			scraped.bio = ""
			scraped.xURL = "https://x.com/new"
			scraped.yearsAttended = [2019]
			let upload = ByteBuffer(data: try JSONEncoder().encode([scraped]))

			try await app.test(.POST, "/api/v3/admin/performer/bulk/upload", headers: headers(ttToken), body: upload,
					afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok, res.body.string)
			})
			let merged = try await verify(app, token: ttToken, overwrite: false)
			let mergedFields = try XCTUnwrap(merged.updatedPerformers.first { $0.header.id == performerID }).changedFields
			XCTAssertEqual(Set(mergedFields.map(\.fieldName)), ["Pronouns", "X"])
			let overwritten = try await verify(app, token: ttToken, overwrite: true)
			let overwriteFields = try XCTUnwrap(overwritten.updatedPerformers.first { $0.header.id == performerID }).changedFields
			XCTAssertEqual(Set(overwriteFields.map(\.fieldName)), ["Pronouns", "X", "Bio", "Organization"])

			// Merge apply: the last importer wins for fields it has, and the rest are kept.
			try await app.test(.POST, "/api/v3/admin/performer/bulk/apply?linkEvents=false", headers: headers(ttToken),
					afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok, res.body.string)
			})
			var found = try await Performer.find(performerID, on: app.db)
			var updated = try XCTUnwrap(found)
			XCTAssertEqual(updated.pronouns, "they/them")
			XCTAssertEqual(updated.xURL, "https://x.com/new")
			XCTAssertEqual(updated.bio, "Sched bio")
			XCTAssertEqual(updated.organization, "Sched org")
			XCTAssertTrue(updated.yearsAttended.contains(2011) && updated.yearsAttended.contains(2019))

			// Overwrite apply: fields the upload doesn't have are blanked.
			try await app.test(.POST, "/api/v3/admin/performer/bulk/apply?linkEvents=false&overwrite=true",
					headers: headers(ttToken), afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok, res.body.string)
			})
			found = try await Performer.find(performerID, on: app.db)
			updated = try XCTUnwrap(found)
			XCTAssertEqual(updated.bio, "")
			XCTAssertNil(updated.organization)
			XCTAssertFalse(updated.yearsAttended.contains(2011))

			try await updated.delete(force: true, on: app.db)
		}
	}
}

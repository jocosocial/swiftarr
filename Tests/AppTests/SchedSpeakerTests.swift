import XCTVapor
@testable import swiftarr

// Converting sched.com API speakers into PerformerData for bulk performer import.
class SchedSpeakerTests: XCTestCase {

	private func testData(_ name: String) throws -> ByteBuffer {
		let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("TestData/\(name)")
		return ByteBuffer(data: try Data(contentsOf: url))
	}

	private func speaker(
		name: String = "Test Speaker",
		about: String? = nil,
		url: String? = nil,
		avatar: String? = nil,
		company: String? = nil,
		position: String? = nil,
		sessions: [String]? = nil
	) -> SchedSpeaker {
		SchedSpeaker(username: "test", name: name, about: about, url: url, avatar: avatar, company: company,
				position: position, sessions: sessions)
	}

	func testFixture_DecodesAndLinksToScheduleSessions() throws {
		let speakers = try SchedSpeaker.decodeSpeakers(from: try testData("SchedSpeakers2026.json"))
		let performers = try speakers.map { try $0.makePerformerData() }
		XCTAssertEqual(performers.count, 37)
		XCTAssertTrue(performers.allSatisfy { $0.header.isOfficialPerformer && !$0.header.name.isEmpty })

		let sessionUIDs = Set(try SchedSession.decodeSessions(from: try testData("SchedExport2026.json")).map(\.id))
		let refs = performers.flatMap(\.scrapedEventRefs)
		XCTAssertEqual(refs.count, 149)
		XCTAssertTrue(refs.allSatisfy { $0.uid.map(sessionUIDs.contains) == true && $0.startTime == nil })

		let coulton = try XCTUnwrap(performers.first { $0.header.name == "Jonathan Coulton" })
		XCTAssertEqual(coulton.scrapedEventRefs.count, 6)
		XCTAssertTrue(coulton.bio?.hasPrefix("**Jonathan Coulton** is from the Internet.") == true)
		XCTAssertNil(coulton.website)
		XCTAssertNil(coulton.pronouns)
		XCTAssertNil(coulton.xURL)
	}

	func testMakePerformerData_MapsFields() throws {
		let performer = try speaker(
			about: "<p>Hello <a href=\"https://x.test\">there</a>.</p>",
			url: "www.example.com",
			avatar: "//avatars.sched.co/a.jpg",
			company: "Paul and Storm",
			position: " ",
			sessions: ["abc"]
		).makePerformerData()
		XCTAssertEqual(performer.bio, "Hello [there](https://x.test).")
		XCTAssertEqual(performer.website, "https://www.example.com")
		XCTAssertEqual(performer.header.photo, "https://avatars.sched.co/a.jpg")
		XCTAssertEqual(performer.organization, "Paul and Storm")
		XCTAssertNil(performer.title)
		XCTAssertEqual(performer.scrapedEventRefs.map(\.uid), ["abc"])
	}

	func testMakePerformerData_KeepsWebsiteScheme() throws {
		XCTAssertEqual(try speaker(url: "http://www.paulandstorm.com/").makePerformerData().website, "http://www.paulandstorm.com/")
	}

	func testMakePerformerData_EmptyFieldsAreNil() throws {
		let performer = try speaker(about: "", url: "", avatar: "", company: "").makePerformerData()
		XCTAssertNil(performer.bio)
		XCTAssertNil(performer.website)
		XCTAssertNil(performer.header.photo)
		XCTAssertNil(performer.organization)
		XCTAssertEqual(performer.scrapedEventRefs.count, 0)
	}

	func testDecodeSpeakers_SchedErrorBodyThrows() {
		XCTAssertThrowsError(try SchedSpeaker.decodeSpeakers(from: ByteBuffer(string: "ERR: Authorization failed.")))
	}
}

import XCTVapor

@testable import swiftarr

class SeamailCreateMailboxTests: XCTestCase {

	func testModeratorForuserPrefillsModeratorRadio() {
		let mailbox = SeamailCreateMailbox(foruser: "moderator")
		XCTAssertTrue(mailbox.postAsModerator)
		XCTAssertFalse(mailbox.postAsTwitarrTeam)
		XCTAssertEqual(mailbox.postSuccessURL, "/seamail?foruser=moderator")
		XCTAssertEqual(mailbox.formAction, "/seamail/create?foruser=moderator")
		XCTAssertEqual(mailbox.effectiveUser, "moderator")
	}

	func testTwitarrTeamForuserPrefillsTwitarrTeamRadio() {
		let mailbox = SeamailCreateMailbox(foruser: "twitarrteam")
		XCTAssertFalse(mailbox.postAsModerator)
		XCTAssertTrue(mailbox.postAsTwitarrTeam)
		XCTAssertEqual(mailbox.postSuccessURL, "/seamail?foruser=twitarrteam")
		XCTAssertEqual(mailbox.formAction, "/seamail/create?foruser=twitarrteam")
		XCTAssertEqual(mailbox.effectiveUser, "twitarrteam")
	}

	func testForuserComparisonIsCaseInsensitive() {
		let mailbox = SeamailCreateMailbox(foruser: "TwitarrTeam")
		XCTAssertTrue(mailbox.postAsTwitarrTeam)
		XCTAssertEqual(mailbox.postSuccessURL, "/seamail?foruser=twitarrteam")
	}

	func testAbsentForuserSelectsSelf() {
		let mailbox = SeamailCreateMailbox(foruser: nil)
		XCTAssertFalse(mailbox.postAsModerator)
		XCTAssertFalse(mailbox.postAsTwitarrTeam)
		XCTAssertEqual(mailbox.postSuccessURL, "/seamail")
		XCTAssertEqual(mailbox.formAction, "/seamail/create")
		XCTAssertNil(mailbox.effectiveUser)
	}

	func testUnrecognizedForuserSelectsSelf() {
		let mailbox = SeamailCreateMailbox(foruser: "javascript:alert(1)")
		XCTAssertFalse(mailbox.postAsModerator)
		XCTAssertFalse(mailbox.postAsTwitarrTeam)
		XCTAssertEqual(mailbox.postSuccessURL, "/seamail")
		XCTAssertNil(mailbox.effectiveUser)
	}

	// The flags come from the URL query, the same way the create page reads them.
	func testMailboxComesFromTheQueryParameter() async throws {
		let app = try await Application.make(.testing)

		func mailbox(for url: String) -> SeamailCreateMailbox {
			SeamailCreateMailbox(
				Request(
					application: app,
					method: .GET,
					url: URI(string: url),
					on: app.eventLoopGroup.next()
				)
			)
		}

		let asModerator = mailbox(for: "/seamail/create?foruser=moderator")
		XCTAssertTrue(asModerator.postAsModerator)
		XCTAssertFalse(asModerator.postAsTwitarrTeam)
		XCTAssertEqual(asModerator.postSuccessURL, "/seamail?foruser=moderator")

		let asTwitarrTeam = mailbox(for: "/seamail/create?foruser=twitarrteam")
		XCTAssertTrue(asTwitarrTeam.postAsTwitarrTeam)
		XCTAssertEqual(asTwitarrTeam.postSuccessURL, "/seamail?foruser=twitarrteam")

		XCTAssertFalse(mailbox(for: "/seamail/create").postAsModerator)
		XCTAssertFalse(mailbox(for: "/seamail/create?foruser=").postAsModerator)
		XCTAssertFalse(mailbox(for: "/seamail/create?foruser=moderatorx").postAsModerator)

		try await app.asyncShutdown()
	}

	func testPaginatorPreservesForuser() {
		let options = SiteSeamailController.SeamailQueryOptions(
			search: nil,
			start: nil,
			limit: nil,
			onlynew: nil,
			foruser: "moderator"
		)
		XCTAssertEqual(
			options.buildQuery(baseURL: "/seamail", startOffset: 50),
			"/seamail?foruser=moderator&start=50"
		)
		XCTAssertEqual(
			options.buildQuery(baseURL: "/seamail/search", startOffset: 0),
			"/seamail/search?foruser=moderator"
		)
	}

	func testListHeadingNamesTheMailbox() {
		XCTAssertEqual(
			SiteSeamailController.SeamailQueryOptions(
				search: nil, start: nil, limit: nil, onlynew: nil, foruser: "moderator"
			).describeQuery(),
			"Moderator Seamail"
		)
		XCTAssertEqual(
			SiteSeamailController.SeamailQueryOptions(
				search: "hello", start: nil, limit: nil, onlynew: nil, foruser: "twitarrteam"
			).describeQuery(),
			"TwitarrTeam Seamail containing \"hello\""
		)
		XCTAssertEqual(
			SiteSeamailController.SeamailQueryOptions(
				search: nil, start: nil, limit: nil, onlynew: nil, foruser: nil
			).describeQuery(),
			"Seamail"
		)
	}

	func testMessagePostContextRadiosFollowForuser() {
		let asModerator = MessagePostContext(forType: .tweet, foruser: "moderator")
		XCTAssertTrue(asModerator.postAsModerator)
		XCTAssertFalse(asModerator.postAsTwitarrTeam)

		let asTwitarrTeam = MessagePostContext(forType: .tweet, foruser: "twitarrteam")
		XCTAssertFalse(asTwitarrTeam.postAsModerator)
		XCTAssertTrue(asTwitarrTeam.postAsTwitarrTeam)

		let asSelf = MessagePostContext(forType: .tweet)
		XCTAssertFalse(asSelf.postAsModerator)
		XCTAssertFalse(asSelf.postAsTwitarrTeam)
	}

	func testPostAsRadioMapsToASingleCreator() {
		func form(postAs: String?) -> SiteSeamailController.SeamailCreateFormContent {
			SiteSeamailController.SeamailCreateFormContent(
				subject: "s",
				postText: "p",
				participants: "",
				openchat: nil,
				postAs: postAs,
				foruser: nil
			)
		}

		XCTAssertTrue(form(postAs: "moderator").createdByModerator)
		XCTAssertFalse(form(postAs: "moderator").createdByTwitarrTeam)

		XCTAssertTrue(form(postAs: "twitarrteam").createdByTwitarrTeam)
		XCTAssertFalse(form(postAs: "twitarrteam").createdByModerator)

		XCTAssertFalse(form(postAs: "self").createdByModerator)
		XCTAssertFalse(form(postAs: "self").createdByTwitarrTeam)
		XCTAssertFalse(form(postAs: nil).createdByModerator)
		XCTAssertFalse(form(postAs: nil).createdByTwitarrTeam)
	}
}

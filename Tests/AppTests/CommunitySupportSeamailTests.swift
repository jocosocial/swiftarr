import Fluent
import XCTVapor

@testable import swiftarr

// End-to-end tests of the shared @CommunitySupport mailbox: attendees can write to it, the team shares it with independent unread counts,
// the team can reply as the account, and plain moderators can't read it. Also covers @CommunitySupport forum mentions and the badge counts.
class CommunitySupportSeamailTests: XCTestCase, SwiftarrBaseTest {

	private struct Fixture {
		let memberA: (token: String, id: UUID)
		let memberB: (token: String, id: UUID)
		let tt: (token: String, id: UUID)
		let moderator: (token: String, id: UUID)
		let attendee: (token: String, id: UUID)
		let phantomID: UUID
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
		let a = try await makeUser(app, username: "ma-\(suffix)", accessLevel: .verified, role: .communitysupport)
		let b = try await makeUser(app, username: "mb-\(suffix)", accessLevel: .verified, role: .communitysupport)
		let tt = try await makeUser(app, username: "mtt-\(suffix)", accessLevel: .twitarrteam)
		let mod = try await makeUser(app, username: "mmod-\(suffix)", accessLevel: .moderator)
		let attendee = try await makeUser(app, username: "matt-\(suffix)", accessLevel: .verified)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		let req = Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
		let phantom = try XCTUnwrap(req.userCache.getUser(username: PrivilegedUser.CommunitySupport.rawValue))
		return Fixture(memberA: a, memberB: b, tt: tt, moderator: mod, attendee: attendee, phantomID: phantom.userID)
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	private func seamailData(
		to users: [UUID],
		createdByCommunitySupport: Bool? = nil,
		postAsCommunitySupport: Bool = false
	)
		-> FezContentData
	{
		FezContentData(
			fezType: .closed,
			visibility: nil,
			title: "Need to talk",
			info: "",
			startTime: nil,
			endTime: nil,
			location: nil,
			minCapacity: 0,
			maxCapacity: 0,
			initialUsers: users,
			createdByModerator: nil,
			createdByTwitarrTeam: nil,
			createdByCommunitySupport: createdByCommunitySupport,
			firstPost: PostContentData(text: "Hello team", images: [], postAsCommunitySupport: postAsCommunitySupport)
		)
	}

	/// An attendee writes to @CommunitySupport; returns the new chat's ID.
	private func attendeeWritesToTeam(_ app: Application, _ f: Fixture) async throws -> UUID {
		var fezID: UUID?
		try await app.test(
			.POST,
			"/api/v3/fez/create",
			headers: bearer(f.attendee.token),
			beforeRequest: { req throws in try req.content.encode(seamailData(to: [f.phantomID])) },
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .created)
				fezID = try res.content.decode(FezData.self).fezID
			}
		)
		return try XCTUnwrap(fezID)
	}

	private func unreadState(_ app: Application, userID: UUID) async throws -> ChatUnreadState {
		let req = Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
		return try await req.redis.getChatUnreadState(userID: userID, inbox: .communitySupportSeamail)
	}

	func testAttendeeCanWriteToTheTeamAndEachMemberGetsAnUnreadCount() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let fezID = try await attendeeWritesToTeam(app, f)
			for member in [f.memberA, f.memberB, f.tt] {
				let state = try await unreadState(app, userID: member.id)
				XCTAssertTrue(
					state.addedToChatIDs.contains(fezID) || state.unreadChatCount > 0,
					"each team member has their own unread count"
				)
			}
			let modState = try await unreadState(app, userID: f.moderator.id)
			XCTAssertTrue(
				modState.addedToChatIDs.isEmpty && modState.unreadChatCount == 0,
				"plain moderators aren't on the roster"
			)
		}
	}

	func testTeamCanListTheSharedMailboxButModeratorsCannot() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let fezID = try await attendeeWritesToTeam(app, f)
			for member in [f.memberA, f.tt] {
				try await app.test(
					.GET,
					"/api/v3/fez/joined?foruser=communitysupport&type=closed",
					headers: bearer(member.token),
					afterResponse: { res async throws in
						XCTAssertEqual(res.status, .ok)
						XCTAssertTrue(try res.content.decode(FezListData.self).fezzes.contains { $0.fezID == fezID })
					}
				)
			}
			for other in [f.moderator, f.attendee] {
				try await app.test(
					.GET,
					"/api/v3/fez/joined?foruser=communitysupport&type=closed",
					headers: bearer(other.token),
					afterResponse: { res async throws in XCTAssertEqual(res.status, .forbidden) }
				)
			}
		}
	}

	func testModeratorsCannotOpenTheChatThroughModerationTools() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			// A team member starts a chat with the attendee, as Community Support, with the first message from the shared account.
			var createdID: UUID?
			try await app.test(
				.POST,
				"/api/v3/fez/create",
				headers: bearer(f.memberA.token),
				beforeRequest: { req throws in
					try req.content.encode(
						seamailData(to: [f.attendee.id], createdByCommunitySupport: true, postAsCommunitySupport: true)
					)
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .created)
					createdID = try res.content.decode(FezData.self).fezID
				}
			)
			let fezID = try XCTUnwrap(createdID)
			try await app.test(
				.GET,
				"/api/v3/mod/fez/\(fezID)",
				headers: bearer(f.moderator.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .notFound) }
			)
			try await app.test(
				.GET,
				"/api/v3/mod/fez/\(fezID)",
				headers: bearer(f.tt.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .ok) }
			)
			// Seamail chats and messages can't be reported, so there's no report that would justify showing a moderator the chat.
			let post = try await FezPost.query(on: app.db).filter(\.$fez.$id == fezID).first()
			let postID = try XCTUnwrap(post?.id)
			for (token, expected) in [
				(f.moderator.token, HTTPResponseStatus.notFound), (f.tt.token, .ok), (f.memberA.token, .forbidden),
			] {
				try await app.test(
					.GET,
					"/api/v3/mod/fezpost/\(postID)",
					headers: bearer(token),
					afterResponse: { res async throws in XCTAssertEqual(res.status, expected) }
				)
			}
		}
	}

	func testTeamMembersCanCreateAndPostAsCommunitySupport() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			for (token, expected) in [
				(f.memberA.token, HTTPResponseStatus.created), (f.tt.token, .created),
				(f.moderator.token, .badRequest), (f.attendee.token, .badRequest),
			] {
				try await app.test(
					.POST,
					"/api/v3/fez/create",
					headers: bearer(token),
					beforeRequest: { req throws in
						try req.content.encode(seamailData(to: [f.attendee.id], createdByCommunitySupport: true))
					},
					afterResponse: { res async throws in XCTAssertEqual(res.status, expected) }
				)
			}
		}
	}

	func testPostingAsCommunitySupportAndAnotherAccountIsRejected() throws {
		let decoder = ValidatingJSONDecoder()
		func errors(_ json: String) throws -> [String] {
			try decoder.validate(PostContentData.self, from: json.data(using: .utf8)!)?.validationFailures
				.map { $0.errorString } ?? []
		}
		XCTAssertEqual(try errors(#"{"text":"hi","images":[],"postAsCommunitySupport":true}"#), [])
		for other in ["postAsModerator", "postAsTwitarrTeam"] {
			let errs = try errors(#"{"text":"hi","images":[],"\#(other)":true,"postAsCommunitySupport":true}"#)
			XCTAssertTrue(
				errs.contains("cannot post as @CommunitySupport and another account at the same time"),
				"\(other): \(errs)"
			)
		}
	}

	func testCommunitySupportMentionNotifiesTeamButNotModerators() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let category = try await Category.query(on: app.db).all().first { $0.requiredRole == .communitysupport }
			let forum = try Forum(title: "Team talk", category: try XCTUnwrap(category), creatorID: f.memberA.id)
			try await forum.save(on: app.db)
			try await ForumPost(forum: forum, authorID: f.memberA.id, text: "first", images: []).save(on: app.db)
			try await app.test(
				.POST,
				"/api/v3/forum/\(try forum.requireID())/create",
				headers: bearer(f.memberA.token),
				beforeRequest: { req throws in
					try req.content.encode(PostContentData(text: "ping @CommunitySupport please look", images: []))
				},
				afterResponse: { res async throws in XCTAssertEqual(res.status, .created) }
			)
			for (token, expected) in [(f.memberB.token, 1), (f.tt.token, 1), (f.memberA.token, 0)] {
				try await app.test(
					.GET,
					"/api/v3/notification/global",
					headers: bearer(token),
					afterResponse: { res async throws in
						let data = try res.content.decode(UserNotificationData.self)
						XCTAssertEqual(data.communitySupportData?.newForumMentionCount, expected)
					}
				)
			}
			try await app.test(
				.GET,
				"/api/v3/notification/global",
				headers: bearer(f.moderator.token),
				afterResponse: { res async throws in
					let data = try res.content.decode(UserNotificationData.self)
					XCTAssertNil(data.communitySupportData, "moderators get no Community Support counts")
					XCTAssertEqual(data.moderatorData?.newModeratorForumMentionCount, 0)
				}
			)
			// Searching for the mention clears it.
			try await app.test(
				.GET,
				"/api/v3/forum/post/search?mentionname=CommunitySupport",
				headers: bearer(f.memberB.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .ok) }
			)
			try await app.test(
				.GET,
				"/api/v3/notification/global",
				headers: bearer(f.memberB.token),
				afterResponse: { res async throws in
					XCTAssertEqual(
						try res.content.decode(UserNotificationData.self).communitySupportData?.newForumMentionCount,
						0
					)
				}
			)
		}
	}

	func testOpenReportCountShowsForTeamOnly() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let data = CommunitySupportReportCreateData(
				memberName: "Pat",
				reporterName: nil,
				reporterUserID: nil,
				reporterHandleText: nil,
				reporterCabin: nil,
				subjectUserID: nil,
				subjectName: nil,
				reporterExperienced: true,
				reporterWitnessed: false,
				intent: .followUp,
				mayContact: true,
				experienceTime: "now",
				experienceLocation: "here",
				experienceDescription: "something",
				preferredOutcome: nil,
				livedExperiences: nil
			)
			try await app.test(
				.POST,
				"/api/v3/communitysupport/report",
				headers: bearer(f.memberA.token),
				beforeRequest: { req throws in try req.content.encode(data) },
				afterResponse: { res async throws in XCTAssertEqual(res.status, .created) }
			)
			try await app.test(
				.GET,
				"/api/v3/notification/global",
				headers: bearer(f.memberB.token),
				afterResponse: { res async throws in
					XCTAssertGreaterThanOrEqual(
						try res.content.decode(UserNotificationData.self).communitySupportData?.openReportCount ?? 0,
						1
					)
				}
			)
			try await app.test(
				.GET,
				"/api/v3/notification/global",
				headers: bearer(f.attendee.token),
				afterResponse: { res async throws in
					XCTAssertNil(try res.content.decode(UserNotificationData.self).communitySupportData)
				}
			)
		}
	}
}

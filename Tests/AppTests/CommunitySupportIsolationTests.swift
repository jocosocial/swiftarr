import Fluent
import XCTVapor

@testable import swiftarr

// Isolation of Community Support content (#517) from people who lose access to it, and from moderators: access that outlives a revoked role,
// the moderator bypass on posting to a shared-mailbox chat, content-creation guards on discussion threads, the audit trail for changes to
// the private forum category, and the `hiddenFromModerators` flag clients use to hide the Mod button.
class CommunitySupportIsolationTests: XCTestCase, SwiftarrBaseTest {

	private struct Fixture {
		let member: (token: String, id: UUID)
		let tt: (token: String, id: UUID)
		let tho: (token: String, id: UUID)
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
		let member = try await makeUser(app, username: "im-\(suffix)", accessLevel: .verified, role: .communitysupport)
		let tt = try await makeUser(app, username: "itt-\(suffix)", accessLevel: .twitarrteam)
		let tho = try await makeUser(app, username: "itho-\(suffix)", accessLevel: .tho)
		let mod = try await makeUser(app, username: "imod-\(suffix)", accessLevel: .moderator)
		let attendee = try await makeUser(app, username: "iatt-\(suffix)", accessLevel: .verified)
		try await app.asyncBoot()
		try await app.initializeUserCache(app)
		let req = Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
		let phantom = try XCTUnwrap(req.userCache.getUser(username: PrivilegedUser.CommunitySupport.rawValue))
		return Fixture(
			member: member,
			tt: tt,
			tho: tho,
			moderator: mod,
			attendee: attendee,
			phantomID: phantom.userID
		)
	}

	private func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

	private func makeRequest(_ app: Application) -> Request {
		Request(application: app, method: .GET, url: URI(string: "/"), on: app.eventLoopGroup.next())
	}

	/// An attendee writes to @CommunitySupport; returns the new chat's ID.
	private func attendeeWritesToTeam(_ app: Application, _ f: Fixture) async throws -> UUID {
		let data = FezContentData(
			fezType: .closed,
			visibility: nil,
			title: "Need to talk",
			info: "",
			startTime: nil,
			endTime: nil,
			location: nil,
			minCapacity: 0,
			maxCapacity: 0,
			initialUsers: [f.phantomID],
			createdByModerator: nil,
			createdByTwitarrTeam: nil,
			createdByCommunitySupport: nil,
			firstPost: PostContentData(text: "Hello team", images: [])
		)
		var fezID: UUID?
		try await app.test(
			.POST,
			"/api/v3/fez/create",
			headers: bearer(f.attendee.token),
			beforeRequest: { req throws in try req.content.encode(data) },
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .created)
				fezID = try res.content.decode(FezData.self).fezID
			}
		)
		return try XCTUnwrap(fezID)
	}

	/// Opens the chat as the shared mailbox, which is what creates the member's own pivot on it.
	private func openAsMailbox(_ app: Application, token: String, fezID: UUID) async throws {
		try await app.test(
			.GET,
			"/api/v3/fez/\(fezID)?foruser=communitysupport",
			headers: bearer(token),
			afterResponse: { res async throws in XCTAssertEqual(res.status, .ok) }
		)
	}

	private func joinedIDs(_ app: Application, token: String) async throws -> [UUID] {
		var ids: [UUID] = []
		try await app.test(
			.GET,
			"/api/v3/fez/joined?type=closed",
			headers: bearer(token),
			afterResponse: { res async throws in
				XCTAssertEqual(res.status, .ok)
				ids = try res.content.decode(FezListData.self).fezzes.map { $0.fezID }
			}
		)
		return ids
	}

	// MARK: - Access that outlives the role

	func testRemovingTheRoleRemovesTheMembersAccessToChatsTheyOpened() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let fezID = try await attendeeWritesToTeam(app, f)
			try await openAsMailbox(app, token: f.member.token, fezID: fezID)
			let before = try await FezParticipant.query(on: app.db).filter(\.$user.$id == f.member.id).count()
			XCTAssertEqual(before, 1, "opening the chat as the mailbox leaves the member a pivot on it")

			try await app.test(
				.POST,
				"/api/v3/admin/userroles/\(UserRoleType.communitysupport.rawValue)/removerole/\(f.member.id)",
				headers: bearer(f.tho.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .ok) }
			)

			let joined = try await joinedIDs(app, token: f.member.token)
			XCTAssertFalse(joined.contains(fezID))
			try await app.test(
				.GET,
				"/api/v3/fez/\(fezID)",
				headers: bearer(f.member.token),
				afterResponse: { res async throws in
					if res.status == .ok {
						XCTAssertNil(try res.content.decode(FezData.self).members, "no members or posts")
					}
				}
			)
			let remaining = try await FezParticipant.query(on: app.db).filter(\.$user.$id == f.member.id).count()
			XCTAssertEqual(remaining, 0)
		}
	}

	func testAStalePivotIsNotMembershipEvenBeforeItIsCleanedUp() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let fezID = try await attendeeWritesToTeam(app, f)
			try await openAsMailbox(app, token: f.member.token, fezID: fezID)
			// Take the role away behind the API's back, so nothing prunes the pivot.
			try await UserRole.query(on: app.db).filter(\.$user.$id == f.member.id).delete()
			try await makeRequest(app).userCache.updateUser(f.member.id)
			try await app.test(
				.GET,
				"/api/v3/fez/\(fezID)",
				headers: bearer(f.member.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .notFound) }
			)
		}
	}

	func testDemotionRemovesTheTwitarrTeamMembersPivot() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let fezID = try await attendeeWritesToTeam(app, f)
			try await openAsMailbox(app, token: f.tt.token, fezID: fezID)
			try await app.test(
				.POST,
				"/api/v3/admin/user/demote/\(f.tt.id)",
				headers: bearer(f.tho.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .ok) }
			)
			let joined = try await joinedIDs(app, token: f.tt.token)
			XCTAssertFalse(joined.contains(fezID))
		}
	}

	// MARK: - Moderators can't write into the chat either

	func testOnlyMailboxMembersCanPostToASharedMailboxChat() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let fezID = try await attendeeWritesToTeam(app, f)
			for (token, expected) in [
				(f.moderator.token, HTTPResponseStatus.forbidden), (f.member.token, .ok), (f.tt.token, .ok),
			] {
				try await app.test(
					.POST,
					"/api/v3/fez/\(fezID)/post",
					headers: bearer(token),
					beforeRequest: { req throws in try req.content.encode(PostContentData(text: "reply", images: [])) },
					afterResponse: { res async throws in XCTAssertEqual(res.status, expected) }
				)
			}
		}
	}

	// MARK: - Content guards on discussion threads

	func testQuarantinedTeamMemberCannotFileReportsOrStartDiscussions() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let report = CommunitySupportReport(
				author: f.member.id,
				data: CommunitySupportReportCreateData(
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
					experienceTime: "Tuesday",
					experienceLocation: "Lido deck",
					experienceDescription: "Something happened.",
					preferredOutcome: nil,
					livedExperiences: nil
				)
			)
			try await report.save(on: app.db)
			let found = try await User.find(f.member.id, on: app.db)
			let user = try XCTUnwrap(found)
			user.tempQuarantineUntil = Date().addingTimeInterval(3600)
			try await user.save(on: app.db)
			try await makeRequest(app).userCache.updateUser(f.member.id)

			try await app.test(
				.POST,
				"/api/v3/communitysupport/report/\(try report.requireID())/discussion",
				headers: bearer(f.member.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .forbidden) }
			)
			try await app.test(
				.POST,
				"/api/v3/communitysupport/report/\(try report.requireID())/status",
				headers: bearer(f.member.token),
				beforeRequest: { req throws in
					try req.content.encode(CommunitySupportStatusChangeData(status: .resolved, note: nil))
				},
				afterResponse: { res async throws in XCTAssertEqual(res.status, .forbidden) }
			)
			let threads = try await Forum.query(on: app.db).filter(\.$title == report.discussionTitle()).count()
			XCTAssertEqual(threads, 0)
		}
	}

	// MARK: - Audit trail

	func testChangesToOthersContentInThePrivateCategoryAreLoggedForTheTeamNotTheModerators() async throws {
		try await withApp { app in
			let f = try await makeFixture(app)
			let foundCategory = try await Category.query(on: app.db).filter(\.$requiredRole == .communitysupport).first()
			let category = try XCTUnwrap(foundCategory)
			var forumID: UUID?
			try await app.test(
				.POST,
				"/api/v3/forum/categories/\(try category.requireID())/create",
				headers: bearer(f.member.token),
				beforeRequest: { req throws in
					try req.content.encode(
						ForumCreateData(title: "Private thread", firstPost: PostContentData(text: "first", images: []))
					)
				},
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .ok)
					forumID = try res.content.decode(ForumData.self).forumID
				}
			)
			var postID: Int?
			try await app.test(
				.POST,
				"/api/v3/forum/\(try XCTUnwrap(forumID))/create",
				headers: bearer(f.member.token),
				beforeRequest: { req throws in try req.content.encode(PostContentData(text: "second", images: [])) },
				afterResponse: { res async throws in
					XCTAssertEqual(res.status, .created)
					postID = try res.content.decode(PostData.self).postID
				}
			)
			let modActionsBefore = try await ModeratorAction.query(on: app.db).count()
			try await app.test(
				.POST,
				"/api/v3/forum/post/\(try XCTUnwrap(postID))/delete",
				headers: bearer(f.tt.token),
				afterResponse: { res async throws in XCTAssertEqual(res.status, .noContent) }
			)
			let modActionsAfter = try await ModeratorAction.query(on: app.db).count()
			XCTAssertEqual(modActionsAfter, modActionsBefore, "nothing reaches the moderator log")
			// Scoped to this test's actor: the database is shared with other tests and earlier runs.
			let entries = try await CommunitySupportAction.query(on: app.db)
				.filter(\.$actionType == .contentModerated).filter(\.$actor.$id == f.tt.id).all()
			XCTAssertEqual(entries.count, 1)
			XCTAssertNil(entries.first?.$report.id)
			XCTAssertEqual(entries.first?.note, "delete: forumPost \(try XCTUnwrap(postID))")
			// Posting as yourself, or deleting your own post, isn't someone else's content and isn't logged.
			let own = try await CommunitySupportAction.query(on: app.db).filter(\.$actor.$id == f.member.id).count()
			XCTAssertEqual(own, 0)
		}
	}

	// MARK: - Mod button

	func testCategoryDataFlagsCategoriesHiddenFromModerators() throws {
		let paginator = Paginator(total: 0, start: 0, limit: 50)
		let hidden = Category(title: "Hidden", purpose: "", requiredRole: .communitysupport)
		hidden.id = UUID()
		let shutternauts = Category(title: "Shutternauts", purpose: "", requiredRole: .shutternaut)
		shutternauts.id = UUID()
		let plain = Category(title: "Plain", purpose: "")
		plain.id = UUID()
		XCTAssertTrue(try CategoryData(hidden, restricted: false, paginator: paginator).hiddenFromModerators)
		XCTAssertFalse(try CategoryData(shutternauts, restricted: false, paginator: paginator).hiddenFromModerators)
		XCTAssertFalse(try CategoryData(plain, restricted: false, paginator: paginator).hiddenFromModerators)
	}
}

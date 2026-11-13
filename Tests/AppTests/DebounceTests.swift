import Testing
import XCTVapor

@testable import swiftarr

// Has to be serialized because user cache is global, not instance-specific.
@Suite(.serialized)
class DebounceTests {
	static func suffix() -> String { UUID().uuidString.prefix(8).lowercased() }
    static func makeUser(_ app: Application, username: String, accessLevel: UserAccessLevel) async throws -> User {
		let user = User(
			username: username,
			password: try Bcrypt.hash("password1"),
			recoveryKey: try Bcrypt.hash("recovery key"),
			accessLevel: accessLevel
		)
		try await user.save(on: app.db)
		return user
	}

    static func tokenFor(_ app: Application, user: User) async throws -> String {
		let token = try Token.generate(for: user)
		try await token.save(on: app.db)
        return token.token
    }

	static func bearer(_ token: String) -> HTTPHeaders {
		var headers = HTTPHeaders()
		headers.bearerAuthorization = BearerAuthorization(token: token)
		return headers
	}

    class ForumPostDebounceTests: SwiftarrBaseTest {
        struct Fixture {
            var category: Category
            var forum: Forum
            var post: ForumPost
            var poster: User
            var token: String
        }

        private func makeFixture(_ app: Application, suffix: String, postText: String, idempotencyKey: UUID?) async throws -> Fixture {
            let poster = try await makeUser(app, username: "debounce-poster-\(suffix)", accessLevel: .verified)
            let category = Category(title: "Debounce Fixture \(suffix)", purpose: "test fixture")
            try await category.save(on: app.db)
            let forum = try Forum(title: "Debounce Fixture \(suffix)", category: category, creatorID: poster.requireID())
            try await forum.save(on: app.db)
            let post = try ForumPost(
                forum: forum,
                authorID: poster.requireID(),
                text: postText,
                images: [],
                idempotencyKey: idempotencyKey
            )
            try await post.save(on: app.db)
            let token = try await tokenFor(app, user: poster)
            
            // The cache is built from Redis, which is not reachable until the app has booted.
            try await app.asyncBoot()
            try await app.initializeUserCache(app)

            return Fixture(category: category, forum: forum, post: post, poster: poster, token: token)
        }

        @Test
        func testOwnSameKey_debounced() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: UUID())
                let body = """
                    {"text":"\(postText)", "images": [], "idempotencyKey": "\(fixture.post.idempotencyKey!)"}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/forum/\(fixture.forum.requireID())/create",
                    headers: bearer(fixture.token),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .ok)
                        let data = try res.content.decode(PostData.self)
                        try #require(data.postID == fixture.post.id)
                    }
                )
            }
        }

        @Test
        func testOwnDifferentKey_posted() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: UUID())
                
                let body = """
                    {"text":"\(postText)", "images": [], "idempotencyKey": "\(UUID())"}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/forum/\(fixture.forum.requireID())/create",
                    headers: bearer(fixture.token),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .created)
                        let data = try res.content.decode(PostData.self)
                        try #require(data.postID != fixture.post.id)
                    }
                )
            }
        }

        @Test
        func testUnsetKey_posted() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: nil)
                
                let body = """
                    {"text":"\(postText)", "images": []}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/forum/\(fixture.forum.requireID())/create",
                    headers: bearer(fixture.token),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .created)
                        let data = try res.content.decode(PostData.self)
                        try #require(data.postID != fixture.post.id)
                    }
                )
            }
        }

        @Test
        func testSameKeyDifferentUser_posted() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let poster2 = try await makeUser(app, username: "debounce-poster-\(suffix)-2", accessLevel: .verified)
                let token2 = try await tokenFor(app, user: poster2)
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: UUID())
                let body = """
                    {"text":"\(postText)", "images": [], "idempotencyKey": "\(fixture.post.idempotencyKey!)"}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/forum/\(fixture.forum.requireID())/create",
                    headers: bearer(token2),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .created)
                        let data = try res.content.decode(PostData.self)
                        try #require(data.postID != fixture.post.id)
                    }
                )
            }
        }
    }

    final class FezPostDebounceTests: SwiftarrBaseTest {
        struct Fixture {
            var fez: FriendlyFez
            var post: FezPost
            var poster: User
            var posterToken: String
            var participant: User
            var participantToken: String
        }

        private func makeFixture(_ app: Application, suffix: String, postText: String, idempotencyKey: UUID?) async throws -> Fixture {
            let poster = try await makeUser(app, username: "debounce-fez-poster-\(suffix)", accessLevel: .verified)
            let participant = try await makeUser(app, username: "debounce-fez-participant-\(suffix)", accessLevel: .verified)
            let fez = try FriendlyFez(owner: poster.requireID())
            fez.participantArray = [try poster.requireID(), try participant.requireID()]
            try await fez.save(on: app.db)
            let post = try FezPost(
                fez: fez,
                authorID: poster.requireID(),
                text: postText,
                image: nil,
                idempotencyKey: idempotencyKey
            )
            try await post.save(on: app.db)
            let token = try await tokenFor(app, user: poster)
            let participantToken = try await tokenFor(app, user: participant)
            
            // The cache is built from Redis, which is not reachable until the app has booted.
            try await app.asyncBoot()
            try await app.initializeUserCache(app)

            return Fixture(fez: fez, post: post, poster: poster, posterToken: token, participant: participant, participantToken: participantToken)
        }

        @Test
        func testOwnSameKey_debounced() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: UUID())
                let body = """
                    {"text":"\(postText)", "images":[], "idempotencyKey": "\(fixture.post.idempotencyKey!)"}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/fez/\(fixture.fez.requireID())/post",
                    headers: bearer(fixture.posterToken),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .ok)
                        let data = try res.content.decode(FezPostData.self)
                        try #require(data.postID == fixture.post.id)
                    }
                )
            }
        }

        @Test
        func testUnsetKey_posted() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: nil)
                let body = """
                    {"text":"\(postText)", "images":[]}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/fez/\(fixture.fez.requireID())/post",
                    headers: bearer(fixture.posterToken),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .ok)
                        let data = try res.content.decode(FezPostData.self)
                        try #require(data.postID != fixture.post.id)
                    }
                )
            }
        }

        @Test
        func testOwnDifferentKey_posted() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: UUID())
                

                let body = """
                    {"text":"\(postText)", "images":[], "idempotencyKey": "\(UUID())"}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/fez/\(fixture.fez.requireID())/post",
                    headers: bearer(fixture.posterToken),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .ok)
                        let data = try res.content.decode(FezPostData.self)
                        try #require(data.postID != fixture.post.id)
                    }
                )
            }
        }

        @Test
        func testSameKeyDifferentUser_posted() async throws {
            try await withApp { app in
                let suffix = suffix()
                let postText = "Post the same thing"
                let fixture = try await makeFixture(app, suffix: suffix, postText: postText, idempotencyKey: UUID())
                let body = """
                    {"text":"\(postText)", "images":[], "idempotencyKey": "\(fixture.post.idempotencyKey!)"}
                    """

                try await app.test(
                    .POST,
                    "/api/v3/fez/\(fixture.fez.requireID())/post",
                    headers: bearer(fixture.participantToken),
                    beforeRequest: { req async throws in
                        req.headers.contentType = .json
                        req.body = ByteBuffer(string: body)
                    },
                    afterResponse: { res async throws in
                        try #require(res.status == .ok)
                        let data = try res.content.decode(FezPostData.self)
                        try #require(data.postID != fixture.post.id)
                    }
                )
            }
        }
    }
}
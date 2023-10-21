import Fluent
import Vapor

/// A `Migration` that seeds the db with test data. Once we have clients that can post data, we can get rid of this file.

struct CreateTestData: AsyncMigration {

	func prepare(on database: Database) async throws {
		try await createTestTwarrts(on: database)
		try await createTestForumPosts(on: database)
		try await createTestLargeForumPosts(on: database)
		try await createTestLargeSeamailThread(on: database)
	}

	func revert(on database: Database) async throws {
		try await Twarrt.query(on: database).delete()
		guard let category = try await Category.query(on: database).filter(\.$title == "Test 1").first() else {
			throw Abort(.internalServerError, reason: "No category found.")
		}
		try await Forum.query(on: database).filter(\.$category.$id == category.requireID()).delete()
	}

	// Makes a single tweet by admin.
	func createTestTwarrts(on database: Database) async throws {
		guard let admin = try await User.query(on: database).filter(\.$username == "admin").first() else {
			throw Abort(.internalServerError, reason: "Could not find admin user.")
		}
		let twarrt = try Twarrt(authorID: admin.requireID(), text: "The one that is the first one.")
		try await twarrt.save(on: database)
	}

	// Creates a forum in Test 1, adds 6 posts to it
	func createTestForumPosts(on database: Database) async throws {
		guard let admin = try await User.query(on: database).filter(\.$username == "admin").first() else {
			throw Abort(.internalServerError, reason: "Could not find admin user.")
		}
		guard let category = try await Category.query(on: database).filter(\.$title == "Egype").first() else {
			throw Abort(.internalServerError, reason: "Test category doesn't exist;, can't make test posts.")
		}
		let thread = try Forum(title: "Say Hello Here", category: category, creatorID: admin.requireID())
		try await thread.save(on: database)
		let adminID = try admin.requireID()
		let posts: [ForumPost] = try [
			ForumPost(forum: thread, authorID: adminID, text: "First Post!"),
			ForumPost(forum: thread, authorID: adminID, text: "Second Post!"),
			ForumPost(forum: thread, authorID: adminID, text: longPost),
			ForumPost(forum: thread, authorID: adminID, text: "This is the fourth post in the stream.!"),
			ForumPost(forum: thread, authorID: adminID, text: "And then the fifth!"),
			ForumPost(forum: thread, authorID: adminID, text: "I'm just going to keep posting here. Posting is fun.!"),
		]
		try await posts.create(on: database)
	}

	// Creates a forum in Test 1, adds multiple pages of posts to it
	func createTestLargeForumPosts(on database: Database) async throws {
		let users = try await User.query(on: database).filter(\.$username ~~ ["james", "heidi", "sam", "verified"])
			.all()
		guard users.count == 4 else {
			throw Abort(.internalServerError, reason: "Users for large test thread don't exist.")
		}
		guard let category = try await Category.query(on: database).filter(\.$title == "Egype").first() else {
			throw Abort(.internalServerError, reason: "Category 'Egype' does not exist; can't make test posts.")
		}
		let thread = try Forum(title: "Long Thread Is Long", category: category, creatorID: users[0].requireID())
		try await thread.save(on: database)
		for index in 0...824 {
			var postStr: String
			switch Int.random(in: 1...10) {
			case 1: postStr = "First Post!"
			case 2:
				postStr =
					"Hey everyone, I've got a great idea! What if we all jump in the air at the same time and try to rock the boat?"
			case 3:
				postStr =
					"Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum."
			case 4:
				postStr =
					"It is a long established fact that a reader will be distracted by the readable content of a page when looking at its layout. The point of using Lorem Ipsum is that it has a more-or-less normal distribution of letters, as opposed to using "
			case 5:
				postStr =
					"All the Lorem Ipsum generators on the Internet tend to repeat predefined chunks as necessary, making this the first true generator on the Internet. It uses a dictionary of over 200 Latin words, combined with a handful of model sentence structures, to generate Lorem Ipsum which looks reasonable. The generated Lorem Ipsum is therefore always free from repetition, injected humour, or non-characteristic words etc."
			case 6: postStr = "What he said."
			case 7: postStr = "Wait. What. Really?"
			case 8: postStr = "Well that's pretty random."
			case 9: postStr = "Is anybody getting off the boat when we dock?"
			case 10: postStr = "Let it go."
			default: postStr = "Okay then, let's do it!"
			}

			let post = try ForumPost(
				forum: thread,
				authorID: users[Int.random(in: 0...3)].requireID(),
				text: "Post #\(index): \(postStr)"
			)
			try await post.save(on: database)
		}
	}

	let longPost = """
						This is a long post with lots of text. Hi everyone. I'm the Admin. I'm posting here to test out how \
						the server works. Does it handle longer posts well? I guess we'll find out soon enough, won't we?
						"""

	func createTestLargeSeamailThread(on database: Database) async throws {
		let users = try await User.query(on: database).filter(\.$username ~~ ["james", "heidi", "sam", "verified"])
			.all()
		guard users.count == 4 else {
			throw Abort(.internalServerError, reason: "Users for large test seamail thread don't exist.")
		}
		let bigChatGroup = try FriendlyChatGroup(owner: users[0].requireID())
		bigChatGroup.title = "Hey Everybody, Let's Make Lots of Posts"
		bigChatGroup.participantArray = try users.map { try $0.requireID() }
		try await bigChatGroup.save(on: database)
		try await bigChatGroup.$participants.attach(
			users,
			on: database,
			{
				$0.readCount = 0
				$0.hiddenCount = 0
			}
		)
		for index in 0...824 {
			var postStr: String
			switch Int.random(in: 1...10) {
			case 1: postStr = "First Post!"
			case 2:
				postStr =
					"Hey everyone, I've got a great idea! What if we all jump in the air at the same time and try to rock the boat?"
			case 3:
				postStr =
					"Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum."
			case 4:
				postStr =
					"It is a long established fact that a reader will be distracted by the readable content of a page when looking at its layout. The point of using Lorem Ipsum is that it has a more-or-less normal distribution of letters, as opposed to using "
			case 5:
				postStr =
					"All the Lorem Ipsum generators on the Internet tend to repeat predefined chunks as necessary, making this the first true generator on the Internet. It uses a dictionary of over 200 Latin words, combined with a handful of model sentence structures, to generate Lorem Ipsum which looks reasonable. The generated Lorem Ipsum is therefore always free from repetition, injected humour, or non-characteristic words etc."
			case 6: postStr = "What he said."
			case 7: postStr = "Wait. What. Really?"
			case 8: postStr = "Well that's pretty random."
			case 9: postStr = "Is anybody getting off the boat when we dock?"
			case 10: postStr = "Let it go."
			default: postStr = "Okay then, let's do it!"
			}

			let post = try ChatGroupPost(
				chatgroup: bigChatGroup,
				authorID: users.randomElement()!.requireID(),
				text: "Post #\(index): \(postStr)",
				image: nil
			)
			try await post.save(on: database)
		}
		bigChatGroup.postCount = 825
		try await bigChatGroup.save(on: database)
	}
}

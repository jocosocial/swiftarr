import Vapor
import Fluent

/// A `Migration` that seeds the db with test data. Once we have clients that can post data, we can get rid of this file.

struct CreateTestData: Migration {
	
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		let futures: [EventLoopFuture<Void>] = [
			createTestTwarrts(on: database),	
			createTestForumPosts(on: database),
			createTestLargeForumPosts(on: database)
		]
		return futures.flatten(on: database.eventLoop).transform(to: ())
	}

    func revert(on database: Database) -> EventLoopFuture<Void> {
 		let futures: [EventLoopFuture<Void>] = [
   			Twarrt.query(on: database).delete(),
			Category.query(on: database)
				.filter(\.$title == "Test 1")
				.first()
				.unwrap(or: Abort(.internalServerError, reason: "No category found."))
				.addModelID()
				.throwingFlatMap { (category, categoryID) in
					Forum.query(on: database).filter(\.$category.$id == categoryID).delete()
				}
		]
		return futures.flatten(on: database.eventLoop).transform(to: ())
    }
    
    // Makes a single tweet by admin.
    func createTestTwarrts(on database: Database) -> EventLoopFuture<Void> {
        return User.query(on: database).first().throwingFlatMap { (admin) in
			let twarrt = try Twarrt(author: admin!, text: "The one that is the first one.")
			return twarrt.save(on: database).transform(to: ())
		}
    }

	
	// Creates a forum in Test 1, adds 6 posts to it
	func createTestForumPosts(on database: Database) -> EventLoopFuture<Void> {
        return User.query(on: database).first()
        		.unwrap(or: Abort(.internalServerError, reason: "No admin user"))
        		.flatMap { (admin) in
        	return Category.query(on: database).all().throwingFlatMap { categories in
        		guard let category = categories.first(where: { $0.title == "Test 1" }) else {
        			throw Abort(.internalServerError, reason: "Test category doesn't exist;, can't make test posts.")
        		}
				let thread = try Forum(title: "Say Hello Here", category: category, creator: admin)
				return thread.save(on: database).transform(to: thread)
			}
        	.throwingFlatMap { (thread: Forum) in
				let posts: [ForumPost] = try [
					ForumPost(forum: thread, author: admin, text: "First Post!"),
					ForumPost(forum: thread, author: admin, text: "Second Post!"),
					ForumPost(forum: thread, author: admin, text: longPost),
					ForumPost(forum: thread, author: admin, text: "This is the fourth post in the stream.!"),
					ForumPost(forum: thread, author: admin, text: "And then the fifth!"),
					ForumPost(forum: thread, author: admin, text: "I'm just going to keep posting here. Posting is fun.!"),
				]
				let futures = posts.map { $0.save(on: database) }
				return futures.flatten(on: database.eventLoop).transform(to: ())
			}
		}
	}
	
	// Creates a forum in Test 1, adds multiple pages of posts to it
	func createTestLargeForumPosts(on database: Database) -> EventLoopFuture<Void> {
		return User.query(on: database).filter(\.$username ~~ ["james", "heidi", "sam", "verified"]).all()
				.throwingFlatMap { (users) in
			guard users.count == 4 else {
				throw Abort(.internalServerError, reason: "Users for large test thread don't exist.")
			}
			return Category.query(on: database).filter(\.$title == "Test 1").first()
					.unwrap(or: Abort(.internalServerError, reason: "Category 'Test 1' does not exist; can't make test posts."))
					.throwingFlatMap { category in
				let thread = try Forum(title: "Long Thread Is Long", category: category, creator: users[0])
				return thread.save(on: database).transform(to: thread)
			}
			.throwingFlatMap { (thread: Forum) in
				var futures: [EventLoopFuture<Void>] = []
				for index in 0...824 {
					var postStr: String
					switch Int.random(in: 1...10) {
					case 1: postStr = "First Post!"
					case 2: postStr = "Hey everyone, I've got a great idea! What if we all jump in the air at the same time and try to rock the boat?"
					case 3: postStr = "Lorem Ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled it to make a type specimen book. It has survived not only five centuries, but also the leap into electronic typesetting, remaining essentially unchanged. It was popularised in the 1960s with the release of Letraset sheets containing Lorem Ipsum passages, and more recently with desktop publishing software like Aldus PageMaker including versions of Lorem Ipsum."
					case 4: postStr = "It is a long established fact that a reader will be distracted by the readable content of a page when looking at its layout. The point of using Lorem Ipsum is that it has a more-or-less normal distribution of letters, as opposed to using "
					case 5: postStr = "All the Lorem Ipsum generators on the Internet tend to repeat predefined chunks as necessary, making this the first true generator on the Internet. It uses a dictionary of over 200 Latin words, combined with a handful of model sentence structures, to generate Lorem Ipsum which looks reasonable. The generated Lorem Ipsum is therefore always free from repetition, injected humour, or non-characteristic words etc."
					case 6: postStr = "What he said."
					case 7: postStr = "Wait. What. Really?"
					case 8: postStr = "Well that's pretty random."
					case 9: postStr = "Is anybody getting off the boat when we dock?"
					case 10: postStr = "Let it go."
					default: postStr = "Okay then, let's do it!"
					}
					
					let post = try ForumPost(forum: thread, author: users[Int.random(in:0...3)], text: "Post #\(index): \(postStr)")
					futures.append(post.save(on: database))
				}
				return futures.flatten(on: database.eventLoop).transform(to: ())
			}
		}
	}
	
	
	let longPost = """
		This is a long post with lots of text. Hi everyone. I'm the Admin. I'm posting here to test out how \
		the server works. Does it handle longer posts well? I guess we'll find out soon enough, won't we?
		"""
}


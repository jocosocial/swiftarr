import Vapor
import Fluent

/// A `Migration` that seeds the db with test data. Once we have clients that can post data, we can get rid of this file.

struct CreateTestData: Migration {
	
	func prepare(on database: Database) -> EventLoopFuture<Void> {
		let futures: [EventLoopFuture<Void>] = [
			createTestTwarrts(on: database),	
			createTestForumPosts(on: database)
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
    
    func createTestTwarrts(on database: Database) -> EventLoopFuture<Void> {
        return User.query(on: database).first().throwingFlatMap { (admin) in
			let twarrt = try Twarrt(author: admin!, text: "The one that is the first one.")
			return twarrt.save(on: database).transform(to: ())
		}
    }

	
	//
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
	
	let longPost = """
		This is a long post with lots of text. Hi everyone. I'm the Admin. I'm posting here to test out how \
		the server works. Does it handle longer posts well? I guess we'll find out soon enough, won't we?
		"""
}


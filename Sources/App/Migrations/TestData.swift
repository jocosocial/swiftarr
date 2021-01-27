import Vapor
import Fluent

/// A `Migration` that seeds the db with test data. Once we have clients that can post data, we can get rid of this file.

struct CreateTestData: Migration {
	
	func prepare(on database: Database) -> EventLoopFuture<Void> {
        return User.query(on: database).first().throwingFlatMap { (admin) in
			let twarrt = try Twarrt(author: admin!, text: "The one that is the first one.")
			return twarrt.save(on: database).transform(to: ())
		}
	}

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forums").delete()
    }

}

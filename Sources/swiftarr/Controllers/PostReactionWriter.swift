import Fluent
import FluentSQL
import Vapor

/// Locks a post row inside a transaction before reading or changing its reactions.
enum PostReactionWriter {
	/// Serializes writers across server processes, including when the post has no reactions yet.
	static func lock(postID: Int, table: String, on db: Database) async throws {
		guard let sql = db as? SQLDatabase else {
			throw Abort(.internalServerError, reason: "Reaction writes require SQL")
		}
		try await sql.raw("SELECT id FROM \(ident: table) WHERE id = \(bind: postID) FOR UPDATE").run()
	}
}

import Fluent
import FluentSQL
import Vapor

/// Locks a post row inside a transaction before reading or changing its reactions.
enum PostReactionWriter {
	/// Advances the revision while the caller holds the post lock in its mutation transaction.
	static func advance(postID: Int, table: String, on db: Database) async throws {
		guard let sql = db as? SQLDatabase else { throw Abort(.internalServerError) }
		try await sql.raw("UPDATE \(ident: table) SET \(ident: "reactionRevision") = \(ident: "reactionRevision") + 1 WHERE id = \(bind: postID)").run()
	}

	/// Serializes writers across server processes, including when the post has no reactions yet.
	static func lock(postID: Int, table: String, on db: Database) async throws {
		guard let sql = db as? SQLDatabase else {
			throw Abort(.internalServerError, reason: "Reaction writes require SQL")
		}
		try await sql.raw("SELECT id FROM \(ident: table) WHERE id = \(bind: postID) FOR UPDATE").run()
	}
}

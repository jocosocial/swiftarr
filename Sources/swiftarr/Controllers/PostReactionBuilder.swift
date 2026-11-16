import Fluent
import FluentSQL
import Vapor

/// Reads revision and contributors in one statement, so they describe the same database snapshot.
enum PostReactionBuilder {
	struct Snapshot {
		var reactions: [ReactionData] = []
		var revision: Int = 0
	}

	/// Builds forum snapshots, optionally on the caller's transaction.
	static func forum(postIDs: [Int], on req: Request, db: Database? = nil) async throws -> [Int: Snapshot] {
		try await snapshots(postIDs: postIDs, table: ForumPost.schema, reactions: ForumPostReaction.schema,
			foreignKey: "forumPost", on: req, db: db ?? req.db)
	}

	/// Builds chat snapshots, optionally on the caller's transaction.
	static func fez(postIDs: [Int], on req: Request, db: Database? = nil) async throws -> [Int: Snapshot] {
		try await snapshots(postIDs: postIDs, table: FezPost.schema, reactions: FezPostReaction.schema,
			foreignKey: "fezPost", on: req, db: db ?? req.db)
	}

	/// A left join retains the revision when the final reaction has been removed.
	private static func snapshots(postIDs: [Int], table: String, reactions: String, foreignKey: String,
		on req: Request, db: Database) async throws -> [Int: Snapshot] {
		guard !postIDs.isEmpty else { return [:] }
		guard let sql = db as? SQLDatabase else { throw Abort(.internalServerError) }
		struct Row: Decodable {
			var postID: Int
			var revision: Int
			var emoji: String?
			var userID: UUID?
		}
		let rows = try await sql.raw("""
			SELECT p.id AS "postID", p.\(ident: "reactionRevision") AS revision,
				r.emoji, r.\(ident: "user") AS "userID"
			FROM \(ident: table) p LEFT JOIN \(ident: reactions) r ON r.\(ident: foreignKey) = p.id
			WHERE p.id IN (\(binds: postIDs)) ORDER BY r.\(ident: "createdAt"), r.\(ident: "groupOrder")
			""").all(decoding: Row.self)
		var result = [Int: Snapshot]()
		var users = [Int: [String: [UUID]]]()
		var order = [Int: [String]]()
		for row in rows {
			result[row.postID] = Snapshot(revision: row.revision)
			guard let emoji = row.emoji, let userID = row.userID else { continue }
			if users[row.postID]?[emoji] == nil { order[row.postID, default: []].append(emoji) }
			users[row.postID, default: [:]][emoji, default: []].append(userID)
		}
		for (postID, emojis) in order {
			result[postID]?.reactions = emojis.map {
				ReactionData(reaction: $0, users: req.userCache.getHeaders(users[postID]?[$0] ?? []))
			}
		}
		return result
	}
}

import Fluent
import FluentSQL

/// Indexes the reaction tables by post.
///
/// Reactions are read by post: every thread and chat page asks for the reactions of the posts it shows, and adding
/// a reaction looks up the post's existing chip for that emoji. The tables' only other index is their unique
/// constraint, which leads with the user and so cannot serve either lookup; without these, each one scans the table.
struct AddPostReactionIndexes: AsyncMigration {
	private static let indexes = [
		(name: "idx_forumpost_reactions_post_emoji", table: ForumPostReaction.schema, post: "forumPost"),
		(name: "idx_fezpost_reactions_post_emoji", table: FezPostReaction.schema, post: "fezPost"),
	]

	func prepare(on database: Database) async throws {
		guard let sql = database as? SQLDatabase else { return }
		for index in Self.indexes {
			try await sql.raw(
				"CREATE INDEX IF NOT EXISTS \(ident: index.name) ON \(ident: index.table) (\(ident: index.post), \(ident: "emoji"))"
			).run()
		}
	}

	func revert(on database: Database) async throws {
		guard let sql = database as? SQLDatabase else { return }
		for index in Self.indexes {
			try await sql.raw("DROP INDEX IF EXISTS \(ident: index.name)").run()
		}
	}
}

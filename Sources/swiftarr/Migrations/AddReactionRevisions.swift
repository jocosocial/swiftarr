import Fluent
import FluentSQL

/// Persists a monotonically increasing reaction revision even when a post has no reactions.
struct AddReactionRevisions: AsyncMigration {
	func prepare(on database: Database) async throws {
		for table in [ForumPost.schema, FezPost.schema] {
			try await database.schema(table).field("reactionRevision", .int64, .required, .sql(.default(SQLRaw("0")))).update()
		}
	}

	func revert(on database: Database) async throws {
		for table in [ForumPost.schema, FezPost.schema] {
			try await database.schema(table).deleteField("reactionRevision").update()
		}
	}
}

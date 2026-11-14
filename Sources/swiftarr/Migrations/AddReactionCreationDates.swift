import Fluent
import FluentSQL

/// Records insertion time so newly introduced reaction chips follow existing ones.
struct AddReactionCreationDates: AsyncMigration {
	/// Existing reactions receive one baseline timestamp; their original insertion times are unknown.
	func prepare(on database: Database) async throws {
		for schema in [ForumPostReaction.schema, FezPostReaction.schema] {
			try await database.schema(schema)
				.field("createdAt", .datetime, .required, .sql(.default(SQLRaw("CURRENT_TIMESTAMP"))))
				.update()
		}
	}

	/// Removes the ordering metadata while retaining reactions.
	func revert(on database: Database) async throws {
		for schema in [ForumPostReaction.schema, FezPostReaction.schema] {
			try await database.schema(schema).deleteField("createdAt").update()
		}
	}
}

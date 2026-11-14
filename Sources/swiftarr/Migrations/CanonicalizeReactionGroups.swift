import Fluent
import FluentSQL
import Vapor

/// Merges equivalent Unicode forms and preserves the original position on every contributor's row.
struct CanonicalizeReactionGroups: AsyncMigration {
	/// Removes duplicate submissions before canonicalizing to avoid violating the unique reaction constraint.
	func prepare(on database: Database) async throws {
		guard let sql = database as? SQLDatabase else { throw Abort(.internalServerError, reason: "Reaction migration requires SQL") }
		for (table, post) in [(ForumPostReaction.schema, "forumPost"), (FezPostReaction.schema, "fezPost")] {
			try await database.schema(table).field("groupOrder", .uuid).update()
			// Identifiers come exclusively from the two static schema definitions above.
			let plain = "normalize(replace(replace(\"emoji\", '\u{FE0E}', ''), '\u{FE0F}', ''), NFC)"
			let canonical = "CASE WHEN \(plain) = '❤' THEN '❤️' ELSE \(plain) END"
			try await sql.raw(SQLQueryString(stringLiteral: """
				DELETE FROM "\(table)" WHERE "id" IN (
					SELECT "id" FROM (
						SELECT "id", ROW_NUMBER() OVER (
							PARTITION BY "user", "\(post)", \(canonical) ORDER BY "createdAt", "id"
						) AS duplicate_rank FROM "\(table)"
					) ranked WHERE duplicate_rank > 1
				)
				""")).run()
			try await sql.raw(SQLQueryString(stringLiteral: "UPDATE \"\(table)\" SET \"emoji\" = \(canonical)")).run()
			try await sql.raw(SQLQueryString(stringLiteral: """
				UPDATE "\(table)" reaction SET "createdAt" = groups.first_date, "groupOrder" = groups.first_id
				FROM (
					SELECT "id",
						FIRST_VALUE("createdAt") OVER chip AS first_date,
						FIRST_VALUE("id") OVER chip AS first_id
					FROM "\(table)"
					WINDOW chip AS (PARTITION BY "\(post)", "emoji" ORDER BY "createdAt", "id")
				) groups WHERE reaction."id" = groups."id"
				""")).run()
			try await sql.raw(SQLQueryString(stringLiteral: "ALTER TABLE \"\(table)\" ALTER COLUMN \"groupOrder\" SET NOT NULL")).run()
		}
	}

	/// Drops group ordering metadata; normalization intentionally retains the canonical stored values.
	func revert(on database: Database) async throws {
		for table in [ForumPostReaction.schema, FezPostReaction.schema] {
			try await database.schema(table).deleteField("groupOrder").update()
		}
	}
}

import Fluent
import FluentSQL

/// Converts legacy forum likes into reaction rows using the legacy routes' exact emoji strings.
struct MigratePostLikesToReactions: AsyncMigration {
	/// Original like times are unknown, so every converted row shares one date; each post's chip gets one
	/// group identifier, derived deterministically because a volatile function is re-evaluated for every row.
	func prepare(on database: Database) async throws {
		if let sql = database as? SQLDatabase {
			let _ = try await sql.raw("""
				INSERT INTO "forumpost+reactions" ("id", "emoji", "user", "forumPost", "createdAt", "groupOrder")
				SELECT gen_random_uuid(),
				       CASE "liketype"
				           WHEN 'laugh' THEN '😆'
				           WHEN 'like' THEN '👍'
				           WHEN 'love' THEN '❤️'
				       END,
				       "user",
				       "forumPost",
				       CURRENT_TIMESTAMP,
				       md5("forumPost"::text || ':' || "liketype")::uuid
				FROM "post+likes"
				WHERE "liketype" IS NOT NULL
				""").all()
		}
		try await database.schema("post+likes").deleteField("liketype").update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("post+likes").field("liketype", .string).update()
		if let sql = database as? SQLDatabase {
			let _ = try await sql.raw("""
				UPDATE "post+likes" pl
				SET "liketype" = migrated."liketype"
				FROM (
				    SELECT DISTINCT ON ("user", "forumPost")
				        "user",
				        "forumPost",
				        CASE "emoji"
				            WHEN '😆' THEN 'laugh'
				            WHEN '👍' THEN 'like'
				            WHEN '❤️' THEN 'love'
				        END AS "liketype"
				    FROM "forumpost+reactions"
				    WHERE "emoji" IN ('😆', '👍', '❤️')
				) AS migrated
				WHERE pl."user" = migrated."user"
				  AND pl."forumPost" = migrated."forumPost"
				""").all()
		}
	}
}

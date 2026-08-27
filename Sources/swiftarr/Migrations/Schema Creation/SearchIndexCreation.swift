import FluentSQL

struct CreateSearchIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		try await sqlDatabase.raw("CREATE EXTENSION IF NOT EXISTS pg_trgm").run()

		try await sqlDatabase.addFullTextSearchColumn(tableName: "twarrt", tsvectorExpression: "to_tsvector('english', text)")
		try await sqlDatabase.addFullTextSearchColumn(tableName: "forum", tsvectorExpression: "to_tsvector('english', title)")
		try await sqlDatabase.addFullTextSearchColumn(tableName: "forumpost", tsvectorExpression: "to_tsvector('english', text)")
		try await sqlDatabase.addFullTextSearchColumn(
			tableName: "event",
			tsvectorExpression: "to_tsvector('english', coalesce(title, '') || ' ' || coalesce(info, ''))"
		)
		try await sqlDatabase.addFullTextSearchColumn(tableName: "boardgame", tsvectorExpression: "to_tsvector('english', \"gameName\")")
		try await sqlDatabase.addFullTextSearchColumn(
			tableName: "karaoke_song",
			tsvectorExpression: "to_tsvector('english', coalesce(artist, '') || ' ' || coalesce(title, ''))"
		)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "twarrt")
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "forum")
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "forumpost")
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "event")
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "boardgame")
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "karaoke_song")

		try await sqlDatabase.raw("DROP EXTENSION IF EXISTS pg_trgm").run()
	}
}

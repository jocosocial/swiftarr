import FluentSQL

struct CreateSearchIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		try await sqlDatabase.raw("CREATE EXTENSION IF NOT EXISTS pg_trgm").run()

		try await createTwarrtSearch(on: sqlDatabase)
		try await createForumSearch(on: sqlDatabase)
		try await createForumPostSearch(on: sqlDatabase)
		try await createEventSearch(on: sqlDatabase)
		try await createBoardgameSearch(on: sqlDatabase)
		try await createKaraokeSongSearch(on: sqlDatabase)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "twarrt")
		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "forum")
		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "forumpost")
		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "event")
		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "boardgame")
		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "karaoke_song")

		try await sqlDatabase.raw("DROP EXTENSION IF EXISTS pg_trgm").run()
	}

	func createTwarrtSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE twarrt
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', text)) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "twarrt")
	}

	func createForumSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE forum
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', title)) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "forum")
	}

	func createForumPostSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE forumpost
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', text)) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "forumpost")
	}

	func createEventSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE event
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(info, ''))) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "event")
	}

	func createBoardgameSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE boardgame
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', "gameName")) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "boardgame")
	}

	func createKaraokeSongSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE karaoke_song
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', coalesce(artist, '') || ' ' || coalesce(title, ''))) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "karaoke_song")
	}

	func createSearchIndex(on database: SQLDatabase, tableName: String) async throws {
		try await database.raw(
			"""
			  CREATE INDEX IF NOT EXISTS idx_\(raw: tableName)_search
			  ON \(raw: tableName)
			  USING GIN
			  (fulltext_search)
			"""
		)
		.run()
	}

	func dropSearchIndexAndColumn(on database: SQLDatabase, tableName: String) async throws {
		try await database
			.drop(index: "idx_\(tableName)_search")
			.run()

		try await database
			.alter(table: tableName)
			.dropColumn("fulltext_search")
			.run()
	}
}

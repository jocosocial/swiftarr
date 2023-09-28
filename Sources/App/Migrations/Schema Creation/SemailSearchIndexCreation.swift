import FluentSQL

struct CreateSeamailSearchIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await createGroupPostsSearch(on: sqlDatabase)
		try await createFriendlyGroupSearch(on: sqlDatabase)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "groupposts")
		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "friendlygroup")
	}

	func createGroupPostsSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE groupposts
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', text)) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "groupposts")
	}

	func createFriendlyGroupSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE friendlygroup
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(info, ''))) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "friendlygroup")
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

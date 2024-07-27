import FluentSQL

struct CreatePersonalEventSearchIndexes: AsyncMigration {
	static let schema = "personal_event"

	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await createPersonalEventSearch(on: sqlDatabase)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: CreatePersonalEventSearchIndexes.schema)
	}

	func createPersonalEventSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE \(unsafeRaw: CreatePersonalEventSearchIndexes.schema)
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: CreatePersonalEventSearchIndexes.schema)
	}

	func createSearchIndex(on database: SQLDatabase, tableName: String) async throws {
		try await database.raw(
			"""
			  CREATE INDEX IF NOT EXISTS idx_\(unsafeRaw: tableName)_search
			  ON \(ident: tableName)
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

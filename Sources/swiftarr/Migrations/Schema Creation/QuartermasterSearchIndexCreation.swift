import FluentSQL

struct CreateQuartermasterSearchIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		try await createQuartermasterItemSearch(on: sqlDatabase)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "quartermaster_item")
	}

	func createQuartermasterItemSearch(on database: SQLDatabase) async throws {
		try await database.raw(
			"""
			  ALTER TABLE quartermaster_item
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (
			      to_tsvector('english',
			        coalesce(item_name, '') || ' ' ||
			        coalesce(item_description, '') || ' ' ||
			        coalesce(location, ''))
			    ) STORED;
			"""
		)
		.run()

		try await createSearchIndex(on: database, tableName: "quartermaster_item")
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

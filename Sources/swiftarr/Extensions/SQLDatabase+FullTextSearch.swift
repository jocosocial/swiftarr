import FluentSQL

/// Shared helpers for the `Create*SearchIndexes` migrations (see `SearchIndexCreation.swift`,
/// `SeamailSearchIndexCreation.swift`, `QuartermasterSearchIndexCreation.swift`), which each add a
/// stored generated `fulltext_search` tsvector column plus a GIN index to one or more tables.
/// Centralized here so the full-text index strategy only needs to change in one place.
extension SQLDatabase {

	/// Adds a `fulltext_search` tsvector column to `tableName`, generated from `tsvectorExpression`
	/// (a raw SQL expression, e.g. `"to_tsvector('english', text)"`), and creates a GIN index over it.
	func addFullTextSearchColumn(tableName: String, tsvectorExpression: String) async throws {
		try await self.raw(
			"""
			  ALTER TABLE \(unsafeRaw: tableName)
			  ADD COLUMN IF NOT EXISTS fulltext_search tsvector
			    GENERATED ALWAYS AS (\(unsafeRaw: tsvectorExpression)) STORED;
			"""
		)
		.run()

		try await createSearchIndex(tableName: tableName)
	}

	func createSearchIndex(tableName: String) async throws {
		try await self.raw(
			"""
			  CREATE INDEX IF NOT EXISTS idx_\(unsafeRaw: tableName)_search
			  ON \(ident: tableName)
			  USING GIN
			  (fulltext_search)
			"""
		)
		.run()
	}

	func dropSearchIndexAndColumn(tableName: String) async throws {
		try await self
			.drop(index: "idx_\(tableName)_search")
			.run()

		try await self
			.alter(table: tableName)
			.dropColumn("fulltext_search")
			.run()
	}
}

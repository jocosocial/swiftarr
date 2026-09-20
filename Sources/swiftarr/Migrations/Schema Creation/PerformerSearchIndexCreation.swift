import FluentSQL

struct CreatePerformerSearchIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		// Postgres's generic array I/O routines (used by both `array_to_string` and a plain `::text` cast)
		// are marked STABLE rather than IMMUTABLE, because they dispatch through the array element type's
		// output function, which isn't provably immutable for every possible element type -- even though
		// it genuinely is for `text`. A thin SQL wrapper declared IMMUTABLE here sidesteps that, which is
		// safe since `text[]` output never varies by locale or session state.
		try await sqlDatabase.raw(
			"""
			CREATE OR REPLACE FUNCTION performer_alt_names_to_text(text[]) RETURNS text AS
			$$ SELECT array_to_string($1, ' ') $$ LANGUAGE sql IMMUTABLE
			"""
		)
		.run()

		try await sqlDatabase.addFullTextSearchColumn(
			tableName: "performer",
			tsvectorExpression: """
				to_tsvector('english',
				  coalesce(name, '') || ' ' ||
				  coalesce(organization, '') || ' ' ||
				  coalesce(title, '') || ' ' ||
				  coalesce(bio, '') || ' ' ||
				  coalesce(performer_alt_names_to_text(alternative_names), ''))
				"""
		)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "performer")
		try await sqlDatabase.raw("DROP FUNCTION IF EXISTS performer_alt_names_to_text(text[])").run()
	}
}

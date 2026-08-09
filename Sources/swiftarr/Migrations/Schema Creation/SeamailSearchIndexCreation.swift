import FluentSQL

struct CreateSeamailSearchIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await sqlDatabase.addFullTextSearchColumn(tableName: "fezposts", tsvectorExpression: "to_tsvector('english', text)")
		try await sqlDatabase.addFullTextSearchColumn(
			tableName: "friendlyfez",
			tsvectorExpression: "to_tsvector('english', coalesce(title, '') || ' ' || coalesce(info, ''))"
		)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "fezposts")
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "friendlyfez")
	}
}

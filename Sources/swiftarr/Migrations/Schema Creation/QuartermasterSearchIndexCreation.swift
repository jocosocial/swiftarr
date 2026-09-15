import FluentSQL

struct CreateQuartermasterSearchIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		try await sqlDatabase.addFullTextSearchColumn(
			tableName: "quartermaster_item",
			tsvectorExpression: """
				to_tsvector('english',
				  coalesce(item_name, '') || ' ' ||
				  coalesce(item_description, '') || ' ' ||
				  coalesce(location, ''))
				"""
		)
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)
		try await sqlDatabase.dropSearchIndexAndColumn(tableName: "quartermaster_item")
	}
}

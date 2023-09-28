import FluentSQL

struct CreatePerformanceIndexes: AsyncMigration {
	func prepare(on database: Database) async throws {
		let sqlDatabase: (SQLDatabase) = (database as! SQLDatabase)

		try await create_index(on: sqlDatabase, tableName: "forum", columnName: "category_id")
		try await create_index(on: sqlDatabase, tableName: "forumpost", columnName: "forum")
		try await create_index(on: sqlDatabase, tableName: "groupposts", columnName: "friendly_group")
		try await create_index(on: sqlDatabase, tableName: "event", columnName: "forum_id")
		try await create_index(on: sqlDatabase, tableName: "group_edit", columnName: "group")
		try await create_index(on: sqlDatabase, tableName: "forum_edit", columnName: "forum")
		try await create_index(on: sqlDatabase, tableName: "forum_post_edit", columnName: "post")
		try await create_index(on: sqlDatabase, tableName: "karaoke_played_song", columnName: "song")
		try await create_index(on: sqlDatabase, tableName: "muteword", columnName: "user")
		try await create_index(on: sqlDatabase, tableName: "profileedit", columnName: "user")
		try await create_index(on: sqlDatabase, tableName: "token", columnName: "user")
		try await create_index(on: sqlDatabase, tableName: "twarrt", columnName: "reply_group")
		try await create_index(on: sqlDatabase, tableName: "twarrtedit", columnName: "twarrt")
		try await create_index(on: sqlDatabase, tableName: "usernote", columnName: "note_subject")
	}

	func revert(on database: Database) async throws {
		let sqlDatabase = (database as! SQLDatabase)

		try await drop_index(on: sqlDatabase, tableName: "forum", columnName: "category_id")
		try await drop_index(on: sqlDatabase, tableName: "forumpost", columnName: "forum")
		try await drop_index(on: sqlDatabase, tableName: "groupposts", columnName: "friendly_group")
		try await drop_index(on: sqlDatabase, tableName: "event", columnName: "forum_id")
		try await drop_index(on: sqlDatabase, tableName: "group_edit", columnName: "group")
		try await drop_index(on: sqlDatabase, tableName: "forum_edit", columnName: "forum")
		try await drop_index(on: sqlDatabase, tableName: "forum_post_edit", columnName: "post")
		try await drop_index(on: sqlDatabase, tableName: "karaoke_played_song", columnName: "song")
		try await drop_index(on: sqlDatabase, tableName: "muteword", columnName: "user")
		try await drop_index(on: sqlDatabase, tableName: "profileedit", columnName: "user")
		try await drop_index(on: sqlDatabase, tableName: "token", columnName: "user")
		try await drop_index(on: sqlDatabase, tableName: "twarrt", columnName: "reply_group")
		try await drop_index(on: sqlDatabase, tableName: "twarrtedit", columnName: "twarrt")
		try await drop_index(on: sqlDatabase, tableName: "usernote", columnName: "note_subject")
	}

	func create_index(on sqlDatabase: SQLDatabase, tableName: String, columnName: String) async throws {
		try await sqlDatabase.create(index: "idx_\(tableName)_\(columnName)")
			.on(tableName)
			.column(columnName)
			.run()
	}

	func drop_index(on sqlDatabase: SQLDatabase, tableName: String, columnName: String) async throws {
		try await sqlDatabase.drop(index: "idx_\(tableName)_\(columnName)").run()
	}
}

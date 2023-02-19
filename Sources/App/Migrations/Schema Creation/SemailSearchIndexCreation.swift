import FluentSQL

struct CreateSeamailSearchIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
      let sqlDatabase = (database as! SQLDatabase)

      try await createFezPostsSearch(on: sqlDatabase)
      try await createFriendlyFezSearch(on: sqlDatabase)
    }

    func revert(on database: Database) async throws {
      let sqlDatabase = (database as! SQLDatabase)

      try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "fezposts")
      try await dropSearchIndexAndColumn(on: sqlDatabase, tableName: "friendlyfez")
    }

    func createFezPostsSearch(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE fezposts
        ADD COLUMN IF NOT EXISTS fulltext_search tsvector
          GENERATED ALWAYS AS (to_tsvector('english', text)) STORED;
      """).run()

      try await createSearchIndex(on: database, tableName: "fezposts")
    }

    func createFriendlyFezSearch(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE friendlyfez
        ADD COLUMN IF NOT EXISTS fulltext_search tsvector
          GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(info, ''))) STORED;
      """).run()

      try await createSearchIndex(on: database, tableName: "friendlyfez")
    }

    func createSearchIndex(on database: SQLDatabase, tableName: String) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_\(raw: tableName)_search
        ON \(raw: tableName)
        USING GIN
        (fulltext_search)
      """).run()
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

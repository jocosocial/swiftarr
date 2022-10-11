import FluentSQL

struct CreateSearchIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
      let sqlDatabase = (database as! SQLDatabase)
      try await sqlDatabase.raw("CREATE EXTENSION IF NOT EXISTS pg_trgm").run()

      try await createTwarrtSearchIndex(on: sqlDatabase)
      try await createForumSearchIndex(on: sqlDatabase)
      try await createForumPostSearchIndex(on: sqlDatabase)
      try await createEventSearchIndex(on: sqlDatabase)
      try await createBoardgameSearchIndex(on: sqlDatabase)
      try await createKaraokeSongSearchIndex(on: sqlDatabase)
    }

    func revert(on database: Database) async throws {
      let sqlDatabase = (database as! SQLDatabase)

      try await dropTwarrtSearchIndex(on: sqlDatabase)
      try await dropForumSearchIndex(on: sqlDatabase)
      try await dropForumPostSearchIndex(on: sqlDatabase)
      try await dropEventSearchIndex(on: sqlDatabase)
      try await dropBoardgameSearchIndex(on: sqlDatabase)
      try await dropKaraokeSongSearchIndex(on: sqlDatabase)

      try await sqlDatabase.raw("DROP EXTENSION IF EXISTS pg_trgm").run()
    }

    func createTwarrtSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_twarrt_search
        ON twarrt
        USING GIN
        (text gin_trgm_ops)
      """).run()
    }

    func dropTwarrtSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_twarrt_search")
        .run()
    }

    func createForumSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_forum_search
        ON forum
        USING GIN
        (title gin_trgm_ops)
      """).run()
    }

    func dropForumSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_forum_search")
        .run()
    }

    func createForumPostSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_forumpost_search
        ON forumpost
        USING GIN
        (text gin_trgm_ops)
      """).run()
    }

    func dropForumPostSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_forumpost_search")
        .run()
    }

    func createEventSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_event_search
        ON event
        USING GIN
        (title gin_trgm_ops, info gin_trgm_ops)
      """).run()
    }

    func dropEventSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_event_search")
        .run()
    }

    func createBoardgameSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_boardgame_search
        ON boardgame
        USING GIN
        ("gameName" gin_trgm_ops)
      """).run()
    }

    func dropBoardgameSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_boardgame_search")
        .run()
    }

    func createKaraokeSongSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_karaoke_song_search
        ON karaoke_song
        USING GIN
        (artist gin_trgm_ops, title gin_trgm_ops)
      """).run()
    }

    func dropKaraokeSongSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_karaoke_song_search")
        .run()
    }
}

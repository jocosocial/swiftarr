import FluentSQL

struct CreateSearchIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
      let sqlDatabase = (database as! SQLDatabase)
      try await sqlDatabase.raw("CREATE EXTENSION IF NOT EXISTS pg_trgm").run()

      try await createTwarrtSearchField(on: sqlDatabase)
      try await createTwarrtSearchIndex(on: sqlDatabase)

      try await createForumSearchField(on: sqlDatabase)
      try await createForumSearchIndex(on: sqlDatabase)

      try await createForumPostSearchField(on: sqlDatabase)
      try await createForumPostSearchIndex(on: sqlDatabase)

      try await createEventSearchField(on: sqlDatabase)
      try await createEventSearchIndex(on: sqlDatabase)

      try await createBoardgameSearchField(on: sqlDatabase)
      try await createBoardgameSearchIndex(on: sqlDatabase)

      try await createKaraokeSongSearchField(on: sqlDatabase)
      try await createKaraokeSongSearchIndex(on: sqlDatabase)
    }

    func revert(on database: Database) async throws {
      let sqlDatabase = (database as! SQLDatabase)

      try await dropTwarrtSearchIndex(on: sqlDatabase)
      try await dropTwarrtSearchField(on: sqlDatabase)

      try await dropForumSearchIndex(on: sqlDatabase)
      try await dropForumSearchField(on: sqlDatabase)

      try await dropForumPostSearchIndex(on: sqlDatabase)
      try await dropForumPostSearchField(on: sqlDatabase)

      try await dropEventSearchIndex(on: sqlDatabase)
      try await dropEventSearchField(on: sqlDatabase)

      try await dropBoardgameSearchIndex(on: sqlDatabase)
      try await dropBoardgameSearchField(on: sqlDatabase)
      
      try await dropKaraokeSongSearchIndex(on: sqlDatabase)
      try await dropKaraokeSongSearchField(on: sqlDatabase)

      try await sqlDatabase.raw("DROP EXTENSION IF EXISTS pg_trgm").run()
    }

    func createTwarrtSearchField(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE twarrt
        ADD COLUMN IF NOT EXISTS searchable_index_col tsvector
          GENERATED ALWAYS AS (to_tsvector('english', text)) STORED;
      """).run()
    }

    func createTwarrtSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_twarrt_search
        ON twarrt
        USING GIN
        (searchable_index_col)
      """).run()
    }

    func dropTwarrtSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_twarrt_search")
        .run()
    }

    func dropTwarrtSearchField(on database: SQLDatabase) async throws {
      try await database
        .alter(table: "twarrt")
        .dropColumn("searchable_index_col")
        .run()
    }

    func createForumSearchField(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE forum
        ADD COLUMN IF NOT EXISTS searchable_index_col tsvector
          GENERATED ALWAYS AS (to_tsvector('english', title)) STORED;
      """).run()
    }

    func createForumSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_forum_search
        ON forum
        USING GIN
        (searchable_index_col)
      """).run()
    }

    func dropForumSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_forum_search")
        .run()
    }

    func dropForumSearchField(on database: SQLDatabase) async throws {
      try await database
        .alter(table: "forum")
        .dropColumn("searchable_index_col")
        .run()
    }

    func createForumPostSearchField(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE forumpost
        ADD COLUMN IF NOT EXISTS searchable_index_col tsvector
          GENERATED ALWAYS AS (to_tsvector('english', text)) STORED;
      """).run()
    }

    func createForumPostSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_forumpost_search
        ON forumpost
        USING GIN
        (searchable_index_col)
      """).run()
    }

    func dropForumPostSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_forumpost_search")
        .run()
    }

    func dropForumPostSearchField(on database: SQLDatabase) async throws {
      try await database
        .alter(table: "forumpost")
        .dropColumn("searchable_index_col")
        .run()
    }

    func createEventSearchField(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE event
        ADD COLUMN IF NOT EXISTS searchable_index_col tsvector
          GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '')) || ' ' || to_tsvector('english', coalesce(info, ''))) STORED;
      """).run()
    }

    func createEventSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_event_search
        ON event
        USING GIN
        (searchable_index_col)
      """).run()
    }

    func dropEventSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_event_search")
        .run()
    }

    func dropEventSearchField(on database: SQLDatabase) async throws {
      try await database
        .alter(table: "event")
        .dropColumn("searchable_index_col")
        .run()
    }

    func createBoardgameSearchField(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE boardgame
        ADD COLUMN IF NOT EXISTS searchable_index_col tsvector
          GENERATED ALWAYS AS (to_tsvector('english', "gameName")) STORED;
      """).run()
    }

    func createBoardgameSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_boardgame_search
        ON boardgame
        USING GIN
        (searchable_index_col)
      """).run()
    }

    func dropBoardgameSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_boardgame_search")
        .run()
    }

    func dropBoardgameSearchField(on database: SQLDatabase) async throws {
      try await database
        .alter(table: "boardgame")
        .dropColumn("searchable_index_col")
        .run()
    }

    func createKaraokeSongSearchField(on database: SQLDatabase) async throws {
      try await database.raw("""
        ALTER TABLE karaoke_song
        ADD COLUMN IF NOT EXISTS searchable_index_col tsvector
          GENERATED ALWAYS AS (to_tsvector('english', coalesce(artist, '')) || ' ' || to_tsvector('english', coalesce(title, ''))) STORED;
      """).run()
    }

    func createKaraokeSongSearchIndex(on database: SQLDatabase) async throws {
      try await database.raw("""
        CREATE INDEX IF NOT EXISTS idx_karaoke_song_search
        ON karaoke_song
        USING GIN
        (searchable_index_col)
      """).run()
    }

    func dropKaraokeSongSearchIndex(on database: SQLDatabase) async throws {
      try await database
        .drop(index: "idx_karaoke_song_search")
        .run()
    }

    func dropKaraokeSongSearchField(on database: SQLDatabase) async throws {
      try await database
        .alter(table: "karaoke_song")
        .dropColumn("searchable_index_col")
        .run()
    }
}

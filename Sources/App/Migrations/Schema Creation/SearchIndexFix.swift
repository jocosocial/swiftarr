import FluentSQL

struct FixSearchIndexes: AsyncMigration {
    func prepare(on database: Database) async throws {
      let sqlDatabase = (database as! SQLDatabase)

      try await sqlDatabase.drop(index: "idx_event_search").run()
      try await sqlDatabase.drop(index: "idx_karaoke_song_search").run()
      try await sqlDatabase.alter(table: "event").dropColumn("fulltext_search").run()
      try await sqlDatabase.alter(table: "karaoke_song").dropColumn("fulltext_search").run()
      
      try await sqlDatabase.raw("""
        ALTER TABLE event
        ADD COLUMN IF NOT EXISTS fulltext_search tsvector
          GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(info, ''))) STORED;
      """).run()

      try await sqlDatabase.raw("""
        ALTER TABLE karaoke_song
        ADD COLUMN IF NOT EXISTS fulltext_search tsvector
          GENERATED ALWAYS AS (to_tsvector('english', coalesce(artist, '') || ' ' || coalesce(title, ''))) STORED;
      """).run()
      
      try await sqlDatabase.raw("""
        CREATE INDEX IF NOT EXISTS idx_event_search
        ON event
        USING GIN
        (fulltext_search)
      """).run()

      try await sqlDatabase.raw("""
        CREATE INDEX IF NOT EXISTS idx_karaoke_song_search
        ON karaoke_song
        USING GIN
        (fulltext_search)
      """).run()
    }

    func revert(on database: Database) async throws {
      // Revert is intentionally a no-op, this is a patch for the previous migration.
    }
}

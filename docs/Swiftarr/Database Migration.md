Database Migration
==================

### Manual Migration via CLI
01. If you are populating a fresh database then you'll need to run a migration.
    to get some data.
    See the [Vapor docs](https://docs.vapor.codes/4.0/fluent/overview/#migrate) for details.
    ```
    swift run Run migrate [--yes]
    ```
    Example output:
    ```
    [0/0] Build complete!
    [ NOTICE ] Starting up in Development mode.
    ...
    The following migration(s) will be prepared:
    ...
    + App.SetInitialCategoryForumCounts on psql
    Would you like to continue?
    y/n>

    [ INFO ] Starting registration code import [database-id: psql]
    [ INFO ] Starting boardgame import [database-id: psql]
    ...
    [ INFO ] Imported 25000 karaoke songs. [database-id: psql]
    Migration successful
    ```

### Manual Migration via Docker
01. If you set `AUTO_MIGRATE` to `false` in your config and wish to perform a manual migration,
    you can do this by calling:
    ```
    scripts/stack.sh -e development run web /app/Run migrate --yes
    ```
02. Then you can restart the initial container that was created and died because
    there was no DB for it at the time.
    ```
    scripts/stack.sh -e development restart web
    ```

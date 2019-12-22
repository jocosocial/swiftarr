import FluentPostgreSQL
import Vapor
import Authentication
import Redis

/// Called before your application initializes.
public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {
    
    // run API on port 8081 by default and set a 10MB hard limit on file size
    let port = Int(Environment.get("PORT") ?? "8081")!
    services.register {
        container -> NIOServerConfig in
        .default(port: port, maxBodySize: 10_000_000)
    }
    
    // register providers first
    try services.register(FluentPostgreSQLProvider())
    try services.register(AuthenticationProvider())
    try services.register(RedisProvider())
    
    // register routes to the router
    let router = EngineRouter.default()
    try routes(router)
    services.register(router, as: Router.self)
    
    // register middleware
    var middlewares = MiddlewareConfig()
    //middlewares.use(FileMiddleware.self) // serves files from `Public/` directory
    middlewares.use(ErrorMiddleware.self) // catches errors and converts to HTTP response
    services.register(middlewares)
    
    // use iso8601ms for dates
    var contentConfig = ContentConfig.default()
    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()
    if #available(OSX 10.13, *) {
        jsonEncoder.dateEncodingStrategy = .iso8601ms
        jsonDecoder.dateDecodingStrategy = .iso8601ms
    } else {
        // Fallback on earlier versions
    }
    contentConfig.use(encoder: jsonEncoder, for: .json)
    contentConfig.use(decoder: jsonDecoder, for: .json)
    services.register(contentConfig)
    
    // configure PostgreSQL connection
    // note: environment variable nomenclature is vapor.cloud compatible
    let postgresConfig: PostgreSQLDatabaseConfig
    // support for Heroku environment
    if let postgresURL = Environment.get("DATABASE_URL") {
        postgresConfig = PostgreSQLDatabaseConfig(url: postgresURL)!
    } else {
        // otherwise
        let postgresHostname = Environment.get("DATABASE_HOSTNAME") ?? "localhost"
        let postgresUser = Environment.get("DATABASE_USER") ?? "swiftarr"
        let postgresPassword = Environment.get("DATABASE_PASSWORD") ?? "password"
        let postgresDB: String
        let postgresPort: Int
        if (env == .testing) {
            postgresDB = "swiftarr-test"
            postgresPort = Int(Environment.get("DATABASE_PORT") ?? "5433")!
        } else {
            postgresDB = Environment.get("DATABASE_DB") ?? "swiftarr"
            postgresPort = 5432
        }
        postgresConfig = PostgreSQLDatabaseConfig(
            hostname: postgresHostname,
            port: postgresPort,
            username: postgresUser,
            database: postgresDB,
            password: postgresPassword,
            transport: .cleartext
        )
    }
    let postgres = PostgreSQLDatabase(config: postgresConfig)
    
    // configure Redis connection
    var redisConfig = RedisClientConfig()
    // support for Heroku environment
    if let redisString = Environment.get("REDIS_URL"),
        let redisURL = URL(string: redisString) {
        redisConfig = RedisClientConfig(url: redisURL)
    } else {
        // otherwise
        let redisHostname: String
        let redisPort: Int
        if (env == .testing) {
            redisHostname = Environment.get("REDIS_HOSTNAME") ?? "localhost"
            redisPort = Int(Environment.get("REDIS_PORT") ?? "6380")!
        } else {
            redisHostname = Environment.get("REDIS_HOSTNAME") ?? "localhost"
            redisPort = 6379
        }
        redisConfig.hostname = redisHostname
        redisConfig.port = redisPort
    }
    let redis = try RedisDatabase(config: redisConfig)
    
    // register databases
    var databases = DatabasesConfig()
    databases.add(database: postgres, as: .psql)
    databases.add(database: redis, as: .redis)
    services.register(databases)
    
    // use Redis for KeyedCache
    services.register(KeyedCache.self) {
        container in
        try container.keyedCache(for: .redis)
    }
    
    // configure migrations
    var migrations = MigrationConfig()
    migrations.add(model: User.self, database: .psql)
    migrations.add(model: UserProfile.self, database: .psql)
    migrations.add(model: Token.self, database: .psql)
    migrations.add(model: RegistrationCode.self, database: .psql)
    migrations.add(model: ProfileEdit.self, database: .psql)
    migrations.add(model: UserNote.self, database: .psql)
    migrations.add(model: Barrel.self, database: .psql)
    migrations.add(model: Report.self, database: .psql)
    migrations.add(model: Event.self, database: .psql)
    migrations.add(model: Category.self, database: .psql)
    migrations.add(model: Forum.self, database: .psql)
    migrations.add(model: ForumPost.self, database: .psql)
    migrations.add(model: ForumEdit.self, database: .psql)
    migrations.add(model: PostLikes.self, database: .psql)
    migrations.add(model: Twarrt.self, database: .psql)
    migrations.add(model: TwarrtEdit.self, database: .psql)
    migrations.add(model: TwarrtLikes.self, database: .psql)
    migrations.add(model: FezPost.self, database: .psql)
    migrations.add(migration: AdminUser.self, database: .psql)
    migrations.add(migration: ClientUsers.self, database: .psql)
    migrations.add(migration: RegistrationCodes.self, database: .psql)
    migrations.add(migration: Events.self, database: .psql)
    migrations.add(migration: Categories.self, database: .psql)
    migrations.add(migration: Forums.self, database: .psql)
    migrations.add(migration: EventForums.self, database: .psql)
    if (env == .testing || env == .development) {
        migrations.add(migration: TestUsers.self, database: .psql)
    }
    services.register(migrations)
    
    // add Fluent commands for CLI migration and revert
    var commandConfig = CommandConfig.default()
    commandConfig.useFluentCommands()
    services.register(commandConfig)
}

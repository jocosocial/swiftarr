import Vapor
import Redis
import Fluent
import FluentPostgresDriver

/// Called before your application initializes.
public func configure(_ app: Application) throws {
    
	// Add lifecycle handler.
	app.lifecycle.use(Application.UserCacheStartup())

    // run API on port 8081 by default and set a 10MB hard limit on file size
    let port = Int(Environment.get("PORT") ?? "8081")!
	app.http.server.configuration.port = port
	app.routes.defaultMaxBodySize = "10mb"
        
    // register routes to the router
//    let router = EngineRouter.default()
    try routes(app)
//    services.register(router, as: Router.self)
    
    // register middleware
//    app.middleware.use(FileMiddleware(publicDirectory: "Public/")) // serves files from `Public/` directory
//	app.middleware.use(SwiftarrErrorMiddleware.default(environment: app.environment))
	var new = Middlewares()
	new.use(RouteLoggingMiddleware(logLevel: .info))
	new.use(SwiftarrErrorMiddleware.default(environment: app.environment))
	app.middleware = new
    
    // use iso8601ms for dates
    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()
    if #available(OSX 10.13, *) {
        jsonEncoder.dateEncodingStrategy = .iso8601ms
        jsonDecoder.dateDecodingStrategy = .iso8601ms
    } else {
        // Fallback on earlier versions
    }
	ContentConfiguration.global.use(encoder: jsonEncoder, for: .json)
    ContentConfiguration.global.use(decoder: jsonDecoder, for: .json)
    
    // configure PostgreSQL connection
    // note: environment variable nomenclature is vapor.cloud compatible
    // support for Heroku environment
    if let postgresURL = Environment.get("DATABASE_URL") {
		try app.databases.use(.postgres(url: postgresURL), as: .psql)
    } else 
    {
        // otherwise
        let postgresHostname = Environment.get("DATABASE_HOSTNAME") ?? "localhost"
        let postgresUser = Environment.get("DATABASE_USER") ?? "swiftarr"
        let postgresPassword = Environment.get("DATABASE_PASSWORD") ?? "password"
        let postgresDB: String
        let postgresPort: Int
        if (app.environment == .testing) {
            postgresDB = "swiftarr-test"
            postgresPort = Int(Environment.get("DATABASE_PORT") ?? "5433")!
        } else {
            postgresDB = Environment.get("DATABASE_DB") ?? "swiftarr"
            postgresPort = 5432
        }
		app.databases.use(.postgres(hostname: postgresHostname, port: postgresPort, username: postgresUser, 
				password: postgresPassword, database: postgresDB), as: .psql)
    }
//    let postgres = PostgreSQLDatabase(config: postgresConfig)
    
    // configure Redis connection
    // support for Heroku environment
    if let redisString = Environment.get("REDIS_URL"), let redisURL = URL(string: redisString) {
		app.redis.configuration = try RedisConfiguration(url: redisURL)
    } else 
    {
        // otherwise
        let redisHostname = Environment.get("REDIS_HOSTNAME") ?? "localhost"
        let redisPort = (app.environment == .testing) ? Int(Environment.get("REDIS_PORT") ?? "6380")! : 6379
		app.redis.configuration = try RedisConfiguration(hostname: redisHostname, port: redisPort)
    }
    
//    // register databases
//    var databases = DatabasesConfig()
//    databases.add(database: postgres, as: .psql)
//    databases.add(database: redis, as: .redis)
//    app.services.register(databases)
//    
//    // use Redis for KeyedCache
//    app.services.register(KeyedCache.self) {
//        container in
//        try container.keyedCache(for: .redis)
//    }
    
    // configure migrations. Schema-creation migrations first. These create an initial database schema
    // and do not add any data to the db. These need to be ordered such that referred-to tables
    // come before referrers.
	app.migrations.add(CreateUserSchema(), to: .psql)
	app.migrations.add(CreateTokenSchema(), to: .psql)
	app.migrations.add(CreateRegistrationCodeSchema(), to: .psql)
	app.migrations.add(CreateProfileEditSchema(), to: .psql)
	app.migrations.add(CreateUserNoteSchema(), to: .psql)
	app.migrations.add(CreateBarrelSchema(), to: .psql)
	app.migrations.add(CreateReportSchema(), to: .psql)
	app.migrations.add(CreateCategorySchema(), to: .psql)
	app.migrations.add(CreateForumSchema(), to: .psql)
	app.migrations.add(CreateForumPostSchema(), to: .psql)
	app.migrations.add(CreateForumEditSchema(), to: .psql)
	app.migrations.add(CreatePostLikesSchema(), to: .psql)
	app.migrations.add(CreateEventSchema(), to: .psql)
	app.migrations.add(CreateTwarrtSchema(), to: .psql)
	app.migrations.add(CreateTwarrtEditSchema(), to: .psql)
	app.migrations.add(CreateTwarrtLikesSchema(), to: .psql)
	app.migrations.add(CreateFezPostSchema(), to: .psql)
	
	// Second, migrations that seed the db with initial data
    app.migrations.add(CreateAdminUser(), to: .psql)
    app.migrations.add(CreateClientUsers(), to: .psql)
    app.migrations.add(CreateRegistrationCodes(), to: .psql)
    app.migrations.add(CreateEvents(), to: .psql)
    app.migrations.add(CreateCategories(), to: .psql)
    app.migrations.add(CreateForums(), to: .psql)
    app.migrations.add(CreateEventForums(), to: .psql)
    if (app.environment == .testing || app.environment == .development) {
        app.migrations.add(CreateTestUsers(), to: .psql)
    }
    
    app.migrations.add(CreateTestData(), to: .psql)
    
    // add Fluent commands for CLI migration and revert
//    var commandConfig = CommandConfig.default()
//    commandConfig.useFluentCommands()
//    services.register(commandConfig)
}

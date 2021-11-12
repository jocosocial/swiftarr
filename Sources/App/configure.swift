import Vapor
import Redis
import Fluent
import FluentPostgresDriver
import Leaf
import Metrics
import Prometheus
import gd

/// # Launching Swiftarr
/// 
/// ### Environment
/// 
/// Besides the standard .development, .production, and .testing, there's a few custom environment values that can be set, either on the command line
/// with `--env <ENVIRONMENT>` or with the `VAPOR_ENV` environment variable
/// * --env heroku: Use this for Heroku installs. This changes the Migrations for games and karaoke to load fewer items and use fewer table rows. It also
/// 	may change the way images are stored. Otherwise like .production.
/// 
/// Environment variables used by Swiftarr:
/// * DATABASE_URL: 
/// * DATABASE_HOSTNAME:
/// * DATABASE_PORT:
/// * DATABASE_DB:
/// * DATABASE_PASSWORD:
/// 
/// * REDIS_URL:
/// * REDIS_HOSTNAME: 
/// 
/// * PORT:
/// * hostname:
/// 
/// * ADMIN_PASSWORD:
/// * RECOVERY_KEY:
/// 
///
/// Called before your application initializes. Calls several other config methods to do its work. Sub functions are only
/// here for easier organization. If order-of-initialization issues arise, rearrange as necessary.
public func configure(_ app: Application) throws {
    
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

	// Remember: Settings are not available during configuration.
	try databaseConnectionConfiguration(app)
	try HTTPServerConfiguration(app)
	try configureMiddleware(app)
	try configureSessions(app)
	try configureLeaf(app)
	try configurePrometheus(app)
    try routes(app)
	try configureMigrations(app)
	
	// Add lifecycle handlers 
	app.lifecycle.use(Application.UserCacheStartup())
	
	// Settings loads values from Redis during startup, and Redis isn't available until app.boot() completes.
	// Posts on RedisKit's github bug db say the solution is to call boot() early. 
	try app.boot()
	try configureSettings(app)
}

func databaseConnectionConfiguration(_ app: Application) throws {
	// configure PostgreSQL connection
    // note: environment variable nomenclature is vapor.cloud compatible
    // support for Heroku environment
	if let databaseURL = Environment.get("DATABASE_URL"), var postgresConfig = PostgresConfiguration(url: databaseURL) {
		postgresConfig.tlsConfiguration = .makeClientConfiguration()
		postgresConfig.tlsConfiguration?.certificateVerification = .none
		app.databases.use(.postgres(configuration: postgresConfig), as: .psql)
    } else 
    {
        // otherwise
        let postgresHostname = Environment.get("DATABASE_HOSTNAME") ?? "localhost"
        let postgresUser = Environment.get("DATABASE_USER") ?? "swiftarr"
        let postgresPassword = Environment.get("DATABASE_PASSWORD") ?? "password"
        let postgresDB: String
        let postgresPort: Int
        if app.environment == .testing {
            postgresDB = "swiftarr-test"
            postgresPort = Int(Environment.get("DATABASE_PORT") ?? "5433")!
        } else {
            postgresDB = Environment.get("DATABASE_DB") ?? "swiftarr"
            postgresPort = 5432
        }
		app.databases.use(.postgres(hostname: postgresHostname, port: postgresPort, username: postgresUser, 
				password: postgresPassword, database: postgresDB), as: .psql)
    }
    
    // configure Redis connection
    // support for Heroku environment. Heroku also provides "REDIS_TLS_URL", but Vapor's Redis package 
    // may not yet support TLS database connections.
	if let redisString = Environment.get("REDIS_URL"), let redisURL = URL(string: redisString) {
		app.redis.configuration = try RedisConfiguration(url: redisURL)
    } else 
    {
        // otherwise
        let redisHostname = Environment.get("REDIS_HOSTNAME") ?? "localhost"
        let redisPort = (app.environment == .testing) ? Int(Environment.get("REDIS_PORT") ?? "6380")! : 6379
		app.redis.configuration = try RedisConfiguration(hostname: redisHostname, port: redisPort)
    }

}

func configureSettings(_ app: Application) throws {
	try Settings.shared.readStoredSettings(app: app)

	// Set the cruise start date to a date that works with the Schedule.ics file that we have. Until we have
	// a 2022 schedule, we're using the 2020 schedule. Development builds by default will date-shift the current date
	// into a day of the cruise week (the time the schedule covers) for Events methods, because 'No Events Today' 
	// makes testing schedule features difficult.
	if app.environment == .testing {
		Logger(label: "app.swiftarr.configuration") .info("Starting up in Testing mode.")
		// Until we get a proper 2022 schedule, we're using the 2020 schedule for testing. 
		Settings.shared.cruiseStartDate = Calendar.autoupdatingCurrent.date(from: DateComponents(calendar: Calendar.current, 
			timeZone: TimeZone(abbreviation: "EST")!, year: 2020, month: 3, day: 7))!
	}
	else if app.environment == .development {
		Logger(label: "app.swiftarr.configuration") .info("Starting up in Development mode.")
		// Until we get a proper 2022 schedule, we're using the 2020 schedule for testing. 
		Settings.shared.cruiseStartDate = Calendar.autoupdatingCurrent.date(from: DateComponents(calendar: Calendar.current, 
			timeZone: TimeZone(abbreviation: "EST")!, year: 2020, month: 3, day: 7))!
	}
	else if app.environment == .production {
		Logger(label: "app.swiftarr.configuration") .info("Starting up in Production mode.")
		Settings.shared.cruiseStartDate = Calendar.autoupdatingCurrent.date(from: DateComponents(calendar: Calendar.current, 
			timeZone: TimeZone(abbreviation: "EST")!, year: 2022, month: 3, day: 5))!
	}
	else {
		Logger(label: "app.swiftarr.configuration") .info("Starting up in Custom \"\(app.environment.name)\" mode.")
		Settings.shared.cruiseStartDate = Calendar.autoupdatingCurrent.date(from: DateComponents(calendar: Calendar.current, 
			timeZone: TimeZone(abbreviation: "EST")!, year: 2022, month: 3, day: 5))!
	}
	
	// Ask the GD Image library what filetypes are available on the local machine.
	// gd, gd2, xbm, xpm, wbmp, some other useless formats culled.
	let fileTypes = [".gif", ".bmp", ".tga", ".png", ".jpg", ".heif", ".heix", ".avif", ".tif", ".webp"]
	let supportedInputTypes = fileTypes.filter { gdSupportsFileType($0, 0) != 0 }
	let supportedOutputTypes = fileTypes.filter { gdSupportsFileType($0, 1) != 0 }
	Settings.shared.validImageInputTypes = supportedInputTypes
	Settings.shared.validImageOutputTypes = supportedOutputTypes
	
	// On my machine: heif, heix, avif not supported
	// [".gif", ".bmp", ".tga", ".png", ".jpg", ".tif", ".webp"] inputs
	// [".gif", ".bmp",         ".png", ".jpg", ".tif", ".webp"] outputs
}

func HTTPServerConfiguration(_ app: Application) throws {
	// run API on port 8081 by default and set a 10MB hard limit on file size
    let port = Int(Environment.get("PORT") ?? "8081")!
	app.http.server.configuration.port = port
	app.routes.defaultMaxBodySize = "10mb"
	
	// Enable HTTP response compression.
	// app.http.server.configuration.responseCompression = .enabled
	
	if let host = Environment.get("hostname") {
		app.http.server.configuration.hostname = host
	}
	else if app.environment == .development {
		app.http.server.configuration.hostname = "192.168.0.19"
	}
	else if app.environment == .production {
		app.http.server.configuration.hostname = "joco.hollandamerica.com"
	}
	else if app.environment.name == "heroku" {
		app.http.server.configuration.hostname = "swiftarr.herokuapp.com"
	}
}

// register global middleware
func configureMiddleware(_ app: Application) throws {
	// By default, Vapor launches with 2 middlewares: RouteLoggingMiddleware and ErrorMiddleware.
	// We want to replace the standard Error middleware with SwiftarrErrorMiddleware, and we do that by
	// creating a new Middlewares().
	var new = Middlewares()
	new.use(SwiftarrErrorMiddleware(environment: app.environment))
	new.use(SiteErrorMiddleware(environment: app.environment))
	app.middleware = new
}

func configureSessions(_ app: Application) throws {
	app.sessions.configuration.cookieName = "swiftarr_session"
	
	// Configures cookie value creation.
	app.sessions.configuration.cookieFactory = { sessionID in
		.init(string: sessionID.string,
				expires: Date( timeIntervalSinceNow: 60 * 60 * 24 * 7),
				maxAge: nil,
				domain: nil,
				path: "/",
				isSecure: false,
				isHTTPOnly: true,
				sameSite: .lax
		)
	}
	
	// Use Redis to store sessions
	app.sessions.use(.redis)
}

func configureLeaf(_ app: Application) throws {
    app.views.use(.leaf)
    
    // Custom Leaf tags
    app.leaf.tags["addJocomoji"] = AddJocomojiTag()
    app.leaf.tags["formatTwarrtText"] = FormatPostTextTag(.twarrt)
    app.leaf.tags["formatPostText"] = FormatPostTextTag(.forumpost)
    app.leaf.tags["formatFezText"] = FormatPostTextTag(.fez)
    app.leaf.tags["formatSeamailText"] = FormatPostTextTag(.seamail)
    app.leaf.tags["relativeTime"] = RelativeTimeTag()
    app.leaf.tags["eventTime"] = EventTimeTag()
    app.leaf.tags["avatar"] = AvatarTag()
    app.leaf.tags["userByline"] = UserBylineTag()
    app.leaf.tags["cruiseDayIndex"] = CruiseDayIndexTag()
    app.leaf.tags["gameRating"] = GameRatingTag()
}

func configurePrometheus(_ app: Application) throws {
	let myProm = PrometheusClient()
	MetricsSystem.bootstrap(PrometheusMetricsFactory(client: myProm))
}
	
func configureMigrations(_ app: Application) throws {

	// Migration order is important here, particularly for initializing a new database.
	// First initialize custom enum types. These are custom 'types' for fields (like .string, .int, or .uuid) -- but custom.
	app.migrations.add(CreateCustomEnums(), to: .psql) 
	
	// Second group is schema-creation migrations. These create an initial database schema
	// and do not add any data to the db. These need to be ordered such that referred-to tables
	// come before referrers.
	app.migrations.add(CreateUserSchema(), to: .psql)
	app.migrations.add(CreateTokenSchema(), to: .psql)
	app.migrations.add(CreateRegistrationCodeSchema(), to: .psql)
	app.migrations.add(CreateProfileEditSchema(), to: .psql)
	app.migrations.add(CreateUserNoteSchema(), to: .psql)
	app.migrations.add(CreateModeratorActionSchema(), to: .psql)
	app.migrations.add(CreateAnnouncementSchema(), to: .psql)
	app.migrations.add(CreateBarrelSchema(), to: .psql)
	app.migrations.add(CreateReportSchema(), to: .psql)
	app.migrations.add(CreateCategorySchema(), to: .psql)
	app.migrations.add(CreateForumSchema(), to: .psql)
	app.migrations.add(CreateForumEditSchema(), to: .psql)
	app.migrations.add(CreateForumPostSchema(), to: .psql)
	app.migrations.add(CreateForumPostEditSchema(), to: .psql)
	app.migrations.add(CreateForumReadersSchema(), to: .psql)
	app.migrations.add(CreatePostLikesSchema(), to: .psql)
	app.migrations.add(CreateEventSchema(), to: .psql)
	app.migrations.add(CreateTwarrtSchema(), to: .psql)
	app.migrations.add(CreateTwarrtEditSchema(), to: .psql)
	app.migrations.add(CreateTwarrtLikesSchema(), to: .psql)
	app.migrations.add(CreateFriendlyFezSchema(), to: .psql)
	app.migrations.add(CreateFezParticipantSchema(), to: .psql)
	app.migrations.add(CreateFezPostSchema(), to: .psql)
	app.migrations.add(CreateFriendlyFezEditSchema(), to: .psql)
	app.migrations.add(CreateDailyThemeSchema(), to: .psql)
	app.migrations.add(CreateBoardgameSchema(), to: .psql)
	app.migrations.add(CreateBoardgameFavoriteSchema(), to: .psql)
	app.migrations.add(CreateKaraokeSongSchema(), to: .psql)
	app.migrations.add(CreateKaraokePlayedSongSchema(), to: .psql)
	app.migrations.add(CreateKaraokeFavoriteSchema(), to: .psql)

	// Third, migrations that seed the db with initial data
	app.migrations.add(CreateAdminUser(), to: .psql)
	app.migrations.add(CreateClientUsers(), to: .psql)
	app.migrations.add(CreateCategories(), to: .psql)
//	app.migrations.add(CreateForums(), to: .psql)		// Adds some initial forum threads; not the event forum threads.
	if app.environment == .testing || app.environment == .development {
		app.migrations.add(CreateTestUsers(), to: .psql)
		app.migrations.add(CreateTestData(), to: .psql)
	}
	
	// Fourth, migrations that import data from /seeds
	app.migrations.add(ImportRegistrationCodes(), to: .psql)
	app.migrations.add(ImportEvents(), to: .psql)
	app.migrations.add(ImportBoardgames(), to: .psql)	
	app.migrations.add(ImportKaraokeSongs(), to: .psql)	
	
	// Fifth, migrations that touch up initial state
	app.migrations.add(SetInitialEventForums(), to: .psql)
	app.migrations.add(SetInitialCategoryForumCounts(), to: .psql)
}
  

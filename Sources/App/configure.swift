import Vapor
import Redis
import Fluent
import FluentPostgresDriver
import Leaf
import LeafKit
import Metrics
import Prometheus
import gd

/// # Launching Swiftarr
/// 
/// ### Environment
/// 
/// Besides the standard .development, .production, and .testing, there's a few custom environment values that can be set, either on the command line
/// with `--env <ENVIRONMENT>` or with the `VAPOR_ENV` environment variable
/// 
/// Environment variables used by Swiftarr:
/// * DATABASE_URL: 
/// * DATABASE_HOSTNAME:
/// * DATABASE_PORT:
/// * DATABASE_DB:
/// * DATABASE_USER:
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
/// * SWIFTARR_USER_IMAGES:  Root directory for storing user-uploaded images. These images are referenced by filename in the db.
///
/// Called before your application initializes. Calls several other config methods to do its work. Sub functions are only
/// here for easier organization. If order-of-initialization issues arise, rearrange as necessary.
public func configure(_ app: Application) throws {

	// use iso8601ms for dates
	let jsonEncoder = JSONEncoder()
	let jsonDecoder = JSONDecoder()
	jsonEncoder.dateEncodingStrategy = .iso8601ms
	jsonDecoder.dateDecodingStrategy = .iso8601ms
	ContentConfiguration.global.use(encoder: jsonEncoder, for: .json)
	ContentConfiguration.global.use(decoder: jsonDecoder, for: .json)
	
	// Set up all the settings that we don't need Redis to acquire. 
	try configureBundle(app)
	try configureBasicSettings(app)

	// Remember: Stored Settings are not available during configuration--only 'basic' settings.
	try databaseConnectionConfiguration(app)
	try configureHTTPServer(app)
	try configureMiddleware(app)
	try configureSessions(app)
	try configureLeaf(app)
	try configurePrometheus(app)
	try routes(app)
	try configureMigrations(app)
		
	// Settings loads values from Redis during startup, and Redis isn't available until app.boot() completes.
	// Posts on RedisKit's github bug db say the solution is to call boot() early. 
	try app.boot()
	
	try configureAPIURL(app)

	// Check that we can access everything.
	try verifyConfiguration(app)
	
	// Now load the settings that we need Redis access to acquire.
	try configureStoredSettings(app)

	// UserCache had previously done startup initialization with a lifecycle handler. However, Redis isn't ready 
	// for use until its 'didBoot' lifecycle handler has run, and I don't like opaque ordering dependencies.
	// As a lifecycle handler, our 'didBoot' callback got put in a list with Redis's, and we had to hope Vapor called them first.
	try app.initializeUserCache(app)

	// Add custom commands
	configureCommands(app)
}

// So, the way to get files copied into a built app with SPM is to declare them as Resources of some sort and 
// the SPM build process will copy them into the app's directory tree in a Bundle. Xcode will also copy them
// into the app's directory tree as a Bundle, except it'll be in a different place with a different name and
// the bundle will have a different internal structure. Oh, and if you build with "vapor run" on the command line,
// the bundle with all the resources files in it will be in yet another different place. I *think* this code
// will handle all the cases, finding the bundle dir correctly. We also check that we can find our resource files
// on launch.
func configureBundle(_ app: Application) throws {
	var resourcesURL: URL
	if operatingSystemPlatform() == "Linux" {
		resourcesURL = Bundle.main.bundleURL.appendingPathComponent("swiftarr_App.resources")
	}
	else if let xcodeLinkedLocation = Bundle.main.resourceURL?.appendingPathComponent("swiftarr_App.bundle"), 
			let bundle = Bundle.init(url: xcodeLinkedLocation), let loc = bundle.resourceURL,
			FileManager.default.fileExists(atPath: loc.appendingPathComponent("seeds").path) {
		// Xcode build toolchain uses this case
		resourcesURL = loc
	}
	else if let cliLinkedLocation = Bundle.main.resourceURL?.appendingPathComponent("swiftarr_App.bundle"), 
			let bundle = Bundle.init(url: cliLinkedLocation),
			FileManager.default.fileExists(atPath: bundle.bundleURL.appendingPathComponent("seeds").path) {
		// Command line toolchain (`swift build`) uses this case
		resourcesURL = bundle.bundleURL
	}
	else if let fwLinkedLocation = Bundle(for: Settings.self).resourceURL?.appendingPathComponent("swiftarr_App.bundle"), 
			let bundle = Bundle.init(url: fwLinkedLocation), let loc = bundle.resourceURL {
		resourcesURL = loc
	}
	else if let bundle = Bundle.init(url: Bundle.main.bundleURL.appendingPathComponent("swiftarr_App.bundle")), let loc = bundle.resourceURL {
		resourcesURL = loc
	}
	else if Bundle(for: Settings.self).url(forResource: "swiftarr", withExtension: "css", subdirectory: "Resources/Assets/css") != nil {
		resourcesURL = Bundle(for: Settings.self).resourceURL ?? Bundle(for: Settings.self).bundleURL
	}
	else {
		resourcesURL = Bundle.main.bundleURL.appendingPathComponent("swiftarr_App.bundle")
		if let swiftarrBundle = Bundle(url: resourcesURL), let swiftarrResourceURL = swiftarrBundle.resourceURL {
			resourcesURL = swiftarrResourceURL
		}
	}
	Settings.shared.staticFilesRootPath = resourcesURL
	Logger(label: "app.swiftarr.configuration") .notice("Set static files path to \(Settings.shared.staticFilesRootPath.path).")

	// Load the variables in the .env file into our environment. This calls `setenv` on each key-value pair in the file.
	// Vapor is setup to load these files automatically,
	//
	// I don't really know if this works on MacOS or not given the weirdness around bundling between MacOS and Linux.
	// This might also be different between Xcode and not-Xcode.
	// https://developer.apple.com/documentation/foundation/bundle
	// https://stackoverflow.com/questions/51955184/get-nil-when-looking-for-file-in-subdirectory-of-main-bundle
	let configDirectory = Settings.shared.seedsDirectoryPath.appendingPathComponent("Private Swiftarr Config")	
	let envFilePath = configDirectory.appendingPathComponent("\(app.environment.name).env")
	if FileManager.default.fileExists(atPath: envFilePath.path) {
		Logger(label: "app.swiftarr.configuration").notice("Loading environment configuration from \(envFilePath.path)")
		DotEnvFile.load(path: envFilePath.path, on: .shared(app.eventLoopGroup), fileio: app.fileio, logger: app.logger)
	} else {
		Logger(label: "app.swiftarr.configuration")
				.warning("No config file detected for environment '\(app.environment.name)'. Defaulting to shell environment and code defaults.")
	}
}

// Sets up the cruise start date, image file types supported on the local machine, and determines a few local file paths.
// Note that other configuration methods rely on values set by this method.
func configureBasicSettings(_ app: Application) throws {

	// Set the cruise start date to a date that works with the Schedule.ics file that we have. Until we have
	// a 2022 schedule, we're using the 2020 schedule. Development builds by default will date-shift the current date
	// into a day of the cruise week (the time the schedule covers) for Events methods, because 'No Events Today' 
	// makes testing schedule features difficult.

	// We do not have the displayCalendar yet so we have to build our own. Since the departure port/timezone is
	// well-known we can safely rely on it here. Perhaps someday make it an environment variable or some other
	// method of configuration for app startup?
	var portCalendar = Calendar(identifier: .gregorian)
	let portTimeZone = TimeZone(identifier: "America/New_York")!
	portCalendar.timeZone = portTimeZone
	Settings.shared.portTimeZone = portTimeZone

	if app.environment == .testing {
		Logger(label: "app.swiftarr.configuration") .notice("Starting up in Testing mode.")
		Settings.shared.cruiseStartDateComponents = DateComponents(year: 2022, month: 3, day: 5)
	}
	else if app.environment == .development {
		Logger(label: "app.swiftarr.configuration") .notice("Starting up in Development mode.")
		Settings.shared.cruiseStartDateComponents = DateComponents(year: 2022, month: 3, day: 5)
	}
	else if app.environment == .production {
		Logger(label: "app.swiftarr.configuration") .notice("Starting up in Production mode.")
		// Until we get a proper future schedule, we're using the current schedule for testing. 
		Settings.shared.cruiseStartDateComponents = DateComponents(year: 2023, month: 3, day: 5)
	}
	else {
		Logger(label: "app.swiftarr.configuration") .notice("Starting up in Custom \"\(app.environment.name)\" mode.")
		Settings.shared.cruiseStartDateComponents = DateComponents(year: 2023, month: 3, day: 5)
	}
	
	// Ask the GD Image library what filetypes are available on the local machine.
	// gd, gd2, xbm, xpm, wbmp, some other useless formats culled.
	let fileTypes = [".gif", ".bmp", ".tga", ".png", ".jpg", ".heif", ".heix", ".avif", ".tif", ".webp"]
	var supportedInputTypes = fileTypes.filter { gdSupportsFileType($0, 0) != 0 }
	var supportedOutputTypes = fileTypes.filter { gdSupportsFileType($0, 1) != 0 }
	if supportedInputTypes.contains(".jpg") {
		supportedInputTypes.append(".jpeg")
	}
	if supportedOutputTypes.contains(".jpg") {
		supportedOutputTypes.append(".jpeg")
	}
	Settings.shared.validImageInputTypes = supportedInputTypes
	Settings.shared.validImageOutputTypes = supportedOutputTypes
	
	// On my machine: heif, heix, avif not supported
	// [".gif", ".bmp", ".tga", ".png", ".jpg", ".tif", ".webp"] inputs
	// [".gif", ".bmp",		 ".png", ".jpg", ".tif", ".webp"] outputs
	
	// Set the app's views dir, which is where all the Leaf template files are.
	app.directory.viewsDirectory = Settings.shared.staticFilesRootPath.appendingPathComponent("Resources/Views").path
	// Also set the resources dir, although I don't think it's used anywhere.
	app.directory.resourcesDirectory = Settings.shared.staticFilesRootPath.appendingPathComponent("Resources").path
	
	// This sets the root dir for the "User Images" tree, which is where user uploaded images are stored.
	// The postgres DB holds filenames that refer to files in this directory tree; ideally the lifetime of the 
	// contents of this directory should be tied to the lifetime of the DB (that is, clear out this dir on DB reset).
	if let userImagesOverridePath = Environment.get("SWIFTARR_USER_IMAGES") {
		Settings.shared.userImagesRootPath = URL(fileURLWithPath: userImagesOverridePath)
	}
	else {
		// Figure out the likely path to the 'swiftarr' executable.
		var likelyExecutablePath: String
		let appPath = app.environment.arguments[0]
		if appPath.isEmpty || !appPath.hasPrefix("/") {
			likelyExecutablePath = DirectoryConfiguration.detect().workingDirectory
		}
		else {
			likelyExecutablePath = URL(fileURLWithPath: appPath).deletingLastPathComponent().path
		}
		
		Settings.shared.userImagesRootPath = URL(fileURLWithPath: likelyExecutablePath).appendingPathComponent("images")
	}
	Logger(label: "app.swiftarr.configuration") .notice("Set userImages path to \(Settings.shared.userImagesRootPath.path).")

	// Always capture stack traces, regardless of log level. Default is false.
	// https://docs.vapor.codes/basics/errors/
	StackTrace.isCaptureEnabled = false
}

func databaseConnectionConfiguration(_ app: Application) throws {
	// configure PostgreSQL connection
	// note: environment variable nomenclature is vapor.cloud compatible

	// Specify a database connection timeout in case we find ourselves stuck on a slow laptop.
	let databaseTimeoutSeconds = Int64(Environment.get("DATABASE_TIMEOUT") ?? "10")

	if let databaseURL = Environment.get("DATABASE_URL"), var postgresConfig = PostgresConfiguration(url: databaseURL) {
		postgresConfig.tlsConfiguration = .makeClientConfiguration()
		postgresConfig.tlsConfiguration?.certificateVerification = .none
		app.databases.use(.postgres(configuration: postgresConfig, maxConnectionsPerEventLoop: 1, connectionPoolTimeout: .seconds(databaseTimeoutSeconds!)), as: .psql)
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
				password: postgresPassword, database: postgresDB, maxConnectionsPerEventLoop: 1, connectionPoolTimeout: .seconds(databaseTimeoutSeconds!)), as: .psql)
	}
	
	// Configure Redis connection
	// Vapor's Redis package may not yet support TLS database connections so we support going both ways.
	let redisPoolOptions: RedisConfiguration.PoolOptions = RedisConfiguration.PoolOptions(maximumConnectionCount: .maximumActiveConnections(2))

	if let redisString = Environment.get("REDIS_URL"), let redisURL = URL(string: redisString) {
		app.redis.configuration = try RedisConfiguration(url: redisURL, pool: redisPoolOptions)
	} else {
		let redisHostname = Environment.get("REDIS_HOSTNAME") ?? "localhost"
		let redisPort = (app.environment == .testing) ? Int(Environment.get("REDIS_PORT") ?? "6380")! : 6379
		var redisPassword: String? = Environment.get("REDIS_PASSWORD") ?? "password"
		if redisPassword == "" {
			redisPassword = nil
		}
		app.redis.configuration = try RedisConfiguration(hostname: redisHostname, port: redisPort, password: redisPassword, pool: redisPoolOptions)
	}
}

// Loads stored setting values from Redis. Must be called after app.boot, because Redis isn't ready until then.
func configureStoredSettings(_ app: Application) throws {
	let promise = app.eventLoopGroup.next().makePromise(of: Void.self)
	promise.completeWithTask {
		try await Settings.shared.readStoredSettings(app: app)
	}
	let _ : EventLoopFuture<Void> = promise.futureResult
}

func configureHTTPServer(_ app: Application) throws {
	// run Web UI on port 8081 by default and set a 10MB hard limit on file size
    let port = Int(Environment.get("SWIFTARR_PORT") ?? "8081")!
	app.http.server.configuration.port = port
	app.routes.defaultMaxBodySize = "10mb"
	
	// Enable HTTP response compression.
	// app.http.server.configuration.responseCompression = .enabled
	
	// Each environment type has its own default hostname. The hostname controls which address we will accept new connections on.
	// The default hostname for an environment may be overridden with the "SWIFTARR_HOSTNAME" environment variable,
	// and the "--hostname <addr>" command line parameter overrides the environment var.
	if let host = Environment.get("SWIFTARR_HOSTNAME") {
		app.http.server.configuration.hostname = host
	}
	else if app.environment == .development {
		app.http.server.configuration.hostname = "127.0.0.1"
	}
	else if app.environment == .production {
		app.http.server.configuration.hostname = "joco.hollandamerica.com"
	}
	
	// Make our chosen hostname a canonical hostname that Settings knows about
	if !Settings.shared.canonicalHostnames.contains(app.http.server.configuration.hostname) {
		Settings.shared.canonicalHostnames.append(app.http.server.configuration.hostname)
	}
	
	// Load the FQDNs that we expect Twitarr to be available from. This feeds into link processing to help
	// ensure a smooth experience between users who enter the site via different hostnames. For example:
	// http://joco.hollandamerica.com and https://twitarr.com are both expected to function and bring you
	// the same content.
	// The empty-string-undefined thing is a little hacky. But it solves a problem of wanting to disable all
	// canonical hostnames. The built-in defaults are set in Settings.swift but without a feature switch boolean
	// you can't disable them. So you can specify the environment variable empty and it will effectively
	// generate a hostname that will never exist, thus the regexes in CustomLeafTags will never match.
	if let canonicalHostnamesStr: String = Environment.get("SWIFTARR_CANONICAL_HOSTNAMES") {
		Settings.shared.canonicalHostnames = canonicalHostnamesStr.split(separator: ",").map { String($0) }
	}
	else if !app.http.server.configuration.hostname.isEmpty {
		Settings.shared.canonicalHostnames.append(app.http.server.configuration.hostname)
	}
	app.logger.debug("Setting canonical hostnames: \(Settings.shared.canonicalHostnames)")
}

func configureAPIURL(_ app: Application) throws {
	// API URL. We used to determine this in SiteController in apiQuery() based on the HTTP Host headers.
	// Due to the way the boat network is architected the HTTP host headers had to be stripped away and reset
	// to the container hostname/IP because of some NAT translations that we had no control over. Additionally,
	// to facilitate the eventual breaking up of the UI and API it would be better if we could point the UI
	// at any API endpoint and say "go". Unfortunately the Settings constructs are somewhat interlinked but
	// hey maybe someday we will complete the split.
	let apiScheme = Environment.get("API_SCHEME") ?? "http"
	let apiHostname = app.http.server.configuration.hostname	// Environment.get("API_HOSTNAME") ?? "127.0.0.1"
	// Don't bother casting this to an int, we're just gonna process it as a string the whole way through.
	let apiPort = app.http.server.configuration.port			// Environment.get("API_PORT") ?? "8081"
	let apiPrefix = Environment.get("API_PREFIX") ?? "/api/v3"
	guard let apiUrlComponents = URLComponents(string: "\(apiScheme)://\(apiHostname):\(apiPort)\(apiPrefix)"),
		let outputURL = apiUrlComponents.url else {
		throw "Unable to construct a valid API URL."
	}
	Settings.shared.apiUrlComponents = apiUrlComponents
	Logger(label: "app.swiftarr.configuration") .notice("API URL base is '\(outputURL)'.")
}

// register global middleware
func configureMiddleware(_ app: Application) throws {
	// By default, Vapor launches with 2 middlewares: RouteLoggingMiddleware and ErrorMiddleware.
	// We want to replace the standard Error middleware with SwiftarrErrorMiddleware, and we do that by
	// creating a new Middlewares().
	var new = Middlewares()

	// Set up CORS to allow any client hosted anywhere to access the API
	let corsConfiguration = CORSMiddleware.Configuration(
		allowedOrigin: .all,
		allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
		allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin]
	)
	let corsMiddleware = CORSMiddleware(configuration: corsConfiguration)
	new.use(corsMiddleware, at: .beginning)

	new.use(SwiftarrErrorMiddleware(environment: app.environment))
	new.use(SiteErrorMiddleware(environment: app.environment))		
	app.middleware = new
	
	// Change the default bcrypt cost for user accounts
	app.passwords.use(.bcrypt(cost: 9))
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
	
	// Create a custom Leaf source that doesn't have the '.toVisibleFiles' limit and uses '.html' instead of '.leaf' as the 
	// default extension. We need visible files turned off because of Heroku, which builds the app into a dir named ".swift-bin"
	// and copies all the resources and views into there. And, settings the extension to .html gets Xcode syntax highlighting 
	// to work without excessive futzing (you can manually set the type to HTML, per file, except Xcode keeps forgetting the setting).
	let customLeafSource = NIOLeafFiles(fileio: app.fileio, limits: [.toSandbox, .requireExtensions], 
			sandboxDirectory: app.directory.viewsDirectory, viewDirectory: app.directory.viewsDirectory, defaultExtension: "html")
	let leafSources = LeafSources()
	try leafSources.register(source: "swiftarrCustom", using: customLeafSource, searchable: true)
	app.leaf.sources = leafSources
	
	app.views.use(.leaf)

	// Custom Leaf tags
	app.leaf.tags["addJocomoji"] = AddJocomojiTag()
	app.leaf.tags["formatTwarrtText"] = try FormatPostTextTag(.twarrt)
	app.leaf.tags["formatPostText"] = try FormatPostTextTag(.forumpost)
	app.leaf.tags["formatFezText"] = try FormatPostTextTag(.fez)
	app.leaf.tags["formatSeamailText"] = try FormatPostTextTag(.seamail)
	app.leaf.tags["relativeTime"] = RelativeTimeTag()
	app.leaf.tags["eventTime"] = EventTimeTag()
	app.leaf.tags["staticTime"] = StaticTimeTag()
	app.leaf.tags["UTCTime"] = UTCTimeTag()
	app.leaf.tags["fezTime"] = FezTimeTag()
	app.leaf.tags["avatar"] = AvatarTag()
	app.leaf.tags["userByline"] = UserBylineTag()
	app.leaf.tags["cruiseDayIndex"] = CruiseDayIndexTag()
	app.leaf.tags["gameRating"] = GameRatingTag()
	app.leaf.tags["localTime"] = LocalTimeTag()
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
	app.migrations.add(CreateUserRoleSchema(), to: .psql)
	app.migrations.add(CreateUserNoteSchema(), to: .psql)
	app.migrations.add(CreateMuteWordSchema(), to: .psql)
	app.migrations.add(CreateAlertWordSchema(), to: .psql)
	app.migrations.add(CreateAlertWordPivotSchema(), to: .psql)
	app.migrations.add(CreateModeratorActionSchema(), to: .psql)
	app.migrations.add(CreateAnnouncementSchema(), to: .psql)
	app.migrations.add(CreateReportSchema(), to: .psql)
	app.migrations.add(CreateCategorySchema(), to: .psql)
	app.migrations.add(CreateForumSchema(), to: .psql)
	app.migrations.add(CreateForumEditSchema(), to: .psql)
	app.migrations.add(CreateForumPostSchema(), to: .psql)
	app.migrations.add(CreateForumPostEditSchema(), to: .psql)
	app.migrations.add(CreateForumReadersSchema(), to: .psql)
	app.migrations.add(CreatePostLikesSchema(), to: .psql)
	app.migrations.add(CreateEventSchema(), to: .psql)
	app.migrations.add(CreateEventFavoriteSchema(), to: .psql)
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
	app.migrations.add(CreateTimeZoneChangeSchema(), to: .psql)

	// Third, migrations that seed the db with initial data
	app.migrations.add(CreateAdminUsers(), to: .psql)
	app.migrations.add(CreateClientUsers(), to: .psql)
	app.migrations.add(CreateCategories(), to: .psql)
//	app.migrations.add(CreateForums(), to: .psql)		// Adds some initial forum threads; not the event forum threads.
	if app.environment == .testing || app.environment == .development {
		app.migrations.add(CreateTestUsers(), to: .psql)
		app.migrations.add(CreateTestData(), to: .psql)
	}
	
	// Fourth, migrations that import data from /seeds
	app.migrations.add(ImportRegistrationCodes(), to: .psql)
	app.migrations.add(ImportTimeZoneChanges(), to: .psql)
	app.migrations.add(ImportEvents(), to: .psql)
	app.migrations.add(ImportBoardgames(), to: .psql)	
	app.migrations.add(ImportKaraokeSongs(), to: .psql)	
	
	// Fifth, migrations that touch up initial state
	app.migrations.add(SetInitialEventForums(), to: .psql)
	app.migrations.add(SetInitialCategoryForumCounts(), to: .psql)

	// Finally, any additional migrations. List newly-written migrations here!
	app.migrations.add(CreateSearchIndexes(), to: .psql)
	app.migrations.add(FixSearchIndexes(), to: .psql)
}
  
// Perform several sanity checks to verify that we can access the dbs and resource files that we need.
// If we're misconfigured, this can emit more useful errors than the ones that'll come from deep inside db drivers.
func verifyConfiguration(_ app: Application) throws {
	var postgresChecksFailed = false
	// Test that we have a Postgres connection (requires that we've connected *and* authed).
	if !postgresChecksFailed, let postgresDB = app.db as? PostgresDatabase {
		do {
			let connClosed = try postgresDB.withConnection { conn in
				return postgresDB.eventLoop.future(conn.isClosed)
			}.wait()
			guard connClosed == false else {
				throw "Postgres DB driver doesn't report any open connections."
			}	
		}
		catch {
			app.logger.critical("Launchtime sanity check: Postgres connection is not open. \(error)")
			postgresChecksFailed = true
		}
	}
	
	// Test whether a 'swiftarr' database exists
	// @TODO make the database name use whatever is configured for the app. Potentially could
	// be called something other than 'swiftarr'.
	if !postgresChecksFailed, let sqldb = app.db as? SQLDatabase {
		do {
			let query = try sqldb.raw("SELECT 1 FROM pg_database WHERE datname='swiftarr'").first().wait()
			guard let sqlrow = query else  {
				throw "No result from SQL query."
			}
			guard try sqlrow.decode(column: "?column?", as: Int.self) == 1 else {
				throw "Database existence check failed in a weird way."
			}
		}
		catch {
			app.logger.critical("Launchtime sanity check: Could not find 'swiftarr' database in Postgres. \(error)")
			postgresChecksFailed = true
			
			// We could probably do `SQL CREATE DATABASE 'swiftarr'` here?
		}
	}
	
	// Do a dummy query on the DB, if the active command is `serve`.
	var commandName = app.environment.arguments.count >= 2 ? app.environment.arguments[1].lowercased() : "serve"
	if commandName.hasPrefix("-") {
		commandName = "serve"
	}
	if !postgresChecksFailed, commandName == "serve" {
		_ = User.query(on: app.db).count().flatMapThrowing { userCount in
			guard userCount > 0 else {
				throw "User table has zero users. Did the migrations all run?"
			}
			app.logger.notice("DB has \(userCount) users at launch.")
		}.flatMapErrorThrowing { error in
			app.logger.critical("Initial connection to Postgres failed. Is the db up and running? \(error)")
			throw error
		}
	}
	
	// Same idea for Redis. I'm not even sure what the 'steps' would be for diagnosing a connection error.
	_ = app.redis.ping(with: "Swiftarr configuration check during app launch").flatMapErrorThrowing { error in
		app.logger.critical("Initial connection to Redis failed. Is the db up and running?")
		throw error
	}

	// Next, check that the resource files are getting copied into the build directory. 
	// What's going on? Instead of running the app at the root of the git hierarchy, Xcode makes a /DerivedData dir and runs
	// apps (deep) inside there. A script build step is supposed to copy the contents of /Resources and /Seeds into the dir
	// the app runs in. If that script breaks or didn't run, this will hopefully catch it and tell admins what's wrong.
	// "vapor run", similarly, creates a ".build" dir and runs apps (deep) inside there.
	var cssFileFound = false
	let swiftarrCSSURL = Settings.shared.staticFilesRootPath.appendingPathComponent("Resources/Assets/css/swiftarr.css")
	var isDir: ObjCBool = false
	if FileManager.default.fileExists(atPath: swiftarrCSSURL.path, isDirectory: &isDir), !isDir.boolValue {
		cssFileFound = true
	}
	if !cssFileFound {
		app.logger.critical("Resource files not found during launchtime sanity check. This usually means the Resources directory isn't getting copied into the App directory in /DerivedData.")
	}

  // FileMiddleware checks eTags and will respond with NotModified, but doesn't set cache-control,
  // which we probably show for static files. That was the main reason for creating SiteFileController
  // and using it instead of FileMiddleware.
  //
  // SiteFileController just serves static files: images, css, and javascript files. Improvements over
  // fileMiddleware are that fileMiddleware ran globally on every request, and we couldn’t set
  // cache-control headers with fileMiddleware.
  //
  // tldr: Don't use the FileMiddleware.
}

// Found this in a Github search. Seems to be good enough for our needs unless someone has better ideas.
// https://github.com/contentstack/contentstack-swift/blob/master/Sources/ContentstackConfig.swift
func operatingSystemPlatform() -> String? {
	let osName: String? = {
		#if os(iOS)
		return "iOS"
		#elseif os(OSX)
		return "macOS"
		#elseif os(tvOS)
		return "tvOS"
		#elseif os(watchOS)
		return "watchOS"
		#elseif os(Linux)
		return "Linux"
		#else
		return nil
		#endif
	}()
	return osName
}

// Wrapper function to add any custom CLI commands. Might be overkill but at least it's scalable.
// These should be stored in Sources/App/Commands.
func configureCommands(_ app: Application) {
}

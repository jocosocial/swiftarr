import Vapor

/// Register your application's routes here.
public func routes(_ app: Application) throws {

	// API Route Controllers all handle routes prefixed with "/api/v3/", and
	// handle Swiftarr API calls that generally take or return JSON data.
	//
	// API routes generally use Tokens to auth, do not use sessions, and use Fluent and Redis to access the underlying databases.
	let apiControllers: [APIRouteCollection] = [
			AdminController(),
			ModerationController(),
			AlertController(),
			AuthController(),
			ClientController(),
			EventController(),
			FezController(),
			ForumController(),
			ImageController(),
			TestController(),
			TwitarrController(),
			UserController(),
			UsersController(),
	]
	try apiControllers.forEach { try $0.registerRoutes(app) }

	// Site Route Controllers handle 'GET' routes that return HTML and 'POST' routes that take data from HTML forms. 
	// Site Routes use session cookies to track user sessions. Site routes (generally) don't access the DB directly,
	// instead calling API routes using Vapor's Client APIs to access model data. 
	//
	// API tokens are stored in session data, allowing site routes to make authenticated calls to API routes.
	let siteControllers: [SiteControllerUtils] = [
			SiteController(),
			SiteLoginController(),
			SiteTwitarrController(),
			SiteSeamailController(),
			SiteFriendlyFezController(),
			SiteForumController(),
			SiteEventsController(),
			SiteUserController(),
			SiteModController(),
			SiteAdminController()
	]
	try siteControllers.forEach { try $0.registerRoutes(app) }
}

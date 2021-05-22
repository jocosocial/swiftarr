import Vapor

/// Register your application's routes here.
public func routes(_ app: Application) throws {
    
	let siteLoginController = SiteLoginController()
	try siteLoginController.registerRoutes(app)

	let siteTwitarrController = SiteTwitarrController()
	try siteTwitarrController.registerRoutes(app)
	
	let siteSeamailController = SiteSeamailController()
	try siteSeamailController.registerRoutes(app)
	
	let siteForumController = SiteForumController()
	try siteForumController.registerRoutes(app)
	
	let siteController = SiteController()
	try siteController.registerRoutes(app)

	let adminController = AdminController()
	try app.register(collection: adminController)

	let authController = AuthController()
	try app.register(collection: authController)

	let clientController = ClientController()
	try app.register(collection: clientController)

	let eventController = EventController()
	try app.register(collection: eventController)

	let fezController = FezController()
	try app.register(collection: fezController)

	let forumController = ForumController()
	try app.register(collection: forumController)

	let testController = TestController()
	try app.register(collection: testController)

	let twitarrController = TwitarrController()
	try app.register(collection: twitarrController)

	let userController = UserController()
	try app.register(collection: userController)

	let usersController = UsersController()
	try app.register(collection: usersController)

	let imageController = ImageController()
	try app.register(collection: imageController)
}

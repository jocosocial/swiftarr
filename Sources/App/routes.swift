import Vapor

/// Register your application's routes here.
public func routes(_ app: Application) throws {

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
    	
	let adminController = AdminController()
	try app.register(collection: adminController)

	let alertController = AlertController()
	try app.register(collection: alertController)
	
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

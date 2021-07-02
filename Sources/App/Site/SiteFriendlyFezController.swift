import Vapor
import Crypto
import FluentSQL

struct SiteFriendlyFezController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app)
        globalRoutes.get("fez", use: fezRootPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app)
        privateRoutes.get("fez", "create", use: fezCreatePageHandler)
	}
	
// MARK: - FriendlyFez
	// Shows the root Seamail page, with a list of all conversations.
	func fezRootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/fez/joined").throwingFlatMap { response in
			let fezzes = try response.content.decode([FezData].self)
			struct SeamailRootPageContext : Encodable {
				var trunk: TrunkContext
				var fezzes: [FezData]
				
				init(_ req: Request, fezzes: [FezData]) throws {
					trunk = .init(req, title: "Seamail")
					self.fezzes = fezzes
				}
			}
			let ctx = try SeamailRootPageContext(req, fezzes: fezzes)
			return req.view.render("fezRoot", ctx)
		}
	}
    
    // Shows the Create New Friendly Fez page
    func fezCreatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct SeamaiCreatePageContext : Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext
			
			init(_ req: Request) throws {
				trunk = .init(req, title: "New Seamail")
				post = .init(forNewSeamail: true)
			}
		}
		let ctx = try SeamaiCreatePageContext(req)
		return req.view.render("fezCreate", ctx)
    }
}

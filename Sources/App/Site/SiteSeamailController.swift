import Vapor
import Crypto
import FluentSQL

struct SiteSeamailController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app)
        globalRoutes.get("seamail", use: seamailRootPageHandler)
        globalRoutes.get("seamail", "create", use: seamailCreatePageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
//		let privateRoutes = getPrivateRoutes(app)
	}
	
// MARK: - Seamail
	// Shows
    func seamailRootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
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
			return req.view.render("seamails", ctx)
    	}
    }
    
    func seamailCreatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct SeamaiCreatePageContext : Encodable {
			var trunk: TrunkContext
			
			init(_ req: Request) throws {
				trunk = .init(req, title: "New Seamail")
			}
		}
		let ctx = try SeamaiCreatePageContext(req)
		return req.view.render("seamailCreate", ctx)
    }
}

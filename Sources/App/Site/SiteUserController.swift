import Vapor
import Crypto
import FluentSQL

struct SiteUserController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app)
        globalRoutes.get("user", userIDParam, use: userProfilePageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
//		let privateRoutes = getPrivateRoutes(app)
	}
	
	func userProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let userID = req.parameters.get(userIDParam.paramString) else {
    		throw "Invalid user ID"
    	}
    	return apiQuery(req, endpoint: "/users/\(userID)/profile").throwingFlatMap { response in
			let profile = try response.content.decode(ProfilePublicData.self)
			struct UserProfileContext : Encodable {
				var trunk: TrunkContext
				var profile: ProfilePublicData
				
				init(_ req: Request, profile: ProfilePublicData) throws {
					trunk = .init(req, title: "Create New Forum")
					self.profile = profile
				}
			}
			let ctx = try UserProfileContext(req, profile: profile)
			return req.view.render("userProfile", ctx)			
    	}
	}

}

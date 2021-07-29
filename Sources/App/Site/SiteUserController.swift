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
        globalRoutes.get("username", ":username", use: usernameProfilePageHandler)

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
					trunk = .init(req, title: "User Profile", tab: .none)
					self.profile = profile
				}
			}
			let ctx = try UserProfileContext(req, profile: profile)
			return req.view.render("userProfile", ctx)			
    	}
	}

	func usernameProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let username = req.parameters.get("username") else {
    		throw "Invalid username parameter"
    	}
    	return apiQuery(req, endpoint: "/users/find/\(username)").throwingFlatMap { headerResponse in
    		do {
				let userHeader = try headerResponse.content.decode(UserHeader.self)
				return apiQuery(req, endpoint: "/users/\(userHeader.userID)/profile").throwingFlatMap { response in
					let profile = try response.content.decode(ProfilePublicData.self)
					struct UserProfileContext : Encodable {
						var trunk: TrunkContext
						var profile: ProfilePublicData
						
						init(_ req: Request, profile: ProfilePublicData) throws {
							trunk = .init(req, title: "User Profile", tab: .none)
							self.profile = profile
						}
					}
					let ctx = try UserProfileContext(req, profile: profile)
					return req.view.render("userProfile", ctx)			
				}
			}
			catch {
				let err = try headerResponse.content.decode(ErrorResponse.self)
				throw err
			}
		}
	}

}

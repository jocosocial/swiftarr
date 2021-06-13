import Vapor
import Crypto
import FluentSQL

/// The collection of `/api/v3/admin/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct AdminController: RouteCollection {
    
    var twarrtIDParam = PathComponent(":twarrt_id")
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(routes: RoutesBuilder) throws {
        
        // convenience route group for all /api/v3/admin endpoints
        let adminRoutes = routes.grouped("api", "v3", "admin")
        
        // instantiate authentication middleware
        let tokenAuthMiddleware = Token.authenticator()
        let requireVerifiedMiddleware = RequireVerifiedMiddleware()
        let requireModMiddleware = RequireModeratorMiddleware()
        let guardAuthMiddleware = User.guardMiddleware()
        
        // set protected route groups
        let userAuthGroup = adminRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware, requireVerifiedMiddleware])
        let moderatorAuthGroup = adminRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware, requireModMiddleware])
                 
        // endpoints available for Moderators only
		moderatorAuthGroup.get("reports", use: reportsHandler)
		moderatorAuthGroup.get("twarrt", twarrtIDParam, use: twarrtModerationHandler)
		
//        tokenAuthGroup.get("user", ":user_id", use: userHandler)
    }
    
    // MARK: - Open Access Handlers
    
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `GET /api/v3/admin/user/ID`
    ///
    /// Retrieves the full `User` model of the specified user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not an admin.
    /// - Returns: `User`.
    func userHandler(_ req: Request) throws -> EventLoopFuture<User> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.hasAccess(.admin) else {
            throw Abort(.forbidden, reason: "admins only")
        }
        return User.findFromParameter("user_id", on: req)
    }
    
    /// `GET /api/v3/admin/reports`
    ///
    /// Retrieves the full `Report` model of all reports.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not an admin.
    /// - Returns: `[Report]`.
    func reportsHandler(_ req: Request) throws -> EventLoopFuture<[ReportAdminData]> {
        return Report.query(on: req.db).sort(\.$createdAt, .descending).all().flatMapThrowing { reports in
        	return try reports.map { try ReportAdminData.init(req: req, report: $0) }
        }
    }
    
	/// Moderator only. Returns info admins and moderators need to review a twarrt. Works if twarrt has been deleted. Shows
	/// twarrt's quarantine and reviewed states.
    ///
    /// * The current Twarrt
    /// * Previous versions of the twarrt
    /// * Reports against the twarrt
    func twarrtModerationHandler(_ req: Request) throws -> EventLoopFuture<TwarrtModerationData> {
  		guard let paramVal = req.parameters.get(twarrtIDParam.paramString), let twarrtID = Int(paramVal) else {
            throw Abort(.badRequest, reason: "Request parameter \(twarrtIDParam.paramString) is missing.")
        }
		return Twarrt.query(on: req.db).filter(\._$id == twarrtID).withDeleted().first()
        		.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")).flatMap { twarrt in
   			return Report.query(on: req.db)
   					.filter(\.$reportType == .twarrt)
   					.filter(\.$reportedID == paramVal)
   					.sort(\.$createdAt, .descending).all().flatMap { reports in
				return twarrt.$edits.query(on: req.db).sort(\.$createdAt, .ascending).all().flatMapThrowing { edits in
					let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
					let twarrtData = try TwarrtData(twarrt: twarrt, creator: authorHeader, isBookmarked: false, 
							userLike: nil, likeCount: 0, overrideQuarantine: true)
					let editData: [TwarrtEditData] = try edits.map {
						let editAuthorHeader = try req.userCache.getHeader($0.$editor.id)
						return try TwarrtEditData(edit: $0, editor: editAuthorHeader)
					}
					let reportData = try reports.map { try ReportAdminData.init(req: req, report: $0) }
					let modData = TwarrtModerationData(twarrt: twarrtData, isDeleted: twarrt.deletedAt != nil, 
							isQuarantined: twarrt.isQuarantined, isReviewed: twarrt.isReviewed, edits: editData, reports: reportData)
					return modData
				}
			}
        }
	}
    
    // MARK: - Helper Functions

}

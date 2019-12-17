import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/twitarr/*` route endpoint and handler functions related
/// to the twit-arr stream.

struct Twitarr: RouteCollection, ImageHandler, ContentFilterable {
    // MARK: ImageHandler Conformance
    
    /// The base directory for storing Twarrt images.
    var imageDir: String {
        return "images/twitarr/"
    }
    
    // The height of Twarrt image thumbnails.
    var thumbnailHeight: Int {
        return 100
    }
    
    // MARK: RouteCollection Conformance
    
    /// Required. Resisters routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/twitarr endpoints
        let twitarrRoutes = router.grouped("api", "v3", "twitarr")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let sharedAuthGroup = twitarrRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGrouo = twitarrRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // endpoints available whether logged in or not
        
        // endpoints only available when logged in
        tokenAuthGrouo.post(PostCreateData.self, at: "create", use: twarrtCreateHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    func twarrtCreateHandler(_ req: Request, data: PostCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // ensure user has write access
        guard user.accessLevel.rawValue >= UserAccessLevel.verified.rawValue else {
            throw Abort(.forbidden, reason: "user cannot post to twitarr")
        }
        // see `PostCreateData.validations()`
        try data.validate()
        // process image
        return try self.processImage(data: data.imageData, forType: .twarrt, on: req).flatMap {
            (filename) in
            // create twarrt
            let twarrt = try Twarrt(
                authorID: user.requireID(),
                text: data.text,
                image: filename
            )
            return twarrt.save(on: req).map {
                (savedTwarrt) in
                // return as PostData with 201 status
                let response = Response(http: HTTPResponse(status: .created), using: req)
                try response.content.encode(try savedTwarrt.convertToData(withLike: nil, likeCount: 0))
                return response
            }
        }
    }
}

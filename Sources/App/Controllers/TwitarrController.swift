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
        tokenAuthGrouo.post(Twarrt.parameter, "delete", use: twarrtDeleteHandler)
        tokenAuthGrouo.post(PostContentData.self, at: Twarrt.parameter, "update", use: twarrtUpdateHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/twitarr/create`
    ///
    /// Create a new `Twarrt` in the twitarr stream.
    ///
    /// - Requires: `PostCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCreateData` containing the twarrt's text and optional image.
    /// - Returns: `PostData` containing the twarrt's contents and metadata.
    func twarrtCreateHandler(_ req: Request, data: PostCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
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
    
    /// `POST /api/v3/twitarr/ID/delete`
    ///
    /// Delete the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No COntent on success.
    func twarrtDeleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "user is not permitted to delete twarrt")
            }
            return twarrt.delete(on: req).transform(to: .noContent)
        }
    }
    
    /// `POST /api/v3/twitarr/ID/update`
    ///
    /// Update the specified `Twarrt`.
    ///
    /// - Note: This endpoint only changes the `.text` and `.image` *filename* of the twarrt.
    ///   To change or remove the actual image associated with the twarrt, use
    ///   `POST /api/v3/twitarr/ID/image`  or `POST /api/v3/twitarr/ID/image/remove`.
    ///
    /// - Requires: `PostCOntentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCOntentData` containing the twarrt's text and image filename.
    /// - Throws: 403 error if user is not post owner or has read-only access.
    /// - Returns: `PostData` containing the twarrt's contents and metadata.
    func twarrtUpdateHandler(_ req: Request, data: PostContentData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            // ensure user has write access
            guard try twarrt.authorID == user.requireID(),
                user.accessLevel.rawValue >= UserAccessLevel.verified.rawValue else {
                    throw Abort(.forbidden, reason: "user not permitted to edit twarrt")
            }
            // get like count
            return try TwarrtLikes.query(on: req)
                .filter(\.twarrtID == twarrt.requireID())
                .count()
                .flatMap {
                    (count) in
                    // see `PostCreateData.validation()`
                    try data.validate()
                    // stash current contents
                    let twarrtEdit = try TwarrtEdit(
                        twarrtID: twarrt.requireID(),
                        twarrtContent: PostContentData(text: twarrt.text, image: twarrt.image)
                    )
                    // update if there are changes
                    if twarrt.text != data.text || twarrt.image != data.image {
                        twarrt.text = data.text
                        twarrt.image = data.image
                        return twarrt.save(on: req).flatMap {
                            (savedTwarrt) in
                            // save TwarrtEdit
                            return twarrtEdit.save(on: req).map {
                                (_) in
                                // return updated twarrt as PostData, with 201 status
                                let response = Response(http: HTTPResponse(status: .created), using: req)
                                try response.content.encode(
                                    try savedTwarrt.convertToData(withLike: nil, likeCount: count)
                                )
                                return response
                            }
                        }
                    } else {
                        // just return as PostData, with 200 status
                        let response = Response(http: HTTPResponse(status: .ok), using: req)
                        try response.content.encode(
                            try twarrt.convertToData(withLike: nil, likeCount: count)
                        )
                        return req.future(response)
                    }
            }
        }
    }
}

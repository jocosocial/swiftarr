import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis
import Metrics

/// The collection of `/api/v3/client/*` route endpoints and handler functions that provide
/// bulk retrieval services for registered API clients.

struct ClientController: APIRouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/client endpoints
		let clientRoutes = app.grouped("api", "v3", "client")

        // open access endpoints
        clientRoutes.get("time", use: clientTimeHandler)

		// endpoints available only when logged in
		let tokenAuthGroup = addTokenAuthGroup(to: clientRoutes)
		tokenAuthGroup.get("user", "updates", "since", ":date", use: userUpdatesHandler)
		tokenAuthGroup.get("usersearch", use: userSearchHandler)
		
		// Endpoints available with HTTP Basic auth. I'd prefer token auth for this, but setting that up looks difficult.
		let basicAuthGroup = addBasicAuthGroup(to: clientRoutes)
		basicAuthGroup.get("metrics", use: prometheusMetricsSource)
    }

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
        
    /// `GET /api/v3/client/usersearch`
    ///
    /// Retrieves all `UserProfile.userSearch` values, returning an array of precomposed
    /// `.userSearch` strings in `UserSearch` format. The intended use for this data
    /// is to efficiently isolate a particular user in an auto-complete type scenario, using
    /// **all** of the `.displayName`, `.username` and `.realName` profile fields.
    ///
    /// - Requires: `x-swiftarr-user` header in the request.
    /// - Throws: 400 error if no valid date string provided. 401 error if the required header
    ///   is missing or invalid. 403 error if user is not a registered client.
    /// - Returns: An array of  <doc:UserSearch> containing the ID and `.userSearch` string values
    ///   of all users, sorted by username.
    func userSearchHandler(_ req: Request) throws -> EventLoopFuture<[UserSearch]> {
        let client = try req.auth.require(User.self)
        // must be registered client
        guard client.accessLevel == .client else {
            throw Abort(.forbidden, reason: "registered clients only")
        }
        // must be on behalf of user
        guard let userHeader = req.headers["x-swiftarr-user"].first,
            let userID = UUID(uuidString: userHeader) else {
                throw Abort(.unauthorized, reason: "no valid 'x-swiftarr-user' header found")
        }
        // find user
        return User.find(userID, on: req.db)
				.unwrap(or: Abort(.unauthorized, reason: "'x-swiftarr-user' user not found"))
				.throwingFlatMap { (user) in
			// must be actual user
			guard user.accessLevel != .client else {
				throw Abort(.unauthorized, reason: "'x-swiftarr-user' user cannot be client")
			}
			// remove blocked users
			let blocked = req.userCache.getBlocks(userID)
			return User.query(on: req.db).filter(\.$id !~ blocked).sort(\.$username, .ascending).all().flatMapThrowing { users in
				// return as [UserSearch]
				return try users.map { try UserSearch(userID: $0.requireID(), userSearch: $0.userSearch) }
			}
        }
    }
    
    /// `GET /api/v3/client/user/updates/since/DATE`
    ///
    /// Retrieves the `UserHeader` of all users with a `.profileUpdatedAt` timestamp later
    /// than the specified date. The `DATE` parameter is a string, and may be provided in
    /// either of two formats:
    ///
    /// * a string literal `Double` (e.g. "1574364935" or "1574364935.88991")
    /// * an ISO 8601 `yyyy-MM-dd'T'HH:mm:ssZ` string (e.g. "2019-11-21T05:31:28Z")
    ///
    /// The second format is precisely what is returned in `swiftarr` JSON responses, while
    /// the numeric form makes for a prettier URL.
    ///
    /// - Requires: `x-swiftarr-user` header in the request.
    /// - Parameter Date: in URL path. See above for formats.
    /// - Throws: 400 error if no valid date string provided. 401 error if the required header
    ///   is missing or invalid. 403 error if user is not a registered client.
    /// - Returns: An array of <doc:UserHeader> containing all updated users.
    func userUpdatesHandler(_ req: Request) throws -> EventLoopFuture<[UserHeader]> {
		let client = try req.auth.require(User.self)
        // must be registered client
        guard client.accessLevel == .client else {
            throw Abort(.forbidden, reason: "registered clients only")
        }
        // must be on behalf of user
        guard let userHeader = req.headers["x-swiftarr-user"].first,
            let userID = UUID(uuidString: userHeader) else {
                throw Abort(.unauthorized, reason: "no valid 'x-swiftarr-user' header found")
        }
		// parse date parameter
		let since = req.parameters.get("date")!
		guard let date = ClientController.dateFromParameter(string: since) else {
			throw Abort(.badRequest, reason: "'\(since)' is not a recognized date format")
		}

        // find user
        return User.find(userID, on: req.db)
            .unwrap(or: Abort(.unauthorized, reason: "'x-swiftarr-user' user not found"))
            .flatMapThrowing { (user) in
				guard user.accessLevel != .client else {
					throw Abort(.unauthorized, reason: "'x-swiftarr-user' user cannot be client")
				}
				return try req.userCache.getHeaders(fromDate: date, forUser: user)
        }
    }
    
    /// `GET /api/v3/client/metrics`
    ///
    /// For use with [Prometheus](https://prometheus.io), a server metrics package. When a Prometheus server process
	/// is connected, it will poll this endpoint for metrics updates. You can then view Swiftarr metrics data with charts and graphs in a web page served
	/// by Prometheus.
    ///
    /// - Requires: `x-swiftarr-user` header in the request.
    /// - Throws: 400 error if no valid date string provided. 401 error if the required header
    ///   is missing or invalid. 403 error if user is not a registered client.
    /// - Returns: Data about what requests are being called, how long they take to complete, how the databases are doing, what the server's CPU utilization is,
	/// plus a bunch of other metrics data. All the data is in some opaquish Prometheus format.
	func prometheusMetricsSource(_ req: Request) -> EventLoopFuture<String> {
		let promise = req.eventLoop.makePromise(of: String.self)
		DispatchQueue.global().async {
			do {
				try MetricsSystem.prometheus().collect(into: promise)
			} catch {
				promise.fail(error)
			}
		}
		return promise.futureResult
	}

    /// `GET /api/v3/client/time`
    ///
    /// Return the current time on the server in ISO8601 format. Useful for figuring out when you are.
    func clientTimeHandler(_ req: Request) -> EventLoopFuture<String> {
        // https://stackoverflow.com/questions/58307194/swift-utc-timezone-is-not-utc
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM dd hh:mm a zzzz")
        return req.eventLoop.makeSucceededFuture(formatter.string(from: Date()))
    }

    // MARK: - Helper Functions
}

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

		// endpoints available only when logged in
		let tokenAuthGroup = addTokenAuthGroup(to: clientRoutes)
		tokenAuthGroup.get("user", "updates", "since", ":date", use: userUpdatesHandler)
		tokenAuthGroup.get("usersearch", use: userSearchHandler)
		
		// Endpoints available with HTTP Basic auth. I'd prefer token auth for this, but setting that up looks difficult.
		let basicAuthGroup = addBasicAuthGroup(to: clientRoutes)
		basicAuthGroup.get("metrics", use: prometheusMetricsSource)
        basicAuthGroup.post("alert", use: prometheusAlertHandler)
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
    /// - Throws: 403 error if user is not a registered client.
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

    /// `POST /api/v3/client/alert`
    ///
    /// For use with the [Prometheus Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/). A webhook can
    /// be configured to POST a payload containing information about actively firing/cleared alerts. A situation arose on JoCo 2022
    /// in which the server ran out of disk space. We have Prometheus metrics for this but no way to tell us about it without
    /// checking the dashboards manually. This endpoint translates that payload into a Seamail that can be sent to an arbitrary
    /// user (usually TwitarrTeam).
    /// 
    /// It is expected that Alertmanager receivers are configured with a pattern of "twitarr-${username}". Where username is a
    /// valid username in Twitarr. This probably explodes with spaces or weird characters but since we expect it to only
    /// be "admin" or "twitarrteam" this should be fine.
    ///
    /// This should be used very judiciously and only for actionable alerts! On-call sucks in the real world and I don't want
    /// people to get spammed with messages while on vacation.
    /// 
    /// - Throws: 403 error if user is not a registered client.
    /// - Returns: 201 created.
    func prometheusAlertHandler(_ req: Request) async throws -> Response {
        // Figure out who we are sending to.
        let data = try ValidatingJSONDecoder().decode(AlertmanagerWebhookPayload.self, fromBodyOf: req)
        guard data.receiver.components(separatedBy: "-").indices.contains(1) else {
            throw Abort(.badRequest, reason: "receiver (\(data.receiver)) must be in the format \"twitarr-${username}\".")
        }
        let seamailUser = data.receiver.components(separatedBy: "-")[1]        
        guard let destinationUser = req.userCache.getHeader(seamailUser) else {
            throw Abort(.badRequest, reason: "User \(seamailUser) not found.")
        }
        req.logger.info("Alertmanager webhook received destined for user '\(seamailUser)' (\(destinationUser.userID)).")

        // Acquire the source user, which is a prometheus service account we create on database initialization.
        guard let sourceUser = req.userCache.getHeader("prometheus") else {
            throw Abort(.internalServerError, reason: "User prometheus not found.")
        }

        // Construct the seamail (fez) based on the data we got in the webhook call.
        let fez = FriendlyFez(owner: sourceUser.userID, fezType: FezType.closed, title: data.getSummarySubject(), info: "",
				location: nil, startTime: nil, endTime: nil,
				minCapacity: 0, maxCapacity: 0)
        let initialUsers = [sourceUser.userID, destinationUser.userID]
        fez.participantArray = initialUsers

        // https://theswiftdev.com/beginners-guide-to-the-asyncawait-concurrency-api-in-vapor-fluent/
        //
        // @TODO figure out if we can reduce these.
        print("saving fez")
        try await fez.save(on: req.db)
        print("attmpting post")
        let post = try FezPost(fez: fez, authorID: sourceUser.userID, text: data.getSummaryContent(), image: nil)
        fez.postCount += 1
        print("saving post")
        try await post.save(on: req.db)
        // try await fez.save(on: req.db)

        // @TODO need to deconstruct this.
        // @TODO not generating proper notifications for trunk
        fez.save(on: req.db).flatMap { _ in
			return User.query(on: req.db).filter(\.$id ~~ initialUsers).all().flatMap { participants in
				return fez.$participants.attach(participants, on: req.db, { $0.readCount = 0; $0.hiddenCount = 0 }).throwingFlatMap { (_) in
					return fez.$participants.$pivots.query(on: req.db).filter(\.$user.$id == sourceUser.userID)
							.first().flatMapThrowing() { creatorPivot -> Response in
						let fezData = try buildFezData(from: fez, with: creatorPivot, posts: [], for: req.userCache.getUser(sourceUser.userID)!, on: req)
						// with 201 status
						let response = Response(status: .created)
						try response.content.encode(fezData)
						return response
					}
				}
			}
		}
        // It's possible that Alertmanager could do something with the information
        // it gets back but that can be a project for a different day.
        return Response(status: .ok)
    }
}

extension ClientController: FezProtocol {
    /// This page intentionally left blank. In case we have extra things to add later on
    /// I'm keeping it seperate even though this could be done above.
}
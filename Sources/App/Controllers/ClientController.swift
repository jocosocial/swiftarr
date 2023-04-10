import Crypto
import Fluent
import FluentSQL
import Metrics
import Redis
import Vapor

/// The collection of `/api/v3/client/*` route endpoints and handler functions that provide
/// bulk retrieval services for registered API clients.

struct ClientController: APIRouteCollection {

	// MARK: RouteCollection Conformance

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/client endpoints
		let clientRoutes = app.grouped("api", "v3", "client")

		// open access endpoints
		clientRoutes.get("health", use: healthHandler)

		// endpoints available only when logged in
		let tokenAuthGroup = addTokenCacheAuthGroup(to: clientRoutes)
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
	/// - Returns: An array of  `UserSearch` containing the ID and `.userSearch` string values
	///   of all users, sorted by username.
	func userSearchHandler(_ req: Request) async throws -> [UserSearch] {
		let client = try req.auth.require(UserCacheData.self)
		// must be registered client
		guard client.accessLevel == .client else {
			throw Abort(.forbidden, reason: "registered clients only")
		}
		// must be on behalf of user
		guard let userHeader = req.headers["x-swiftarr-user"].first,
			let userID = UUID(uuidString: userHeader)
		else {
			throw Abort(.unauthorized, reason: "no valid 'x-swiftarr-user' header found")
		}
		// find user
		guard let user = try await User.find(userID, on: req.db) else {
			throw Abort(.unauthorized, reason: "'x-swiftarr-user' user not found")
		}
		// must be actual user
		guard user.accessLevel != .client else {
			throw Abort(.unauthorized, reason: "'x-swiftarr-user' user cannot be client")
		}
		// remove blocked users
		let blocked = req.userCache.getBlocks(userID)
		let users = try await User.query(on: req.db).filter(\.$id !~ blocked).sort(\.$username, .ascending).all()
		// return as [UserSearch]
		return try users.map { try UserSearch(userID: $0.requireID(), userSearch: $0.userSearch) }
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
	/// - Returns: An array of `UserHeader` containing all updated users.
	func userUpdatesHandler(_ req: Request) async throws -> [UserHeader] {
		let client = try req.auth.require(UserCacheData.self)
		// must be registered client
		guard client.accessLevel == .client else {
			throw Abort(.forbidden, reason: "registered clients only")
		}
		// must be on behalf of user
		guard let userHeader = req.headers["x-swiftarr-user"].first,
			let userID = UUID(uuidString: userHeader)
		else {
			throw Abort(.unauthorized, reason: "no valid 'x-swiftarr-user' header found")
		}
		// parse date parameter
		let since = req.parameters.get("date")!
		guard let date = ClientController.dateFromParameter(string: since) else {
			throw Abort(.badRequest, reason: "'\(since)' is not a recognized date format")
		}

		// find user
		guard let user = try await User.find(userID, on: req.db) else {
			throw Abort(.unauthorized, reason: "'x-swiftarr-user' user not found")
		}
		guard user.accessLevel != .client else {
			throw Abort(.unauthorized, reason: "'x-swiftarr-user' user cannot be client")
		}
		return try req.userCache.getHeaders(fromDate: date, forUser: user)
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
		DispatchQueue.global()
			.async {
				do {
					try MetricsSystem.prometheus().collect(into: promise)
				}
				catch {
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
	/// It is expected that the Prometheus alerts are configured with two custom annotations:
	///   * participants: A comma-seperated list of usernames to send the seamail to.
	///   * summary: A string containing a message body to send in the seamail.
	///
	/// This should be used very judiciously and only for actionable alerts! On-call sucks in the real world and I don't want
	/// people to get spammed with messages while on vacation.
	///
	/// - Throws: 403 error if user is not a registered client.
	/// - Returns: 201 created.
	func prometheusAlertHandler(_ req: Request) async throws -> Response {
		let data = try ValidatingJSONDecoder().decode(AlertmanagerWebhookPayload.self, fromBodyOf: req)

		// Locate the source user, which is a prometheus service account we create on database initialization.
		guard let sourceUserHeader = req.userCache.getHeader("prometheus") else {
			throw Abort(.internalServerError, reason: "User prometheus not found.")
		}

		// In my testing I couldn't get the AlertmanagerWebhookPayload.alerts array to be larger than one.
		// In the event I missed some weird case I'm going to put this in a loop that best case just runs once anyway.
		for alert in data.alerts {
			guard alert.annotations["participants"] != nil else {
				throw Abort(.badRequest, reason: "Could not decode participants. Requires annotation.")
			}
			guard let destinationUsernames = alert.annotations["participants"]?.components(separatedBy: ",") else {
				throw Abort(
					.badRequest,
					reason: "Could not decode participants. Requires comma-separated list of usernames."
				)
			}
			var destinationUserHeaders: [UserHeader] = []
			for destinationUsername in destinationUsernames {
				guard req.userCache.getHeader(destinationUsername) != nil else {
					throw Abort(.badRequest, reason: "Unknown participant username: '\(destinationUsername)'")
				}
				destinationUserHeaders.append(req.userCache.getHeader(destinationUsername)!)
			}
			let alertSubject = "Prometheus Alert: \(alert.getName()) is now \(alert.status)."
			req.logger.warning("\(alertSubject)")
			// I speak Python, and "list comprehension" is not nearly as easy here. Fortunately the toUserIDs magic
			// was adapted from https://stackoverflow.com/questions/24003584/list-comprehension-in-swift
			try await sendSimpleSeamail(
				req,
				fromUserID: sourceUserHeader.userID,
				toUserIDs: destinationUserHeaders.map { $0.userID },
				subject: alertSubject,
				initialMessage: alert.getSummary()
			)
		}

		// It's possible that Alertmanager could do something with the information
		// it gets back but that can be a project for a different day.
		return Response(status: .ok)
	}

	/// `GET /api/v3/client/health`
	///
	/// HTTP endpoint to report application health status.
	/// During the 2022 "Bad Gateway" issue we noticed the app taking a while to start
	/// up with a bunch of Users in the table. During this time Traefik would route
	/// requests but the app wasn't listening yet. This healthcheck won't complete
	/// successfully unless the app has started so it's a good barometer of when we're
	/// ready to service requests.
	///
	/// - Throws: 500 error if Redis or Postgres are unhappy.
	/// - Returns: 200 OK.
	func healthHandler(_ req: Request) async throws -> HealthResponse {
		// Redis only tests that Redis replies, which should be a pretty good indicator.
		let _ = try await req.redis.ping().get()
		// Postgres has to actually do a query.
		let _ = try await User.query(on: req.db).first()

		return HealthResponse()
	}
}

extension ClientController: FezProtocol {
	/// This page intentionally left blank. In case we have extra things to add later on
	/// I'm keeping it seperate even though this could be done above.
}

import Crypto
import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/personalevents/*` route endpoints and handler functions related
/// to events that are specific to individual users.

struct PersonalEventController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// Convenience route group for all /api/v3/personalevents endpoints.
		let personalEventRoutes = app.grouped("api", "v3", "personalevents")

		// Endpoints available only when logged in.
		let tokenAuthGroup = personalEventRoutes.tokenRoutes(feature: .personalevents)
		tokenAuthGroup.get(use: personalEventsHandler)
		tokenAuthGroup.post("create", use: personalEventCreateHandler)
		tokenAuthGroup.post(personalEventIDParam, "delete", use: personalEventDeleteHandler)
		tokenAuthGroup.delete(personalEventIDParam, use: personalEventDeleteHandler)
	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	/// All handlers in this route group require a valid HTTP Bearer Authentication
	/// header in the request.

	/// `GET /api/v3/personalevents`
	///
	/// Retrieve the `PersonalEvent`s the user has access to, sorted by `.startTime`.
	/// By default this returns all events that the user has created or was added to.
	///
	/// **URL Query Parameters:**
	/// - ?cruiseday=INT    Embarkation day is day 1, value should be less than or equal to `Settings.shared.cruiseLengthInDays`, which will be 8 for the 2022 cruise.
	/// - ?date=DATE        Returns events occurring on the given day. Empty list if there are no cruise events on that day.
	/// - ?time=DATE        Returns events whose startTime is earlier (or equal) to DATE and endTime is later than DATE. Note that this will often include 'all day' events.
	/// - ?search=STRING    Returns events whose title or description contain the given string.
	/// - ?owned=true       Returns events only that the user has created. Mutually exclusive with joined.
	/// - ?joined=true      Returns events only that the user has joined. Mutually exclusive with owned.
	///
	/// The day and date parameters actually return events from 3AM local time on the given day until 3AM the next day--some events start after midnight and tend to get lost by those
	/// looking at daily schedules.
	///
	/// - Returns: An array of `PersonalEeventData` containing the `PersonalEvent`s.
	func personalEventsHandler(_ req: Request) async throws -> [PersonalEventData] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		struct QueryOptions: Content {
			var cruiseday: Int?
			var date: Date?
			var time: Date?
			var search: String?
			var owned: Bool?
			var joined: Bool?
		}
		let options = try req.query.decode(QueryOptions.self)
		let particpantArrayFieldName = PersonalEvent().$participantArray.key.description

		let query = PersonalEvent.query(on: req.db).sort(\.$startTime, .ascending)
		if let _ = options.owned {
			req.logger.log(level: .debug, "Owner only")
			query.filter(\.$owner.$id == cacheUser.userID)
		}
		else if let _ = options.joined {
			req.logger.log(level: .debug, "Joined only")
			query.filter(.sql(unsafeRaw: "\(cacheUser.userID) = ANY(\"\(particpantArrayFieldName)\")"))
		}
		else {
			req.logger.log(level: .debug, "Owner and Joined")
			query.group(.or) { group in
				group.filter(\.$owner.$id == cacheUser.userID)
				group.filter(.sql(unsafeRaw: "'\(cacheUser.userID)' = ANY(\"\(particpantArrayFieldName)\")"))
			}
		}
		let events = try await query.all()
        return try await buildPersonalEventDataList(events, on: req)
	}

	/// `POST /api/v3/personalevents/create`
	/// 
	/// Create a new PersonalEvent.
	/// 
	/// - Parameter requestBody: `FezContentData` payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: 201 Created; `FezData` containing the newly created fez.
	func personalEventCreateHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let data: PersonalEventContentData = try ValidatingJSONDecoder().decode(PersonalEventContentData.self, fromBodyOf: req)

		let favorites = try await UserFavorite.query(on: req.db).filter(\.$favorite.$id == cacheUser.userID).all()
		let favoritesUserIDs = try favorites.map({ try $0.user.requireID() })
		try data.participants.forEach { userID in 
			if (!favoritesUserIDs.contains(userID)) {
				throw Abort(.forbidden, reason: "Cannot have a participant who has not favorited you.")
			}
		}

		let personalEvent = PersonalEvent(data, cacheOwner: cacheUser)
		try await personalEvent.save(on: req.db)
		let personalEventData = try buildPersonalEventData(personalEvent, on: req)

		// Return with 201 status
		let response = Response(status: .created)
		try response.content.encode(personalEventData)
		return response
	}

	/// `POST /api/v3/personalevents/:eventID/delete`
	/// `DELETE /api/v3/personalevents/:eventID`
	/// 
	/// Deletes the given `PersonalEvent`.
	/// 
	/// - Parameter eventID: in URL path.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func personalEventDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let personalEvent = try await PersonalEvent.findFromParameter(personalEventIDParam, on: req)
		try cacheUser.guardCanModifyContent(personalEvent)
		// try await fez.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		try await personalEvent.delete(on: req.db)
		return .noContent
	}
}

// MARK: Utility Functions
extension PersonalEventController {
	/// Builds a `PersonalEventData` from a `PersonalEvent`.
	func buildPersonalEventData(_ personalEvent: PersonalEvent, on: Request) throws -> PersonalEventData {
		let ownerHeader = try on.userCache.getHeader(personalEvent.$owner.id)
		let participantHeaders = on.userCache.getHeaders(personalEvent.participantArray)
		return try PersonalEventData(personalEvent, ownerHeader: ownerHeader, participantHeaders: participantHeaders)
	}

	/// Builds an array of `PersonalEventData` from the given `PersonalEvent`s.
	func buildPersonalEventDataList(_ personalEvents: [PersonalEvent], on: Request) async throws -> [PersonalEventData]
	{
		return try personalEvents.map { event in
			try buildPersonalEventData(event, on: on)
		}
	}
}

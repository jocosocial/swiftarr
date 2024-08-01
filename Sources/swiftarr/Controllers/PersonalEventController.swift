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
		tokenAuthGroup.get(personalEventIDParam, use: personalEventHandler)
		tokenAuthGroup.post(personalEventIDParam, use: personalEventUpdateHandler)
		tokenAuthGroup.post(personalEventIDParam, "update", use: personalEventUpdateHandler)
		tokenAuthGroup.post(personalEventIDParam, "delete", use: personalEventDeleteHandler)
		tokenAuthGroup.delete(personalEventIDParam, use: personalEventDeleteHandler)

		tokenAuthGroup.post(personalEventIDParam, "user", userIDParam, "remove", use: personalEventUserRemoveHandler)
		tokenAuthGroup.delete(personalEventIDParam, "user", userIDParam, use: personalEventUserRemoveHandler)

		tokenAuthGroup.post(personalEventIDParam, "report", use: personalEventReportHandler)
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
	/// - ?owned=BOOLEAN    Returns events only that the user has created. Mutually exclusive with joined.
	/// - ?joined=BOOLEAN   Returns events only that the user has joined. Mutually exclusive with owned.
	///
	/// The day and date parameters actually return events from 3AM local time on the given day until 3AM the next day--some events start after midnight and tend to get lost by those
	/// looking at daily schedules.
	///
	/// - Returns: An array of `PersonalEeventData` containing the `PersonalEvent`s.
	func personalEventsHandler(_ req: Request) async throws -> [PersonalEventData] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		struct QueryOptions: Content {
			var cruiseday: Int?
			var search: String?
			var owned: Bool?
			var joined: Bool?
		}
		let options: QueryOptions = try req.query.decode(QueryOptions.self)
		if let _ = options.owned, let _ = options.joined {
			throw Abort(.badRequest, reason: "Cannot specify both parameters 'joined' and 'owned'.")
		}
		let particpantArrayFieldName = PersonalEvent().$participantArray.key.description

		let query = PersonalEvent.query(on: req.db).sort(\.$startTime, .ascending)

		if let _ = options.owned {
			query.filter(\.$owner.$id == cacheUser.userID)
		}
		else if let _ = options.joined {
			query.filter(.sql(unsafeRaw: "\'\(cacheUser.userID)\' = ANY(\"\(particpantArrayFieldName)\")"))
		}
		else {
			query.group(.or) { group in
				group.filter(\.$owner.$id == cacheUser.userID)
				group.filter(.sql(unsafeRaw: "'\(cacheUser.userID)' = ANY(\"\(particpantArrayFieldName)\")"))
			}
		}

		if let cruiseday = options.cruiseday {
			let portCalendar = Settings.shared.getPortCalendar()
			let cruiseStartDate = Settings.shared.cruiseStartDate()
			// This is close to Events, but not quite.
			// https://github.com/jocosocial/swiftarr/issues/230
			let searchStartTime = portCalendar.date(byAdding: .day, value: cruiseday, to: cruiseStartDate)
			let searchEndTime = portCalendar.date(byAdding: .day, value: cruiseday + 1, to: cruiseStartDate)
			if let start = searchStartTime, let end = searchEndTime {
				query.filter(\.$startTime >= start).filter(\.$startTime < end)
			}
		}

		if var search = options.search {
			// postgres "_" and "%" are wildcards, so escape for literals
			search = search.replacingOccurrences(of: "_", with: "\\_")
			search = search.replacingOccurrences(of: "%", with: "\\%")
			search = search.trimmingCharacters(in: .whitespacesAndNewlines)
			query.fullTextFilter(\.$title, search)  // This is also getting description...
		}

		let events = try await query.all()
		return try await buildPersonalEventDataList(events, on: req)
	}

	/// `POST /api/v3/personalevents/create`
	///
	/// Create a new PersonalEvent.
	///
	/// - Parameter requestBody: `PersonalEventContentData` payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: 201 Created; `PersonalEventData` containing the newly created event.
	func personalEventCreateHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let data: PersonalEventContentData = try ValidatingJSONDecoder()
			.decode(PersonalEventContentData.self, fromBodyOf: req)

		let favorites = try await UserFavorite.query(on: req.db).filter(\.$favorite.$id == cacheUser.userID).all()
		let favoritesUserIDs = favorites.map({ $0.$user.id })
		try data.participants.forEach { userID in
			if !favoritesUserIDs.contains(userID) {
				throw Abort(.forbidden, reason: "Cannot have a participant who has not favorited you.")
			}
		}

		let personalEvent = PersonalEvent(data, cacheOwner: cacheUser)
		try await personalEvent.save(on: req.db)
		let personalEventData = try buildPersonalEventData(personalEvent, on: req)

		// @TODO generate socket notifications for participants
		// @TODO add next private event to UND

		// Return with 201 status
		let response = Response(status: .created)
		try response.content.encode(personalEventData)
		return response
	}

	/// `GET /api/v3/personalevents/:eventID`
	///
	/// Get a single `PersonalEvent`.
	///
	/// - Throws: 403 error if you're not allowed.
	/// - Returns: `PersonalEventData` containing the event.
	func personalEventHandler(_ req: Request) async throws -> PersonalEventData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let personalEvent = try await PersonalEvent.findFromParameter(personalEventIDParam, on: req)
		guard personalEvent.$owner.id == cacheUser.userID || cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "You cannot access this personal event.")
		}
		return try buildPersonalEventData(personalEvent, on: req)
	}

	/// `POST /api/v3/personalevents/:eventID`
	///
	/// Updates an existing `PersonalEvent`.
	/// Note: All fields in the supplied `PersonalEventContentData` must be filled, just as if the event
	/// were being created from scratch.
	///
	/// - Parameter requestBody: `PersonalEventContentData` payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: `PersonalEventData` containing the updated event.
	func personalEventUpdateHandler(_ req: Request) async throws -> PersonalEventData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let personalEvent = try await PersonalEvent.findFromParameter(personalEventIDParam, on: req)
		let data: PersonalEventContentData = try ValidatingJSONDecoder()
			.decode(PersonalEventContentData.self, fromBodyOf: req)

		let favorites = try await UserFavorite.query(on: req.db).filter(\.$favorite.$id == cacheUser.userID).all()
		let favoritesUserIDs = favorites.map { $0.$user.id }
		try data.participants.forEach { userID in
			if !favoritesUserIDs.contains(userID) {
				throw Abort(.forbidden, reason: "Cannot have a participant who has not favorited you.")
			}
		}

		personalEvent.title = data.title
		personalEvent.description = data.description
		personalEvent.startTime = data.startTime
		personalEvent.endTime = data.endTime
		personalEvent.location = data.location
		personalEvent.participantArray = data.participants
		try await personalEvent.save(on: req.db)

		// @TODO generate socket notifications for participants
		// @TODO add next private event to UND
		// @TODO generate notifications for newly added participants

		return try buildPersonalEventData(personalEvent, on: req)

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
		try await personalEvent.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		// @TODO add next private event to UND
		try await personalEvent.delete(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/personalevents/:eventID/user/:userID/delete`
	/// `DELETE /api/v3/personalevents/:eventID/user/:userID`
	///
	/// Removes a `User` from the `PersonalEvent`.
	/// Intended to be called by the `User` if they do not want to see this event.
	///
	/// - Parameter eventID: in URL path.
	/// - Parameter userID: in the URL path.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func personalEventUserRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let personalEvent = try await PersonalEvent.findFromParameter(personalEventIDParam, on: req)
		let removeUser = try await User.findFromParameter(userIDParam, on: req)
		guard
			personalEvent.$owner.id == cacheUser.userID || personalEvent.participantArray.contains(cacheUser.userID)
				|| cacheUser.accessLevel.hasAccess(.moderator)
		else {
			throw Abort(.forbidden, reason: "You cannot access this personal event.")
		}
		personalEvent.participantArray.removeAll { $0 == removeUser.id }
		try await personalEvent.save(on: req.db)
		try await personalEvent.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
		return .noContent
	}

	/// `POST /api/v3/personalevents/:eventID/report`
	///
	/// Creates a `Report` regarding the specified `PersonalEvent`.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter eventID: in URL path, the PersonalEvent ID to report.
	/// - Parameter requestBody: `ReportData`
	/// - Returns: 201 Created on success.
	func personalEventReportHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let reportedEvent = try await PersonalEvent.findFromParameter(personalEventIDParam, on: req)
		return try await reportedEvent.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
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

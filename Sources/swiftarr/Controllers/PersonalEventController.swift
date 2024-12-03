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
		tokenAuthGroup.get(fezIDParam, use: personalEventHandler)
		tokenAuthGroup.post(fezIDParam, use: personalEventUpdateHandler)
		tokenAuthGroup.post(fezIDParam, "update", use: personalEventUpdateHandler)
		tokenAuthGroup.post(fezIDParam, "delete", use: personalEventDeleteHandler)
		tokenAuthGroup.delete(fezIDParam, use: personalEventDeleteHandler)

		tokenAuthGroup.post(fezIDParam, "user", userIDParam, "remove", use: personalEventUserRemoveHandler)
		tokenAuthGroup.delete(fezIDParam, "user", userIDParam, use: personalEventUserRemoveHandler)

		tokenAuthGroup.post(fezIDParam, "report", use: personalEventReportHandler)
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
	/// - ?search=STRING    Returns events whose title or description contain the given string.
	/// - ?owned=BOOLEAN    Returns events only that the user has created. Mutually exclusive with joined.
	/// - ?joined=BOOLEAN   Returns events only that the user has joined. Mutually exclusive with owned.
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
		if  options.owned == true, options.joined == true {
			throw Abort(.badRequest, reason: "Cannot specify both parameters 'joined' and 'owned'.")
		}
		let fezList = try await options.owned == true ? FezController().ownerHandler(req) : FezController().joinedHandler(req)
		let events = try fezList.fezzes.compactMap {
			options.joined == true && $0.owner.userID == cacheUser.userID ? nil : try PersonalEventData($0, request: req) 
		}
		return events
	}

	/// `POST /api/v3/personalevents/create`
	///
	/// Create a new PersonalEvent.
	///
	/// - Parameter requestBody: `PersonalEventContentData` payload in the HTTP body.
	/// - Throws: 400 error if the supplied data does not validate.
	/// - Returns: 201 Created; `PersonalEventData` containing the newly created event.
	func personalEventCreateHandler(_ req: Request) async throws -> Response {
		let requestContent = try ValidatingJSONDecoder().decode(PersonalEventContentData.self, fromBodyOf: req)
		let inputData = FezContentData(privateEvent: requestContent)
		let processedData = try await FezController().createChat(req, data: inputData)
		let personalEventData = try PersonalEventData(processedData, request: req)

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
		let apptData = try await FezController().fezHandler(req)
		return try PersonalEventData(apptData, request: req)
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
		let requestContent = try ValidatingJSONDecoder().decode(PersonalEventContentData.self, fromBodyOf: req)
		let inputData = FezContentData(privateEvent: requestContent)
		let processedData = try await FezController().updateChat(req, data: inputData)
		let personalEventData = try PersonalEventData(processedData, request: req)
		return personalEventData
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
		let lfgData = try await FezController().cancelHandler(req)
		if lfgData.fezType == .personalEvent {
			return try await FezController().fezDeleteHandler(req)
		}
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
		let removingUserID = req.parameters.get(userIDParam.paramString, as: UUID.self)
		if cacheUser.userID == removingUserID {
			_ = try await FezController().unjoinHandler(req)
		}
		else {
			_ = try await FezController().userRemoveHandler(req)
		}
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
		return try await FezController().reportFezHandler(req)
	}
}

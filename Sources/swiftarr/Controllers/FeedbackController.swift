import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/feedback/*` route endpoints and handler functions related
/// to shadow event feedback surveys. These surveys are for the organizers of shadow events to report 
/// back to THO how their event went.

struct EventFeedbackController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
	
		// convenience route group for all /api/v3/users endpoints
		let feedbackRoutes = app.grouped("api", "v3", "feedback")

		// endpoints available only when logged in
		let tokenAuthGroup = feedbackRoutes.tokenRoutes(feature: .eventFeedback)
		tokenAuthGroup.get("id", eventIDParam, use: getFeedbackFromID)
		tokenAuthGroup.get("uid", eventUIDParam, use: getFeedbackFromUID)
		tokenAuthGroup.get("eventlist", use: getEventList)
		tokenAuthGroup.post(use: createFeedback)
		
		let ttAuthGroup = app.grouped("api", "v3", "admin", "feedback").tokenRoutes(feature: .eventFeedback, minAccess: .twitarrteam)
		ttAuthGroup.get("roomlist", use: getRoomList)
		ttAuthGroup.get("reports", use: getFeedbackReports)
		ttAuthGroup.get("stats", use: getFeedbackStats)
		ttAuthGroup.get("report", feedbackIDParam, use: getFeedbackReport)
		ttAuthGroup.post("report", feedbackIDParam, "mark", use: markFeedbackActionable)
		ttAuthGroup.delete("report", feedbackIDParam, "mark", use: removeFeedbackActionable)
		ttAuthGroup.post("report", feedbackIDParam, "unmark", use: removeFeedbackActionable)
	}
	
	// MARK: - tokenAuthGroup Handlers (logged in)
	
	/// `GET /api/v3/feedback/eventlist`
	/// 
	/// Returns EventData for events upon which the user could submit feedback. 
	/// 
	/// **URL Query Parameters:**
	/// - room=STRING		If present, fills in the `matchingRoom` member of the returned struct with events with
	/// 					STRING as prefix for their room name
	///
	/// - Returns: `EventFeedbackSelectionData`
	func getEventList(_ req: Request) async throws -> EventFeedbackSelectionData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let performer = try await Performer.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first()
		let roomName = req.query[String.self, at: "room"]?.lowercased(with: .current)
		// Events are stored as 'floating' times in the portTimeZone. So, filtering against dates calculated in portTimeZone
		// should do the right thing, even when the dates are then adjusted to the current TZ for delivery.
		let currentPortTime = Settings.shared.timeZoneChanges.displayTimeToPortTime(Date())
		// 
		let query = Event.query(on: req.db)
				.filter(\.$eventType ~~ [.shadow, .workshop])
				.filter(\.$startTime <= currentPortTime)
				.sort(\.$startTime, .descending)
				// Left joins Feedback records this user posted for this this event
				.joinOptionalWithFilter(method: .left, from: \.$id, to: \EventFeedback.$event.$id, otherFilters: 
				[.value(.path(EventFeedback.path(for: \.$author.$id), schema: EventFeedback.schema), .equal, .bind(cacheUser.userID))])
				// Left joins EventFavorites this user has for this event
				.joinWithFilter(method: .left, from: \.$id, to: \EventFavorite.$event.$id, otherFilters: 
				[.value(.path(EventFavorite.path(for: \.$user.$id), schema: EventFavorite.schema), .equal, .bind(cacheUser.userID))])
		if let perf = performer {
				query.joinWithFilter(method: .left, from: \.$id, to: \EventPerformer.$event.$id, otherFilters: 
				[.value(.path(EventPerformer.path(for: \.$performer.$id), schema: EventPerformer.schema), .equal, .bind(perf.id))])
		}
		let allEvents = try await query.all()
		var result = EventFeedbackSelectionData()
		for event in allEvents {
			let eventData: EventData = try EventData(event, isFavorite: (try? event.joined(EventFavorite.self)) != nil)
			if (try? event.joined(EventFeedback.self)) != nil {
				result.existingFeedback.append(eventData)
			}
			if performer != nil, (try? event.joined(EventPerformer.self)) != nil {
				result.performerAttached.append(eventData)
			}
			if let room = roomName, event.location.lowercased().hasPrefix(room) {
				result.matchingRoom.append(eventData)
			}
			result.events.append(eventData)
		}
		return result
	}

	/// `GET /api/v3/feedback/id/:event_id`
	/// 
	/// Gets any existing feedback the current user has posted for for the given event. Here, the event ID is the 
	/// Twitarr database ID for the event. 
	func getFeedbackFromID(_ req: Request) async throws -> EventFeedbackReport {
		guard let idString = req.parameters.get(eventIDParam.paramString), let eventID = UUID(uuidString: idString) else {
			throw Abort(.badRequest, reason: "Request parameter \(eventIDParam) is missing.")
		}
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let feedback = try await EventFeedback.query(on: req.db)
				.filter(\.$event.$id == eventID)
				.filter(\.$author.$id == cacheUser.userID)
				.first() else {
			throw Abort(.noContent)
		}
		return try EventFeedbackReport(feedback, author: cacheUser.makeHeader())
	}
	
	/// `GET /api/v3/feedback/uid/:event_uid`
	/// 
	/// Gets any existing feedback the current user has posted for for the given event. `Event_UID` comes from
	/// Sched's .ics output, is unique per event, and follows the event as it gets passed around (unlike the ID,
	/// which is specific to our databse). This could be used to mass-email hosts before sailing, giving them a 
	/// link to their event's feedback form.
	func getFeedbackFromUID(_ req: Request) async throws -> EventFeedbackReport {
		guard let eventUID = req.parameters.get(eventUIDParam.paramString)  else {
			throw Abort(.badRequest, reason: "Request parameter \(eventUIDParam) is missing.")
		}
		guard let event = try await Event.query(on: req.db).filter(\.$uid == eventUID).first() else {
			throw Abort(.badRequest, reason: "No event found with UID \(eventUIDParam).")
		}
		let cacheUser = try req.auth.require(UserCacheData.self)
		var response : EventFeedbackReport
		if let feedback = try await EventFeedback.query(on: req.db)
				.join(Event.self, on: \Event.$id == \EventFeedback.$event.$id)
				.filter(Event.self, \Event.$uid == eventUID)
				.filter(\.$author.$id == cacheUser.userID)
				.first() {
			response = try EventFeedbackReport(feedback, author: cacheUser.makeHeader())
		}
		else {
			guard let user = try await User.query(on: req.db).filter(\.$id == cacheUser.userID).first() else {
				throw Abort(.badRequest, reason: "No User found with ID \(cacheUser.userID). How do we have a userHeader for this?")
			}
			response = try EventFeedbackReport(author: cacheUser.makeHeader(), event: event, realName: user.realName)
		}
		return response
	}
	
	/// `POST /api/v3/feedback`
	/// 
	/// Saves or updates host feedback about a shadow event. Currently, the feedback must reference an event on the
	/// public schedule. The feedback is tied to the current user and uniqued per user/event pair.
	/// 
	/// - Parameter EventFeedbackData: JSON in request body
	/// - Returns: 200 OK if feedback was saved/updated.
	func createFeedback(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()
		let data = try ValidatingJSONDecoder().decode(EventFeedbackData.self, fromBodyOf: req)
		// Currently all feedback must be tied to an event on the public schedule. Could change in the future
		guard let eventUID = data.eventUID else {
			throw Abort(.badRequest, reason: "Feedback must be tied to an event on the public schedule.")
		}
		guard let event = try await Event.query(on: req.db).filter((\.$uid == eventUID)).first() else {
			throw Abort(.notFound, reason: "Event with UID \(eventUID) not found.")
		}
		let feedback = try await EventFeedback.query(on: req.db).filter(\.$event.$id == event.id)
				.filter(\.$author.$id == cacheUser.userID).first() ?? EventFeedback()
		try feedback.update(event: event, author: cacheUser, feedback: data)
		try await feedback.save(on: req.db)
		return .created
	}
	
	// MARK: - ttAuthGroup Handlers (TwitarrTeam and above)
	
	/// `GET /api/v3/admin/feedback/roomlist`
	/// 
	/// Returns a list of all room names that are listed as the location of a Shadow or Workshop event on the official
	/// schedule.
	func getRoomList(_ req: Request) async throws -> [String] {
		var eventLocations = try await Event.query(on: req.db)
				.filter(\.$eventType ~~ [ .shadow, .workshop])
				.unique().all(\.$location)
		eventLocations = eventLocations.map { 
			$0.prefix(while: { !",(".contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines) 
		}
		return eventLocations
	}
	
	/// `GET /api/v3/admin/feedback/reports`
	/// 
	/// Returns all feedback reports that have been filed, sorted by descending update time. 
	/// This usually means 'most recent first', but editing an existing report bumps it to the top.
	func getFeedbackReports(_ req: Request) async throws -> [EventFeedbackReport] {
		let feedback = try await EventFeedback.query(on: req.db).sort(\.$updatedAt, .descending)
				.join(Event.self, on: \Event.$id == \EventFeedback.$event.$id, method: .left)
				.join(from: Event.self, parent: \Event.$forum, method: .left).all()
		let events = try feedback.map { try $0.joined(Event.self) }
		let followCounts = try await events.childCountsPerModel(atPath: \.$favorites.$pivots, on: req.db)
		let forums = try feedback.map { try $0.joined(Forum.self) }
		let adminUserID = req.userCache.getUser(username: "admin")?.userID 
		let postCounts = try await forums.childCountsPerModel(atPath: \.$posts, on: req.db, sqlFilter: { builder in
			if let adminUserID = adminUserID {
				builder.where(SQLColumn("author"), .notEqual, SQLLiteral.string(adminUserID.uuidString))
			}
		})
		let result = try feedback.map {
			let authorHeader = try req.userCache.getHeader($0.$author.id)
			var report =  try EventFeedbackReport($0, author: authorHeader)
			report.adminFields = .init()
			if let eventID = $0.$event.id {
				report.adminFields?.actionable = $0.actionable
				report.adminFields?.followCount = followCounts[eventID] ?? 0
				if let event = events.first(where: { $0.id == eventID }), let forumID = event.$forum.id {
					report.adminFields?.forumID = forumID
					report.adminFields?.forumPostCount = postCounts[forumID] ?? 0
				}
			}
			return report
		}
		return result
	}
	
	/// `GET /api/v3/admin/feedback/report/:report_id`
	/// 
	/// Returns all feedback reports that have been filed, sorted by descending update time. 
	/// This usually means 'most recent first', but editing an existing report bumps it to the top.
	func getFeedbackReport(_ req: Request) async throws -> EventFeedbackReport {
		guard let idString = req.parameters.get(feedbackIDParam.paramString), let feedbackID = UUID(uuidString: idString) else {
			throw Abort(.badRequest, reason: "Request parameter \(feedbackIDParam) is missing.")
		}
		guard let feedback = try await EventFeedback.query(on: req.db).sort(\.$updatedAt, .descending)
				.join(Event.self, on: \Event.$id == \EventFeedback.$event.$id)
				.filter(\.$id == feedbackID)
				.first() else {
			throw Abort(.notFound, reason: "No feedback report found with id \(feedbackID).")
		}
		let authorHeader = try req.userCache.getHeader(feedback.$author.id)
		var report = try EventFeedbackReport(feedback, author: authorHeader)
		report.adminFields = .init()
		if let event = try? feedback.joined(Event.self) {
			report.adminFields?.followCount = try await event.$favorites.$pivots.query(on: req.db).count()
			if let forum = try await event.$forum.get(on: req.db) {
				report.adminFields?.actionable = feedback.actionable
				report.adminFields?.forumID = try forum.requireID()
				let postQuery = forum.$posts.query(on: req.db)
				if let adminUserID = req.userCache.getUser(username: "admin")?.userID {
					postQuery.filter(\.$author.$id != adminUserID)
				}
				report.adminFields?.forumPostCount = try await postQuery.count()
			}
		}
		return report
	}
		
	/// `GET /api/v3/admin/feedback/stats`
	/// 
	/// Returns statistics on shadow events and shadow event feedback reports.
	func getFeedbackStats(_ req: Request) async throws -> EventFeedbackStats {
		let totalEvents = try await Event.query(on: req.db).filter(\.$eventType ~~ [.shadow, .workshop]).count()
		let completedEvents = try await Event.query(on: req.db).filter(\.$eventType ~~ [.shadow, .workshop])
				.filter(\.$endTime < Date()).count()
		let totalFeedback = try await EventFeedback.query(on: req.db).count()
		let uniqueEventsWithFeedback = Set(try await EventFeedback.query(on: req.db).all(\.$event.$id)).count
		let stats = EventFeedbackStats(totalShadowEvents: totalEvents, completedShadowEvents: completedEvents,
				totalFeedbackReports: totalFeedback, uniqueEventsWithFeedback: uniqueEventsWithFeedback)
		return stats
	}
	
	/// `POST /api/v3/admin/feedback/report/:report_id/mark`
	///
	/// Mark the given report as containing something actionable. Actionable is a global flag attached to the report.
	/// Intended use case is that the reports manager can set this on reports that have actionable issues that need to be dealt with
	/// during the cruise, and clear it when the issue is resolved.
	///
	/// - Parameter report_id: in URL path
	/// - Returns: 201 Created on success; 200 OK if already marked.
	func markFeedbackActionable(_ req: Request) async throws -> HTTPStatus {
		let feedback = try await EventFeedback.findFromParameter(feedbackIDParam, on: req)
		if feedback.actionable {
			return .ok
		}
		feedback.actionable = true
		try await feedback.save(on: req.db)
		return .created
	}

	/// `POST /api/v3/admin/feedback/report/:report_id/unmark`
	///
	/// Clears 'actionable' status on a feedback report. Actionable is a global flag attached to the report.
	/// Intended use case is that the reports manager can set this on reports that have actionable issues that need to be dealt with
	/// during the cruise, and clear it when the issue is resolved.
	///
	/// - Parameter report_id: in URL path
	/// - Throws: 400 error if the event was not favorited.
	/// - Returns: 204 No Content on success; 200 OK if event is already not marked.
	func removeFeedbackActionable(_ req: Request) async throws -> HTTPStatus {
		let feedback = try await EventFeedback.findFromParameter(feedbackIDParam, on: req)
		if !feedback.actionable {
			return .ok
		}
		feedback.actionable = false
		try await feedback.save(on: req.db)
		return .noContent
	}
}

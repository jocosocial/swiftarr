import Vapor
import Crypto
import FluentSQL

// rcf Contents of this file are still being baked.
//
// What I want to try to do is make a single endpoint that returns server time, announcements,
// and user notifications, ideally with very low overhead. Perhaps we could just return "highest 
// announcement index #", and store notification numbers in UserCache? 
// That is, we'd store in UserCache that a user had 15 total @mentions, and clients could calc the # unseen.

/// The collection of alert endpoints, with routes for:
/// 	- getting server time,,
///		- getting public address-style announcements,,
///		- getting notifications on alertwords,
///		- getting notificaitons on incoming Fez messages.
struct AlertController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
        
		// convenience route group for all /api/v3/alert endpoints
		let alertRoutes = app.grouped("api", "v3", "notification")

		// Flexible access endpoints -- login not required, although calls may act differently if logged in
		let flexAuthGroup = addFlexAuthGroup(to: alertRoutes)
		flexAuthGroup.get("global", use: globalNotificationHandler)
		flexAuthGroup.get("user", use: globalNotificationHandler)
		flexAuthGroup.get("announcements", use: getAnnouncements)
		flexAuthGroup.get("dailythemes", use: getDailyThemes)

		// endpoints available only when logged in
		let tokenAuthGroup = addTokenAuthGroup(to: alertRoutes)
		tokenAuthGroup.get("announcement", announcementIDParam, use: getSingleAnnouncement)

		tokenAuthGroup.post("announcement", "create", use: createAnnouncement)
		tokenAuthGroup.post("announcement", announcementIDParam, "edit", use: editAnnouncement)
		tokenAuthGroup.post("announcement", announcementIDParam, "delete", use: deleteAnnouncement)
		tokenAuthGroup.delete("announcement", announcementIDParam, use: deleteAnnouncement)

	}
	
	// MARK: - Notifications
		
    /// `GET /api/v3/notification/global`
    /// `GET /api/v3/notification/user`
    ///
    /// Retrieve info on the number of each type of notification supported by Swiftarr. 
	/// 
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:UserNotificationData>
	func globalNotificationHandler(_ req: Request) throws -> EventLoopFuture<UserNotificationData> {
        guard let user = req.auth.get(User.self) else {
			return Announcement.query(on: req.db).filter(\.$displayUntil > Date()).count().map { activeAnnouncements in
				var result = UserNotificationData()
				result.activeAnnouncementCount = activeAnnouncements
				return result
			}
        }
		// get user's taggedEvent barrel, and from it get next event being followed
		return user.getBookmarkBarrel(of: .taggedEvent, on: req).flatMap { barrel in
			guard let barrel = barrel else {
				return req.eventLoop.makeSucceededFuture(nil)
			}
			let cruiseStartDate = Settings.shared.cruiseStartDate
			var filterDate = Date()
			// If the cruise is in the future or more than 10 days in the past, construct a fake date during the cruise week
			let secondsPerDay = 24 * 60 * 60.0
			if cruiseStartDate.timeIntervalSinceNow > 0 ||
				cruiseStartDate.timeIntervalSinceNow < 0 - Double(Settings.shared.cruiseLengthInDays) * secondsPerDay {
				var filterDateComponents = Calendar.autoupdatingCurrent.dateComponents(in: TimeZone(abbreviation: "EST")!, 
						from: cruiseStartDate)
				let currentDateComponents = Calendar.autoupdatingCurrent.dateComponents(in: TimeZone(abbreviation: "EST")!, 
						from: Date())
				filterDateComponents.hour = currentDateComponents.hour
				filterDateComponents.minute = currentDateComponents.minute
				filterDateComponents.second = currentDateComponents.second
				filterDate = Calendar.autoupdatingCurrent.date(from: filterDateComponents) ?? Date()
				if let currentDayOfWeek = currentDateComponents.weekday {
					let daysToAdd = (7 + currentDayOfWeek - Settings.shared.cruiseStartDayOfWeek) % 7 
					if let adjustedDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: daysToAdd, to: filterDate) {
						filterDate = adjustedDate
					}
				}
			}			
			return Event.query(on: req.db).filter(\.$id ~~ barrel.modelUUIDs)
					.filter(\.$startTime > filterDate)
					.sort(\.$startTime, .ascending)
					.first()
					.map { event in
				return event?.startTime
			}
		}.flatMap { (nextEventDate: Date?) in
			// Get the number of fezzes with unread messages
			return user.$joined_fezzes.$pivots.query(on: req.db).with(\.$fez).all().flatMap { pivots in
				var unreadFezCount = 0
				var unreadSeamailCount = 0
				pivots.forEach { fezParticipant in
					if fezParticipant.fez.postCount - fezParticipant.readCount - fezParticipant.hiddenCount > 0 {
						if fezParticipant.fez.fezType == .closed {
							unreadSeamailCount += 1
						}
						else {
							unreadFezCount += 1
						}
					}
				}
				return Announcement.query(on: req.db)
						.field(\.$id)
						.filter(\.$displayUntil > Date())
						.all().map { actives in
					let newAnnouncements = actives.reduce(0) { ($1.id ?? 0) > user.lastReadAnnouncement ? $0 + 1 : $0 }
					return UserNotificationData(user: user, newFezCount: unreadFezCount, newSeamailCount: unreadSeamailCount,
							newAnnouncementCount: newAnnouncements, activeAnnouncementCount: actives.count, nextEvent: nextEventDate,
							disabledFeatures: [])
				}
			}
		}
	}
	
	// MARK: - Announcements

    /// `POST /api/v3/announcement/create`
    ///
    /// Create a new announcement. Requires THO access and above. When a new announcement is created the notification endpoints will start 
	/// indicating the new announcement to all users.
	/// 
    /// - Parameter requestBody: <doc:AnnouncementCreateData>
    /// - Returns: `HTTPStatus` 201 on success.
	func createAnnouncement(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
		let announcementData = try ValidatingJSONDecoder().decode(AnnouncementCreateData.self, fromBodyOf: req)
		let announcement = try Announcement(author: user, text: announcementData.text, displayUntil: announcementData.displayUntil)
		return announcement.save(on: req.db).transform(to: .created)
	}
	
    /// `GET /api/v3/notification/announcements`
    ///
    /// Returns all active announcements, sorted by creation time, by default. 
	/// 
	/// **URL Query Parameters**
	/// 
	/// - `?inactives=true` Also return expired and deleted announcements. THO and admins only. 
	/// 		
	/// The purpose if the inactives flag is to allow for finding an expired announcement and re-activating it by changing its expire time. Remember that doing so
	/// doesn't re-alert users who have already read it.
    ///
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: Array of <doc:AnnouncementData>
	func getAnnouncements(_ req: Request) throws -> EventLoopFuture<[AnnouncementData]> {
		let user = req.auth.get(User.self)
		let includeInactives: Bool = req.query[String.self, at: "inactives"] == "true"
		guard !includeInactives || (user?.accessLevel.hasAccess(.tho) ?? false) else {
			throw Abort(.forbidden, reason: "Inactive announcements are THO only")
		}
		let query = Announcement.query(on: req.db).sort(\.$id, .descending)
		if includeInactives {
			query.withDeleted()
		}
		else {
			query.filter(\.$displayUntil > Date())
		}
		return query.all().flatMapThrowing { announcements in
			let result: [AnnouncementData] = try announcements.map { 
				let authorHeader = try req.userCache.getHeader($0.$author.id)
				return try AnnouncementData(from: $0, authorHeader: authorHeader) 
			}
			return result
		}
	}
	
    /// `GET /api/v3/notification/announcement/ID`
    ///
    /// Returns a single announcement, identified by its ID. THO and admins only. . 
	/// 
    /// - Parameter announcementID: The announcement to find
    /// - Throws: 403 error if the user doesn't have THO-level access. 404 if no announcement with the given ID is found.
    /// - Returns: <doc:AnnouncementData>
	func getSingleAnnouncement(_ req: Request) throws -> EventLoopFuture<AnnouncementData> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
  		guard let paramVal = req.parameters.get(announcementIDParam.paramString), let announcementID = Int(paramVal) else {
            throw Abort(.badRequest, reason: "Request parameter \(announcementIDParam.paramString) is missing.")
        }
		return Announcement.query(on: req.db).filter(\.$id == announcementID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "Announcement not found")).flatMapThrowing { announcement in
			let authorHeader = try req.userCache.getHeader(announcement.$author.id)
			return try AnnouncementData(from: announcement, authorHeader: authorHeader) 
		}
	}
	
    /// `POST /api/v3/notification/announcement/ID/edit`
    ///
    /// Edits an existing announcement. Editing a deleted announcement will un-delete it. Editing an announcement does not change any user's notification status for that
	/// announcement: if a user has seen the announcement already, editing it will not cause the user to be notified that they should read it again.
    ///
    /// - Parameter announcementID: The announcement to edit. Must exist.
    /// - Parameter requestBody: <doc:AnnouncementCreateData>
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: The updated <doc:AnnouncementCreateData>
	func editAnnouncement(_ req: Request) throws -> EventLoopFuture<AnnouncementData> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
		let announcementData = try ValidatingJSONDecoder().decode(AnnouncementCreateData.self, fromBodyOf: req)
		guard let announcementIDStr = req.parameters.get(announcementIDParam.paramString), let announcementID = Int(announcementIDStr) else {
			throw Abort(.badRequest, reason: "Announcement ID is missing.")
		}
		return Announcement.query(on: req.db).filter(\.$id == announcementID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "Announcement not found.")).throwingFlatMap { announcement in
			if let deleteTime = announcement.deletedAt, deleteTime < Date() {
				return announcement.restore(on: req.db).transform(to: announcement)
			}
			return req.eventLoop.future(announcement)
		}.flatMap { (announcement: Announcement) in
			announcement.text = announcementData.text
			announcement.displayUntil = announcementData.displayUntil
			return announcement.save(on: req.db).flatMapThrowing {
				let authorHeader = try req.userCache.getHeader(announcement.$author.id)
				return try AnnouncementData(from: announcement, authorHeader: authorHeader)
			}
		}
	}
	
    /// `POST /api/v3/notification/announcement/ID/delete`
    /// `DELETE /api/v3/notification/announcement/ID`
    ///
    /// Deletes an existing announcement. Editing a deleted announcement will un-delete it.
    ///
    /// - Parameter announcementIDParam: The announcement to delete. 
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 NoContent on success.
	func deleteAnnouncement(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
		return Announcement.findFromParameter(announcementIDParam, on: req).throwingFlatMap { announcement in
			announcement.delete(on: req.db).transform(to: .noContent)
		}
	}
	
	// MARK: - Daily Themes

    /// `GET /api/v3/notification/dailythemes`
	/// 
	///  Returns information about all the daily themes currently registered.
    ///
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: An array of <doc:DailyThemeData> on success.
	func getDailyThemes(_ req: Request) throws -> EventLoopFuture<[DailyThemeData]> {
		return DailyTheme.query(on: req.db).sort(\.$cruiseDay, .ascending).all().flatMapThrowing { themes in
			return try themes.map { try DailyThemeData($0) }
		}
	}
}

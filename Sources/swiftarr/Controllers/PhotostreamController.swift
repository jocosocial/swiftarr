import Fluent
import FluentSQL
import Vapor

struct PhotostreamController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		// convenience route group for all /api/v3/photostream endpoints
		let photoRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .photostream)).grouped("api", "v3", "photostream")

		// Photostream Route Group, requires token
		let tokenAuthGroup = photoRoutes.addTokenAuthRequirement()
		tokenAuthGroup.get("", use: photostreamHandler)
		tokenAuthGroup.get("placenames", use: getPlacenames)
		tokenAuthGroup.post("upload", use: photostreamUploadHandler)
		tokenAuthGroup.post("report", streamPhotoIDParam, use: photostreamReportHandler)

		let modRoutes = app.grouped("api", "v3", "mod", "photostream").addTokenAuthRequirement().grouped(RequireModeratorMiddleware())
		modRoutes.get(streamPhotoIDParam, use: getPhotoModerationData)		
		modRoutes.post(streamPhotoIDParam, "delete", use: modDeleteStreamPhoto)		
		modRoutes.delete(streamPhotoIDParam, use: modDeleteStreamPhoto)		
	}
	
	/// `GET /api/v3/photostream`
	/// 
	/// For regular users, returns the last 30 photos uploaded to the photostream, in descending order. Moderators can use  the start and limit parameters to 
	/// page through all the photos. For non-moderators, the pagination struct will always indicate 30 photos or fewer, on one page.
	/// 
	/// I'm limitiing pagination to mods because Photostream is supposed to be a sort of snapshot of what's going on on the boat right now. This may change in the future.
	/// 
	/// **URL Query Parameters:**
	/// * `?start=INT` - Moderators only. The index into the sorted list of photos to start returning results. 0 for most recent photo.
	/// * `?limit=INT` - Moderators only. The max # of entries to return. Defaults to 30.
	/// 
	/// - Returns: `PhotostreamListData`, a paginated array of `PhotostreamImageData`
	func photostreamHandler(_ req: Request) async throws -> PhotostreamListData {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel != .banned else {
			throw Abort(.unauthorized, reason: "User is banned, and cannot access this resource.")
		}
		var start = 0
		var limit = 30
		var photoCount = 0
		if user.accessLevel.hasAccess(.moderator) {
			start = req.query[Int.self, at: "start"] ?? 0
			limit = req.query[Int.self, at: "limit"] ?? 30
			photoCount = try await StreamPhoto.query(on: req.db).filter(\.$moderationStatus !~ [.autoQuarantined, .quarantined]).count()
		}
		let photos = try await StreamPhoto.query(on: req.db).filter(\.$moderationStatus !~ [.autoQuarantined, .quarantined])
				.sort(\.$id, .descending).offset(start).limit(limit).with(\.$atEvent).all()
		let imageData = try photos.map { 
			let authorHeader = try  req.userCache.getHeader($0.$author.id)
			return try PhotostreamImageData(streamPhoto: $0, author: authorHeader) 
		}
		if photoCount == 0 {
			photoCount = imageData.count
		}
		return PhotostreamListData(photos: imageData, paginator: Paginator(total: photoCount, start: start, limit: limit))
	}
	
	/// `GET /api/v3/photostream/placenames`
	/// 
	/// Returns a list of currently-valid placenames that can be used to tag a photo. This list includes events currently happening as well as a few
	/// general ship locations. These values are valid to be returned to `/api/v3/photostream/upload`.  Note that this means the result of this call is ephermal
	/// and will change as events end and new ones start. Similar to how the  'now' functionality works in Schedule, long-running 'events' are filtered out (e.g. "Cosplay Day", running
	/// from 8:00 AM to mindnight).
	/// 
	/// - Returns: `PhotostreamLocationData` contining currently-running events and general boat placenames.
	func getPlacenames(_ req: Request) async throws -> PhotostreamLocationData {
		return try await getPlacenameList(req, forValidation: false)
	}
	
	/// `POST /api/v3/photostream/upload`
	/// 
	/// Adds the given photo to the photostream. To be valid, either the eventID or the placename should be non-nil, and should equal a value recently returned from
	/// `/api/v3/photostream/placenames`.
	/// 
	/// - Parameter `PhotostreamUploadData`: In the request body.
	/// - Returns: 200 OK if upload successful.
	func photostreamUploadHandler(_ req: Request) async throws -> Response {
		let user = try req.auth.require(UserCacheData.self)
		try user.guardCanCreateContent(customErrorString: "user cannot post to photostream")
		if let userPrevPhoto = try await StreamPhoto.query(on: req.db).filter(\.$author.$id == user.userID).sort(\.$id, .descending).first(),
				userPrevPhoto.captureTime > Date() - Settings.shared.photostreamUploadRateLimit {
			throw Abort(.tooManyRequests, reason: "You may only upload one Photostream photo every \(Settings.shared.photostreamUploadRateLimit / 60) minutes.")
		}
		let newPostData = try ValidatingJSONDecoder().decode(PhotostreamUploadData.self, fromBodyOf: req)
		// The only valid place names are what getPlacenames returns
		let validPlaces = try await getPlacenameList(req, forValidation: true)
		var matchingEvent: Event? = nil
		var boatLocation: PhotoStreamBoatLocation? = nil
		if let uploadEventID = newPostData.eventID {
			guard validPlaces.events.contains(where: { $0.eventID == uploadEventID } ) else {
				throw Abort(.badRequest, reason: "Place tag for photo not in list of allowed tags. This can happen if you tag with an Event that's already ended.")
			}
			matchingEvent = try await Event.query(on: req.db).filter(\.$id == uploadEventID).first()
			guard matchingEvent != nil else {
				throw Abort(.badRequest, reason: "Couldn't find the event to tag this photo with.")
			}
		}
		else if let uploadPlacename = newPostData.locationName, validPlaces.locations.contains(uploadPlacename) {
			boatLocation = PhotoStreamBoatLocation.init(rawValue: uploadPlacename)
		}
		if boatLocation == nil && matchingEvent == nil {
			boatLocation = .onBoat
		}
		guard let filename = try await self.processImage(data: newPostData.image, usage: .photostream, on: req) else {
			throw Abort(.badRequest, reason: "Unable to process uploaded photo.")
		}
		let streamPhoto = StreamPhoto(image: filename, captureTime: newPostData.createdAt, user: user, atEvent: matchingEvent,
				boatLocation: boatLocation)
		try await streamPhoto.save(on: req.db)
		let response = Response(status: .ok)
		response.headers.add(name: "Retry-After", value: "\(Settings.shared.photostreamUploadRateLimit)")
		return response
	}
	
	/// `POST /api/v3/photostream/report/:photoID`
	///
	/// Create a `Report` regarding the specified `StreamPhoto`.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter requestBody:`ReportData`
	/// - Throws: 409 error if user has already reported the post.
	/// - Returns: 201 Created on success.
	func photostreamReportHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let photo = try await StreamPhoto.findFromParameter(streamPhotoIDParam, on: req)
		return try await photo.fileReport(submitter: cacheUser, submitterMessage: data.message, on: req)
	}
	
// MARK: Moderator

	/// `GET /api/v3/mod/photostream/:photo_id`
	/// 
	/// Moderator only. Returns a photo from the photostream, with associated data for moderation tasks.
	/// 
	/// - Returns: `PhotostreamModerationData` on success.
	func getPhotoModerationData(_ req: Request) async throws -> PhotostreamModerationData {
		let user = try req.auth.require(UserCacheData.self)
		if let quarantineEndDate = user.tempQuarantineUntil {
			guard Date() > quarantineEndDate else {
				throw Abort(.forbidden, reason: "User is temporarily quarantined and cannot modify content.")
			}
		}
		guard user.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "This method is moderator only.")
		}
		guard let paramVal = req.parameters.get(streamPhotoIDParam.paramString), let postID = Int(paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter \(streamPhotoIDParam.paramString) is missing.")
		}
		guard let photo = try await StreamPhoto.query(on: req.db).filter(\.$id == postID).withDeleted().with(\.$atEvent).first() else {
			throw Abort(.badRequest, reason: "Photo \(postIDParam.paramString) not found.")
		}
		let authorHeader = try req.userCache.getHeader(photo.$author.id)
		let reports = try await Report.query(on: req.db).filter(\.$reportType == .streamPhoto).filter(\.$reportedID == paramVal)
				.sort(\.$createdAt, .descending).all()
		let imageData = try PhotostreamImageData(streamPhoto: photo, author: authorHeader)
		var isDeleted = false
		if let deleteDate = photo.deletedAt, deleteDate < Date() {
			isDeleted = true
		}
		let reportData = try reports.map { try ReportModerationData(req: req, report: $0) }
		let result = PhotostreamModerationData(photo: imageData, isDeleted: isDeleted, moderationStatus: photo.moderationStatus, 
				reports: reportData)
		return result
	}
	
	/// `DELETE /api/v3/mod/photostream/:photo_id`
	/// `POST /api/v3/mod/photostream/:photo_id/delete`
	/// 
	/// Moderator only. Soft-deletes the given photo. The deleted phto may still be viewed by moderators, but will no longer be seen by normal users.
	/// 
	/// - Returns: 200 on success.
	func modDeleteStreamPhoto(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		let photo = try await StreamPhoto.findFromParameter(streamPhotoIDParam, on: req)
		try user.guardCanModifyContent(photo, customErrorString: "User cannot edit/moderate photo.")
		try await photo.delete(on: req.db)
		try await photo.logIfModeratorAction(.delete, moderatorID: user.userID, on: req)
		return .ok
	}
	
// MARK: Utilities

	// Gets the list of placenames and current events. If forValidation is TRUE, also returns events that ended within
	// the last 5 minutes. This gives a user taking a Photostream photo near the end of an event a bit of a grace period
	// in which to upload their pic.
	func getPlacenameList(_ req: Request, forValidation: Bool) async throws -> PhotostreamLocationData {
		let user = try req.auth.require(UserCacheData.self)
		
		// As with event getters, translate the current time-of-week into the same time of the cruise week (for whatever
		// year our schedule data is for), so that we can test getting event placeenames year-round. During cruise week
		// this translation should no-op.
		let cruiseStart = Settings.shared.cruiseStartDate()
		let cal = Settings.shared.calendarForDate(cruiseStart)
		let thisWeekday = cal.component(.weekday, from: Date())
		let dayOfCruise = (7 + thisWeekday - Settings.shared.cruiseStartDayOfWeek) % 7	// 0 for embark day
		let currentDateComponents = cal.dateComponents(in: cal.timeZone, from: Date())
// For testing
//		let dayOfCruise = 1	// 0 for embark day
//		let currentDateComponents = DateComponents(calendar: cal, timeZone: cal.timeZone, hour: 15, minute: 2, second: 0)
		let cruiseWeekOffset = DateComponents(calendar: cal, timeZone: cal.timeZone, day: dayOfCruise, hour: currentDateComponents.hour, 
				minute: currentDateComponents.minute, second: currentDateComponents.second)
		let effectiveDate = cal.date(byAdding: cruiseWeekOffset, to: cruiseStart, wrappingComponents: false)
		// Search for current events; if we're validating an upload include the event if it ended in the last 5 mins
		let currentPortTime = try await TimeZoneChangeSet(req.db).displayTimeToPortTime(effectiveDate)
		let validationEndTime = forValidation ? currentPortTime + 300.0 : currentPortTime
		let currentEvents = try await Event.query(on: req.db).filter(\.$startTime <= currentPortTime).filter(\.$endTime > validationEndTime)
				.joinWithFilter(method: .left, from: \.$id, to: \EventFavorite.$event.$id, otherFilters: 
				[.value(.path(EventFavorite.path(for: \.$user.$id), schema: EventFavorite.schema), .equal, .bind(user.userID))]).all()
		let eventData: [EventData] = try currentEvents.compactMap {
			if $0.endTime.timeIntervalSince($0.startTime) > 3600 * 2 {
				return nil
			}
			let isFav = (try? $0.joined(EventFavorite.self)) != nil
			return try EventData($0, isFavorite: isFav)
		}
		let placeNames = PhotoStreamBoatLocation.allCases.map { $0.rawValue }
		let result = PhotostreamLocationData(events: eventData, locations: placeNames)
		return result
	}

}


import Vapor
import Crypto
import FluentSQL

/// The collection of `/api/v3/admin` route endpoints and handler functions related to admin tasks.
///
/// All routes in this group should be restricted to users with administrator priviliges. This controller returns data of 
/// a privledged nature, and has control endpoints for setting overall server state.
struct AdminController: APIRouteCollection {
    
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/admin endpoints
		let modRoutes = app.grouped("api", "v3", "admin")
		
		// instantiate authentication middleware
		let requireAdminMiddleware = RequireAdminMiddleware()
						 
		// endpoints available for Admins only
		let adminAuthGroup = addTokenAuthGroup(to: modRoutes).grouped([requireAdminMiddleware])
		adminAuthGroup.post("dailytheme", "create", use: addDailyThemeHandler)
		adminAuthGroup.post("dailytheme", dailyThemeIDParam, "edit", use: editDailyThemeHandler)
		adminAuthGroup.post("dailytheme", dailyThemeIDParam, "delete", use: deleteDailyThemeHandler)
		adminAuthGroup.delete("dailytheme", dailyThemeIDParam, use: deleteDailyThemeHandler)
		
		adminAuthGroup.get("serversettings", use: settingsHandler)
		adminAuthGroup.post("serversettings", "update", use: settingsUpdateHandler)

		adminAuthGroup.post("schedule", "update", use: scheduleUploadPostHandler)
		adminAuthGroup.get("schedule", "verify", use: scheduleChangeVerificationHandler)
		adminAuthGroup.post("schedule", "update", "apply", use: scheduleChangeApplyHandler)
		
		adminAuthGroup.get("regcodes", "stats", use: regCodeStatsHandler)
		adminAuthGroup.get("regcodes", "find", searchStringParam, use: userForRegCodeHandler)
	}

    /// `POST /api/v3/admin/dailytheme/create`
    ///
    /// Creates a new daily theme for a day of the cruise (or some other day). The 'day' field is unique, so attempts to create a new record
	/// with the same day as an existing record will fail--instead, you probably want to edit the existing DailyTheme for that day. 
	/// 
    /// - Parameter requestBody: <doc:DailyThemeUploadData>
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 201 Created` if the theme was added successfully.
	func addDailyThemeHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot add daily themes")
 		let data = try ValidatingJSONDecoder().decode(DailyThemeUploadData.self, fromBodyOf: req)
 		let imageArray = data.image != nil ? [data.image!] : []
        // process images
        return self.processImages(imageArray, usage: .dailyTheme, on: req).throwingFlatMap { filenames in
        	let filename = filenames.isEmpty ? nil : filenames[0]
			let dailyTheme = DailyTheme(title: data.title, info: data.info, image: filename, day: data.cruiseDay)		
			return dailyTheme.save(on: req.db).transform(to: .created)
		}
	}
	
    /// `POST /api/v3/admin/dailytheme/ID/edit`
    ///
    /// Edits an existing daily theme. Passing nil for the image will remove an existing image. Although you can change the cruise day for a DailyTheme,
	/// you can't set the day to equal a day that already has a theme record. This means it'll take extra steps if you want to swap days for 2 themes.
	/// 
    /// - Parameter dailyThemeID: in URL path
    /// - Parameter requestBody: <doc:DailyThemeUploadData>
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 201 Created` if the theme was added successfully.
	func editDailyThemeHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot add daily themes")
 		let data = try ValidatingJSONDecoder().decode(DailyThemeUploadData.self, fromBodyOf: req)
 		let imageArray = data.image != nil ? [data.image!] : []
 		return DailyTheme.findFromParameter(dailyThemeIDParam, on: req).throwingFlatMap { dailyTheme in
			// process images
			return self.processImages(imageArray, usage: .dailyTheme, on: req).throwingFlatMap { filenames in
        		let filename = filenames.isEmpty ? nil : filenames[0]
				dailyTheme.title = data.title
				dailyTheme.info = data.info
				dailyTheme.image = filename
				dailyTheme.cruiseDay = data.cruiseDay
				return dailyTheme.save(on: req.db).transform(to: .created)
			}
		}
	}
	
    /// `POST /api/v3/admin/dailytheme/ID/delete`
    /// `DELETE /api/v3/admin/dailytheme/ID/`
    ///
    ///  Deletes a daily theme.
	/// 
    /// - Parameter dailyThemeID:in URL path
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 204 noContent` if the theme was deleted successfully.
	func deleteDailyThemeHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot delete daily themes")
		return DailyTheme.findFromParameter(dailyThemeIDParam, on: req).flatMap { theme in
			return theme.delete(on: req.db).transform(to: .noContent)
		}
	}
	
    /// `GET /api/v3/admin/serversettings`
    ///
    ///  Returns the current state of the server's Settings structure.
	/// 
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:SettingsAdminData>
	func settingsHandler(_ req: Request) throws -> SettingsAdminData {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.admin) else {
			throw Abort(.forbidden, reason: "Admin only")
		}
		return SettingsAdminData(Settings.shared)
	}
	
    /// `POST /api/v3/admin/serversettings/update`
    ///
    ///  Updates a bunch of settings in the Settings.shared object.
	/// 
    /// - Parameter requestBody: <doc:SettingsUpdateData>
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 200 OK` if the settings were updated.
	func settingsUpdateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.admin) else {
			throw Abort(.forbidden, reason: "Admin only")
		}
 		let data = try ValidatingJSONDecoder().decode(SettingsUpdateData.self, fromBodyOf: req)
 		if let value = data.maxAlternateAccounts {
 			Settings.shared.maxAlternateAccounts = value
 		}
 		if let value = data.maximumTwarrts {
 			Settings.shared.maximumTwarrts = value
 		}
 		if let value = data.maximumForums {
 			Settings.shared.maximumForums = value
 		}
 		if let value = data.maximumForumPosts {
 			Settings.shared.maximumForumPosts = value
 		}
 		if let value = data.maxImageSize {
 			Settings.shared.maxImageSize = value
 		}
 		if let value = data.forumAutoQuarantineThreshold {
 			Settings.shared.forumAutoQuarantineThreshold = value
 		}
 		if let value = data.postAutoQuarantineThreshold {
 			Settings.shared.postAutoQuarantineThreshold = value
 		}
 		if let value = data.userAutoQuarantineThreshold {
 			Settings.shared.userAutoQuarantineThreshold = value
 		}
 		if let value = data.allowAnimatedImages {
 			Settings.shared.allowAnimatedImages = value
 		}
 		var localDisables = Settings.shared.disabledFeatures.value
 		for pair in data.enableFeatures {
 			if let app = SwiftarrClientApp(rawValue: pair.app), let feature = SwiftarrFeature(rawValue: pair.feature) {
				localDisables[app]?.remove(feature)
				if let featureSet = localDisables[app], featureSet.isEmpty {
					localDisables.removeValue(forKey: app)
				}
			}
 		}
 		for pair in data.disableFeatures {
 			if let app = SwiftarrClientApp(rawValue: pair.app), let feature = SwiftarrFeature(rawValue: pair.feature) {
 				if localDisables[app] == nil {
					localDisables[app] = Set(arrayLiteral: feature)
 				}
 				else {
					localDisables[app]?.insert(feature)
				}
			}
 		}
 		Settings.shared.disabledFeatures = DisabledFeaturesGroup(value: localDisables)
		return try Settings.shared.storeSettings(on: req).transform(to: HTTPStatus.ok)
	}
	
    /// `POST /api/v3/admin/schedule/update`
    ///
    ///  Handles the POST of a new schedule .ics file.
	/// 
	///  - Warning: Updating the schedule isn't thread-safe, especially if admin is logged in twice. Uploading a schedule file while another 
	///  admin account was attempting to apply its contents will cause errors. Once uploaded, an events file should be safe to verify and 
	///  apply multiple times in parallel.
	///
    /// - Parameter requestBody: <doc:EventsUpdateData> which is really one big String (the .ics file) wrapped in JSON.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 200 OK`
	func scheduleUploadPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.admin) else {
			throw Abort(.forbidden, reason: "Admin only")
		}
		var schedule = try req.content.decode(EventsUpdateData.self).schedule
        schedule = schedule.replacingOccurrences(of: "&amp;", with: "&")
        schedule = schedule.replacingOccurrences(of: "\\,", with: ",")
		let filepath = try uploadSchedulePath()
		// If we attempt an upload, it's important we end up with the uploaded file or nothing at the filepath.
		// Leaving the previous file there would be bad.
		try FileManager.default.removeItem(at: filepath)
		return req.fileio.writeFile(ByteBuffer(string: schedule), at: filepath.path).transform(to: .ok)
	}
	
    /// `GET /api/v3/admin/schedule/verify`
    ///
    ///  Returns a struct showing the differences between the current schedule and the (already uploaded and saved to a local file) new schedule.
	///  
	///  - Note: This is a separate GET call, instead of the response from POSTing the updated .ics file, so that verifying and applying a schedule 
	///  update can be idempotent. Once an update is uploaded, you can call the validate and apply endpoints repeatedly if necessary. 
	///  
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:EventUpdateDifferenceData>
	func scheduleChangeVerificationHandler(_ req: Request) throws -> EventLoopFuture<EventUpdateDifferenceData> {
		let filepath = try uploadSchedulePath()
		return req.fileio.collectFile(at: filepath.path).throwingFlatMap { buffer in
			guard let scheduleFileStr = buffer.getString(at: 0, length: buffer.readableBytes) else {
				throw Abort(.badRequest, reason: "Could not read schedule file.")
			}
			let updateEvents = EventParser().parse(scheduleFileStr)
			return Event.query(on: req.db).withDeleted().all().flatMapThrowing { existingEvents in
				// Convert to dictionaries, keyed by uid of the events
				let existingEventDict = Dictionary(existingEvents.map { ($0.uid, $0) }) {first, _ in first }
				let updateEventDict = Dictionary(updateEvents.map { ($0.uid, $0) }) {first, _ in first }
				let existingEventuids = Set(existingEvents.map { $0.uid }) 
				let updateEventuids = Set(updateEvents.map { $0.uid })
				var responseData = EventUpdateDifferenceData()
				
				// Deletes
				let deleteduids = existingEventuids.subtracting(updateEventuids)
				try deleteduids.forEach { uid in
					if let existing = existingEventDict[uid] {
						try responseData.deletedEvents.append(EventData(existing))
					}
				}
				
				// Creates
				let createduids = updateEventuids.subtracting(existingEventuids)
				createduids.forEach { uid in
					if let updated = updateEventDict[uid] {
						let eventData = EventData(eventID: UUID(), uid: updated.uid, title: updated.title, 
							description: updated.description, startTime: updated.startTime, endTime: updated.endTime, 
							location: updated.location, eventType: updated.eventType.rawValue, forum: nil, isFavorite: false)
						responseData.createdEvents.append(eventData)
					}
				}
				
				// Updates
				let updatedEvents = existingEventuids.intersection(updateEventuids)
				updatedEvents.forEach { uid in
					if let existing = existingEventDict[uid], let updated = updateEventDict[uid] {
						let eventData = EventData(eventID: UUID(), uid: updated.uid, title: updated.title, 
							description: updated.description, startTime: updated.startTime, endTime: updated.endTime, 
							location: updated.location, eventType: updated.eventType.rawValue, forum: nil, isFavorite: false)
						if existing.startTime != updated.startTime || existing.endTime != updated.endTime {
							responseData.timeChangeEvents.append(eventData)
						}
						if existing.location != updated.location {
							responseData.locationChangeEvents.append(eventData)
						}
						if existing.title != updated.title || existing.info != updated.info ||
								existing.eventType != updated.eventType {
							responseData.minorChangeEvents.append(eventData)		
						}
					}
				}
				
				return responseData
			}
		}
	}
	
    /// `POST /api/v3/admin/schedule/update/apply`
	/// 
	/// Applies schedule changes to the schedule. Reads in a previously uploaded schedule file from `/admin/uploadschedule.ics` and creates, 
	/// deletes, and updates Event objects as necessary. If `forumPosts` is `true`, creates posts in Event forums notifying users of the schedule
	/// change. Whether `forumPosts` is true or not, forums are created for new Events, and forum titles and initial posts are updated to match
	/// the updated event info.
    ///
    /// **URL Query Parameters:**
	/// 
	/// - `?processDeletes=true` to delete existing events not in the update list. Only set this if the update file is a comprehensive list of all events.
	/// - `?forumPosts=true` to create posts in the Event Forum of each modified event, alerting readers of the event change. We may want to forego 
	///   	 	change posts if we update the schedule as soon as we board the ship. For events created by this update, we always try to create and associate
	///   	 	a forum for the event.
	/// 
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 200 OK`
	func scheduleChangeApplyHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        guard user.accessLevel.hasAccess(.admin) else {
            throw Abort(.forbidden, reason: "admins only")
        }
		let processDeletes = req.query[String.self, at: "processDeletes"]?.lowercased() == "true"
		let makeForumPosts = req.query[String.self, at: "forumPosts"]?.lowercased() == "true"
        
		let filepath = try uploadSchedulePath()
		return req.fileio.collectFile(at: filepath.path).throwingFlatMap { buffer in
			guard let scheduleFileStr = buffer.getString(at: 0, length: buffer.readableBytes) else {
				throw Abort(.badRequest, reason: "Could not read schedule file.")
			}
			let updateEvents = EventParser().parse(scheduleFileStr)

            let officialResult = Category.query(on: req.db).filter(\.$title, .custom("ILIKE"), "event%").first()
            let shadowResult = Category.query(on: req.db).filter(\.$title, .custom("ILIKE"), "shadow%").first()
            return EventLoopFuture.whenAllSucceed([officialResult, shadowResult], on: req.eventLoop).flatMap { categories in
				return Event.query(on: req.db).withDeleted().with(\.$forum).all().flatMap { existingEvents in
					return req.db.transaction { database in
						do {
							var futures: [EventLoopFuture<Void>] = []

							// Convert to dictionaries, keyed by uid of the events
							let existingEventDict = Dictionary(existingEvents.map { ($0.uid, $0) }) {first, _ in first }
							let updateEventDict = Dictionary(updateEvents.map { ($0.uid, $0) }) {first, _ in first }
							let existingEventuids = Set(existingEvents.map { $0.uid }) 
							let updateEventuids = Set(updateEvents.map { $0.uid })
						
							// Process deletes
							if processDeletes {
								let deleteduids = existingEventuids.subtracting(updateEventuids)
								if makeForumPosts {
									for eventUID in deleteduids {
										if let existingEvent = existingEventDict[eventUID] {
											let future = existingEvent.$forum.load(on: database).throwingFlatMap { (_: Void) -> EventLoopFuture<Void> in
												if let forum = existingEvent.forum {
													let newPost = try ForumPost(forum: forum, author: user, text: """
															Automatic Notification of Schedule Change: This event has been deleted from the \
															schedule. Apologies to those planning on attending.
															
															However, since this is an automatic announcement, it's possible the event got moved or \
															rescheduled and it only looks like a delete to me, your automatic server software. \
															Check the schedule.
															""")
													return newPost.save(on: database)
												}
												return database.eventLoop.future()
											}
											futures.append(future)
										}
									}
								}
								futures.append(Event.query(on: database).filter(\.$uid ~~ deleteduids).delete())
							}
							
							// Process creates
							let createduids = updateEventuids.subtracting(existingEventuids)
							try createduids.forEach { uid in
								if let event = updateEventDict[uid] {
									// Note that for creates, we make an initial forum post whether or not makeForumPosts is set.
									// makeForumPosts only concerns the "Schedule was changed" posts.
									if let officialCategory = categories[0], let shadowCategory = categories[1], 
											officialCategory.title.lowercased() == "event forums", 
											shadowCategory.title.lowercased() == "shadow event forums" {
										let forum = try CreateEventForums.buildEventForum(event, creator: user, 
												shadowCategory: shadowCategory, officialCategory: officialCategory)
										futures.append(forum.save(on: database).throwingFlatMap {
											// Build an initial post in the forum with information about the event, and
											// a callout for posters to discuss the event.
											let postText = CreateEventForums.buildEventPostText(event)
											let infoPost = try ForumPost(forum: forum, author: user, text: postText)
										
											// Associate the forum with the event
											event.$forum.id = forum.id
											event.$forum.value = forum
											return event.save(on: database).flatMap {
												return infoPost.save(on: database).throwingFlatMap { 
													if makeForumPosts {
														let newPost = try ForumPost(forum: forum, author: user, text: """
																Automatic Notification of Schedule Change: This event was just added to the \
																schedule.
																""")
														return newPost.save(on: database)
													}
													return database.eventLoop.future()
												}
											}
										})
									}
									else {
										futures.append(event.save(on: database))
									}
								}
							}
						
							// Process changes to existing events
							let updatedEvents = existingEventuids.intersection(updateEventuids)
							try updatedEvents.forEach { uid in
								if let existing = existingEventDict[uid], let updated = updateEventDict[uid] {
									var changes: Set<EventModification> = Set()
									if let deleteTime = existing.deletedAt, deleteTime < Date() {
										changes.insert(.undelete)
										existing.deletedAt = nil
									}
									if existing.startTime != updated.startTime {
										changes.insert(.startTime)
										existing.startTime = updated.startTime
										existing.endTime = updated.endTime
									}
									else if existing.endTime != updated.endTime {
										changes.insert(.endTime)
										existing.endTime = updated.endTime
									}
									if existing.location != updated.location {
										changes.insert(.location)
										existing.location = updated.location
									}
									if existing.title != updated.title || existing.info != updated.info ||
											existing.eventType != updated.eventType {
										changes.insert(.info)
										existing.title = updated.title
										existing.info = updated.info
										existing.eventType = updated.eventType
									}
									if !changes.isEmpty {
										futures.append(existing.save(on: database))
										if let forum = existing.forum {
											// Update title of event's linked forum
											let dateFormatter = DateFormatter()
											dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
											dateFormatter.dateFormat = "(E, HH:mm)"
											forum.title = dateFormatter.string(from: existing.startTime) + " \(existing.title)"
											futures.append(forum.save(on: database))
											// Update first post of event's forum thread.
											futures.append(forum.$posts.query(on: database).sort(\.$id, .ascending).first()
													.flatMap { (post) -> EventLoopFuture<Void> in
												if let firstPost = post {
													firstPost.text = CreateEventForums.buildEventPostText(existing)
													return firstPost.save(on: database)
												}
												return database.eventLoop.future()
											})
											// Add post to forum detailing changes made to this event.
											if makeForumPosts {
												let newPost = try ForumPost(forum: forum, author: user, text: """
														Automatic Notification of Schedule Change: This event has changed.
														
														\(changes.contains(.undelete) ? "This event was canceled, but now is un-canceled.\r" : "")\
														\(changes.contains(.startTime) ? "Start Time changed\r" : "")\
														\(changes.contains(.endTime) ? "End Time changed\r" : "")\
														\(changes.contains(.location) ? "Location changed\r" : "")\
														\(changes.contains(.info) ? "Event info changed\r" : "")
														""")
												futures.append(newPost.save(on: database))
											}
										}
									}
								}
							}
							// Wait for everything to complete
							return futures.flatten(on: database.eventLoop).transform(to: .ok)					
						}
						catch {
							return database.eventLoop.makeFailedFuture(error)
						}
						// End database transaction
					}
				}
			}
        }
	}
	
    /// `GET /api/v3/admin/regcodes/stats`
	/// 
	///  Returns basic info about how many regcodes have been used to create accounts, and how many there are in total.
	///  In the future, we may add a capability for admins to create and issue replacement codes to users (or pull codes from a pre-allocated
	///  'replacement' list, or something). This returns stats on those theoretical codes too, but the numbers are all 0.
	///  
    /// - Returns: <doc:RegistrationCodeStatsData> 
	func regCodeStatsHandler(_ req: Request) throws -> EventLoopFuture<RegistrationCodeStatsData> {
		let codeCountFuture = RegistrationCode.query(on: req.db).count()
		let usedCodesFuture = RegistrationCode.query(on: req.db).filter(\.$user.$id != nil).count()
		return codeCountFuture.and(usedCodesFuture).map { codeCount, usedCodes in
			return RegistrationCodeStatsData(allocatedCodes: codeCount, usedCodes: usedCodes, 
					unusedCodes: codeCount - usedCodes, adminCodes: 0)
		}
	}
	
    /// `GET /api/v3/admin/regcodes/find/:search_string`
	/// 
	///  Checks whether a user has been associated with a registration code. Can also be used to check whether a reg code is valid.
	///  Throws when the reg code is not found primarily to help differentiate between "No reg code found" "No User Found" and "User Found" cases.
	///  
    /// - Throws: 400 Bad Request if the reg code isn't found in the db or if it's malformed. We don't check too thoroughly whether it's well-formed.
    /// - Returns: [] if no user has created an account using this reg code yet. If they have, returns a one-item array containing the UserHead of that user.
	func userForRegCodeHandler(_ req: Request) throws -> EventLoopFuture<[UserHeader]> {
        guard let regCode = req.parameters.get(searchStringParam.paramString, as: String.self)?.lowercased() else {
        	throw Abort(.badRequest, reason: "Missing search parameter")
        }
        guard regCode.count == 6, regCode.allSatisfy( { $0.isLetter || $0.isNumber }) else {
        	throw Abort(.badRequest, reason: "Registration code search parameter is malformed.")
        }
		return RegistrationCode.query(on: req.db).filter(\.$code == regCode).first().flatMapThrowing { record in
			guard let foundRecord = record else {
				throw Abort(.badRequest, reason: "\(regCode) is not found in the registration code table.")
			}
			if let userID = foundRecord.$user.id {
				let userHeader = try req.userCache.getHeader(userID)
				return [userHeader]
			}
			return []
		}
	}

// MARK: - Utilities

	// Gets the path where the uploaded schedule is kept. Only one schedule file can be in the hopper at a time.
	// This fn ensures intermediate directories are created.
	func uploadSchedulePath() throws -> URL {
		let dirPath = URL(fileURLWithPath: DirectoryConfiguration.detect().workingDirectory)
				.appendingPathComponent("admin")
		try FileManager.default.createDirectory(at: dirPath, withIntermediateDirectories: true, attributes: nil)
		let filePath = dirPath.appendingPathComponent("uploadschedule.ics")
		return filePath
	}

}

// Used internally to track the diffs involved in an calendar update.
fileprivate enum EventModification {
	case startTime
	case endTime
	case location
	case undelete
	case info
}

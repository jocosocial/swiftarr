import Vapor
import Crypto
import FluentSQL
import Dispatch

/// The collection of `/api/v3/admin` route endpoints and handler functions related to admin tasks.
///
/// All routes in this group should be restricted to users with administrator priviliges. This controller returns data of 
/// a privledged nature, and has control endpoints for setting overall server state.
struct AdminController: APIRouteCollection {
	
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/admin endpoints
		let adminRoutes = app.grouped("api", "v3", "admin")
		
		// endpoints available to TwitarrTeam and above
		let ttAuthGroup = addTokenCacheAuthGroup(to: adminRoutes).grouped([RequireTwitarrTeamMiddleware()])
		ttAuthGroup.post("schedule", "update", use: scheduleUploadPostHandler)
		ttAuthGroup.get("schedule", "verify", use: scheduleChangeVerificationHandler)
		ttAuthGroup.post("schedule", "update", "apply", use: scheduleChangeApplyHandler)
		
		ttAuthGroup.get("regcodes", "stats", use: regCodeStatsHandler)
		ttAuthGroup.get("regcodes", "find", searchStringParam, use: userForRegCodeHandler)
		ttAuthGroup.get("regcodes", "findbyuser", userIDParam, use: regCodeForUserHandler)

		ttAuthGroup.get("serversettings", use: settingsHandler)
								 
		// endpoints available for THO and Admin only
		let thoAuthGroup = addTokenCacheAuthGroup(to: adminRoutes).grouped([RequireTHOMiddleware()])
		thoAuthGroup.on(.POST, "dailytheme", "create", body: .collect(maxSize: "30mb"), use: addDailyThemeHandler)
		thoAuthGroup.on(.POST, "dailytheme", dailyThemeIDParam, "edit", body: .collect(maxSize: "30mb"), use: editDailyThemeHandler)
		thoAuthGroup.post("dailytheme", dailyThemeIDParam, "delete", use: deleteDailyThemeHandler)
		thoAuthGroup.delete("dailytheme", dailyThemeIDParam, use: deleteDailyThemeHandler)
		
			// Note that there's several promote method that promote to different access levels, but 
			// only one demote, that returns the user to Verified.
		thoAuthGroup.get("moderators", use: getModeratorsHandler)
		thoAuthGroup.get("twitarrteam", use: getTwitarrTeamHandler)
		thoAuthGroup.get("tho", use: getTHOHandler)
		thoAuthGroup.post("moderator", "promote", userIDParam, use: makeModeratorHandler)
		thoAuthGroup.post("twitarrteam", "promote", userIDParam, use: makeTwitarrTeamHandler)
		thoAuthGroup.post("user", "demote", userIDParam, use: demoteToVerifiedHandler)
		
			// User Role management
		thoAuthGroup.get("userroles", userRoleParam, use: getUsersWithRole)
		thoAuthGroup.post("userroles", userRoleParam, "addrole", userIDParam, use: addRoleForUser)
		thoAuthGroup.post("userroles", userRoleParam, "removerole", userIDParam, use: removeRoleForUser)

		let adminAuthGroup = addTokenCacheAuthGroup(to: adminRoutes).grouped([RequireAdminMiddleware()])
		adminAuthGroup.post("serversettings", "update", use: settingsUpdateHandler)
		
		adminAuthGroup.get("timezonechanges", use: timeZoneChangeHandler)
		adminAuthGroup.post("timezonechanges", "reloadtzdata", use: reloadTimeZoneChangeData)
		
		// Only admin may promote to THO 
		adminAuthGroup.post("tho", "promote", userIDParam, use: makeTHOHandler)
	}

	/// `POST /api/v3/admin/dailytheme/create`
	///
	/// Creates a new daily theme for a day of the cruise (or some other day). The 'day' field is unique, so attempts to create a new record
	/// with the same day as an existing record will fail--instead, you probably want to edit the existing DailyTheme for that day. 
	/// 
	/// - Parameter requestBody: <doc:DailyThemeUploadData>
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 201 Created` if the theme was added successfully.
	func addDailyThemeHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		try user.guardCanCreateContent(customErrorString: "user cannot add daily themes")
 		let data = try ValidatingJSONDecoder().decode(DailyThemeUploadData.self, fromBodyOf: req)
 		let imageArray = data.image != nil ? [data.image!] : []
		let filenames = try await processImages(imageArray, usage: .dailyTheme, on: req)
		let filename = filenames.isEmpty ? nil : filenames[0]
		let dailyTheme = DailyTheme(title: data.title, info: data.info, image: filename, day: data.cruiseDay)		
		try await dailyTheme.save(on: req.db)
		return .created
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
	func editDailyThemeHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		try user.guardCanCreateContent(customErrorString: "user cannot add daily themes")
 		let data = try ValidatingJSONDecoder().decode(DailyThemeUploadData.self, fromBodyOf: req)
 		let dailyTheme = try await DailyTheme.findFromParameter(dailyThemeIDParam, on: req)
		// process images
		let filenames = try await processImages(data.image != nil ? [data.image!] : [], usage: .dailyTheme, on: req)
		dailyTheme.title = data.title
		dailyTheme.info = data.info
		dailyTheme.image = filenames.isEmpty ? nil : filenames[0]
		dailyTheme.cruiseDay = data.cruiseDay
		try await dailyTheme.save(on: req.db)
		return .created
	}
	
	/// `POST /api/v3/admin/dailytheme/ID/delete`
	/// `DELETE /api/v3/admin/dailytheme/ID/`
	///
	///  Deletes a daily theme.
	/// 
	/// - Parameter dailyThemeID:in URL path
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 204 noContent` if the theme was deleted successfully.
	func deleteDailyThemeHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		try user.guardCanCreateContent(customErrorString: "user cannot delete daily themes")
		let theme = try await DailyTheme.findFromParameter(dailyThemeIDParam, on: req)
		try await theme.delete(on: req.db)
		return .noContent
	}
	
	/// `GET /api/v3/admin/serversettings`
	///
	///  Returns the current state of the server's Settings structure.
	/// 
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:SettingsAdminData>
	func settingsHandler(_ req: Request) throws -> SettingsAdminData {
		return SettingsAdminData(Settings.shared)
	}
	
	/// `POST /api/v3/admin/serversettings/update`
	///
	///  Updates a bunch of settings in the Settings.shared object.
	/// 
	/// - Parameter requestBody: <doc:SettingsUpdateData>
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK` if the settings were updated.
	func settingsUpdateHandler(_ req: Request) async throws -> HTTPStatus {
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
 		if let value = data.shipWifiSSID {
 			Settings.shared.shipWifiSSID = value
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
		try await Settings.shared.storeSettings(on: req)
		return .ok
	}
	
	/// `GET /api/v3/admin/timezonechanges`
	/// 
	/// Returns information about the declared time zone changes happening during the cruise.
	/// 
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:TimeZoneChangeData>
	func timeZoneChangeHandler(_ req: Request) async throws -> TimeZoneChangeData {
		let tzChangeSet = try await TimeZoneChangeSet(req.db)
		let result = TimeZoneChangeData(tzChangeSet)
		return result
	}
	
	/// `POST /api/v3/admin/serversettings/reloadtzdata`
	///
	///  Reloads the time zone change data from the seed file. Removes all previous entries.
	/// 
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK` if the settings were updated.
	func reloadTimeZoneChangeData(_ req: Request) async throws -> HTTPStatus {
		let migrator = ImportTimeZoneChanges()
		try await migrator.loadTZFile(on: req.db, isMigrationTime: false)
		return .ok
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
	func scheduleUploadPostHandler(_ req: Request) async throws -> HTTPStatus {
		var schedule = try req.content.decode(EventsUpdateData.self).schedule
		schedule = schedule.replacingOccurrences(of: "&amp;", with: "&")
		schedule = schedule.replacingOccurrences(of: "\\,", with: ",")
		let filepath = try uploadSchedulePath()
		// If we attempt an upload, it's important we end up with the uploaded file or nothing at the filepath.
		// Leaving the previous file there would be bad.
		try? FileManager.default.removeItem(at: filepath)
		try await req.fileio.writeFile(ByteBuffer(string: schedule), at: filepath.path)
		return .ok
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
	func scheduleChangeVerificationHandler(_ req: Request) async throws -> EventUpdateDifferenceData {
		let filepath = try uploadSchedulePath()
		let buffer = try await req.fileio.collectFile(at: filepath.path)
		guard let scheduleFileStr = buffer.getString(at: 0, length: buffer.readableBytes) else {
			throw Abort(.badRequest, reason: "Could not read schedule file.")
		}
		let updateEvents = EventParser().parse(scheduleFileStr)
		let existingEvents = try await Event.query(on: req.db).withDeleted().all()
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
				// This eventData uses a throwaway UUID as the Event isn't in the db yet 
				let eventData = EventData(eventID: UUID(), uid: updated.uid, title: updated.title, 
						description: updated.description, startTime: updated.startTime, endTime: updated.endTime, timeZone: "", 
						location: updated.location, eventType: updated.eventType.rawValue, lastUpdateTime: updated.updatedAt ?? Date(),
						forum: nil, isFavorite: false)
				responseData.createdEvents.append(eventData)
			}
		}
				
		// Updates
		let updatedEvents = existingEventuids.intersection(updateEventuids)
		updatedEvents.forEach { uid in
			if let existing = existingEventDict[uid], let updated = updateEventDict[uid] {
				let eventData = EventData(eventID: UUID(), uid: updated.uid, title: updated.title, 
						description: updated.description, startTime: updated.startTime, endTime: updated.endTime, timeZone: "", 
						location: updated.location, eventType: updated.eventType.rawValue, lastUpdateTime: updated.updatedAt ?? Date(),
						forum: nil, isFavorite: false)
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
	func scheduleChangeApplyHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		let processDeletes = req.query[String.self, at: "processDeletes"]?.lowercased() == "true"
		let makeForumPosts = req.query[String.self, at: "forumPosts"]?.lowercased() == "true"
		let filepath = try uploadSchedulePath()
		let buffer = try await req.fileio.collectFile(at: filepath.path)
		guard let scheduleFileStr = buffer.getString(at: 0, length: buffer.readableBytes) else {
			throw Abort(.badRequest, reason: "Could not read schedule file.")
		}
		let updateEvents = EventParser().parse(scheduleFileStr)

		let officialCategory = try await Category.query(on: req.db).filter(\.$title, .custom("ILIKE"), "event%").first()
		let shadowCategory = try await Category.query(on: req.db).filter(\.$title, .custom("ILIKE"), "shadow%").first()
		let existingEvents = try await Event.query(on: req.db).withDeleted().with(\.$forum).all()
		try await req.db.transaction { database in
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
							try await existingEvent.$forum.load(on: database)
							if let forum = existingEvent.forum {
								let newPost = try ForumPost(forum: forum, authorID: user.userID, text: """
										Automatic Notification of Schedule Change: This event has been deleted from the \
										schedule. Apologies to those planning on attending.
										
										However, since this is an automatic announcement, it's possible the event got moved or \
										rescheduled and it only looks like a delete to me, your automatic server software. \
										Check the schedule.
										""")
								try await newPost.save(on: database)
							}
						}
					}
				}
				try await Event.query(on: database).filter(\.$uid ~~ deleteduids).delete()
			}
			
			// Process creates
			let createduids = updateEventuids.subtracting(existingEventuids)
			for uid in createduids {
				if let event = updateEventDict[uid] {
					// Note that for creates, we make an initial forum post whether or not makeForumPosts is set.
					// makeForumPosts only concerns the "Schedule was changed" posts.
					if let officialCategory = officialCategory, let shadowCategory = shadowCategory {
						let forum = try SetInitialEventForums.buildEventForum(event, creatorID: user.userID, 
								shadowCategory: shadowCategory, officialCategory: officialCategory)
						try await forum.save(on: database)
						// Build an initial post in the forum with information about the event, and
						// a callout for posters to discuss the event.
						let postText = SetInitialEventForums.buildEventPostText(event)
						let infoPost = try ForumPost(forum: forum, authorID: user.userID, text: postText)
					
						// Associate the forum with the event
						event.$forum.id = forum.id
						event.$forum.value = forum
						try await event.save(on: database)
						try await infoPost.save(on: database)
						if makeForumPosts {
							let newPost = try ForumPost(forum: forum, authorID: user.userID, text: """
									Automatic Notification of Schedule Change: This event was just added to the \
									schedule.
									""")
							try await newPost.save(on: database)
						}
					}
				}
			}
		
			// Process changes to existing events
			let updatedEvents = existingEventuids.intersection(updateEventuids)
			for uid in updatedEvents {
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
					if existing.title != updated.title || existing.info != updated.info || existing.eventType != updated.eventType {
						changes.insert(.info)
						existing.title = updated.title
						existing.info = updated.info
						existing.eventType = updated.eventType
					}
					if !changes.isEmpty {
						try await existing.save(on: database)
						if let forum = existing.forum {
							// Update title of event's linked forum
							let dateFormatter = DateFormatter()
							dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
							dateFormatter.dateFormat = "(E, HH:mm)"
							forum.title = dateFormatter.string(from: existing.startTime) + " \(existing.title)"
							try await forum.save(on: database)
							// Update first post of event's forum thread.
							if let firstPost = try await forum.$posts.query(on: database).sort(\.$id, .ascending).first() {
								firstPost.text = SetInitialEventForums.buildEventPostText(existing)
								try await firstPost.save(on: database)
							}
							// Add post to forum detailing changes made to this event.
							if makeForumPosts {
								let newPost = try ForumPost(forum: forum, authorID: user.userID, text: """
										Automatic Notification of Schedule Change: This event has changed.
										
										\(changes.contains(.undelete) ? "This event was canceled, but now is un-canceled.\r" : "")\
										\(changes.contains(.startTime) ? "Start Time changed\r" : "")\
										\(changes.contains(.endTime) ? "End Time changed\r" : "")\
										\(changes.contains(.location) ? "Location changed\r" : "")\
										\(changes.contains(.info) ? "Event info changed\r" : "")
										""")
								try await newPost.save(on: database)
							}
						}
					}
				}
			}
			// Update the cached counts of how many forums are in each category
			let categories = try await Category.query(on: database).with(\.$forums).all()
			for cat in categories {
				cat.forumCount = Int32(cat.forums.count)
				try await cat.save(on: database)
			}
		}
		// End database transaction
		return .ok	
	}
	
	/// `GET /api/v3/admin/regcodes/stats`
	/// 
	///  Returns basic info about how many regcodes have been used to create accounts, and how many there are in total.
	///  In the future, we may add a capability for admins to create and issue replacement codes to users (or pull codes from a pre-allocated
	///  'replacement' list, or something). This returns stats on those theoretical codes too, but the numbers are all 0.
	///  
	/// - Returns: <doc:RegistrationCodeStatsData> 
	func regCodeStatsHandler(_ req: Request) async throws -> RegistrationCodeStatsData {
		let codeCount = try await RegistrationCode.query(on: req.db).count()
		let usedCodes = try await RegistrationCode.query(on: req.db).filter(\.$user.$id != nil).count()
		return RegistrationCodeStatsData(allocatedCodes: codeCount, usedCodes: usedCodes, 
					unusedCodes: codeCount - usedCodes, adminCodes: 0)
	}
	
	/// `GET /api/v3/admin/regcodes/find/:search_string`
	/// 
	///  Checks whether a user has been associated with a registration code. Can also be used to check whether a reg code is valid.
	///  Throws when the reg code is not found primarily to help differentiate between "No reg code found" "No User Found" and "User Found" cases.
	///  
	/// - Throws: 400 Bad Request if the reg code isn't found in the db or if it's malformed. We don't check too thoroughly whether it's well-formed.
	/// - Returns: [] if no user has created an account using this reg code yet. If they have, returns an array containing the UserHeaders of all users associated with
	/// the registration code. The first item in the array will be the primary account.
	func userForRegCodeHandler(_ req: Request) async throws -> [UserHeader] {
		guard let regCode = req.parameters.get(searchStringParam.paramString, as: String.self)?.lowercased() else {
			throw Abort(.badRequest, reason: "Missing search parameter")
		}
		guard regCode.count == 6, regCode.allSatisfy( { $0.isLetter || $0.isNumber }) else {
			throw Abort(.badRequest, reason: "Registration code search parameter is malformed.")
		}
		guard let foundRecord = try await RegistrationCode.query(on: req.db).filter(\.$code == regCode).first() else {
			throw Abort(.badRequest, reason: "\(regCode) is not found in the registration code table.")
		}
		guard let parentUserID = foundRecord.$user.id else {
			// This is the case where the reg code is valid, exists in the table, but hasn't been used to create a user account.
			return []
		}
		let subAccountIDs = try await User.query(on: req.db).filter(\.$parent.$id == parentUserID).all().map { try $0.requireID() }
		return req.userCache.getHeaders([parentUserID] + subAccountIDs)
	}
	
	/// `GET /api/v3/admin/regcodes/findbyuser/:userID`
	/// 
	///  Returns the primary user, all alt users, and registration code for the given user. The input userID can be for the primary user or any of their alts.
	///  If called with a userID that has no associated regcode (e.g. 'admin' or 'moderator'), regCode will be "".
	///  
	/// - Throws: 400 Bad Request if the userID isn't found in the db or if it's malformed.
	/// - Returns: [] if no user has created an account using this reg code yet. If they have, returns a one-item array containing the UserHeader of that user.
	func regCodeForUserHandler(_ req: Request) async throws -> RegistrationCodeUserData {
		let user = try await User.findFromParameter(userIDParam, on: req)
		let allAccounts = try await user.allAccounts(on: req.db)
		let userIDs = try allAccounts.map { try $0.requireID() }
		let regCodeResult = try await RegistrationCode.query(on: req.db).filter(\.$user.$id ~~ userIDs).first()
		let regCode = regCodeResult?.code ?? ""
		let resultUsers = req.userCache.getHeaders(userIDs)
		return RegistrationCodeUserData(users: resultUsers, regCode: regCode)
	}
	
// MARK: - Promote/Demote
	/// `GET /api/v3/admin/moderators`
	/// 
	///  Returns a list of all site moderators. Only THO and above may call this method.
	///  
	/// - Returns: Array of <doc:UserHeader>.
	func getModeratorsHandler(_ req: Request) async throws -> [UserHeader] {
		let mods = try await User.query(on: req.db).filter(\.$accessLevel == .moderator).all()
		return try mods.map { try UserHeader(user: $0) }
	}
	
	/// `POST /api/v3/admin/moderator/promote/:user_id`
	/// 
	/// Makes the target user a moderator. Only admins may call this method. The user must have an access level of `.verified` and not 
	/// be temp-quarantined. Unlike the Moderator method that sets access levels, mod promotion only affects the requested account, not
	/// other sub-accounts held by the same user.
	///  
	/// - Throws: badRequest if the target user isn't verified, or if they're temp quarantined.
	/// - Returns: 200 OK if the user was made a mod.
	func makeModeratorHandler(_ req: Request) async throws -> HTTPStatus {
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		try guardNotSpecialAccount(targetUser)
		if targetUser.accessLevel == .moderator {
			throw Abort(.badRequest, reason: "Cannot promote: User is already a moderator.")
		}
		if targetUser.accessLevel > .moderator {
			throw Abort(.badRequest, reason: "Cannot promote to moderator: Access level is above moderator!")
		}
		guard targetUser.accessLevel == .verified else {
			throw Abort(.badRequest, reason: "Only verified users may be promoted to moderators.")
		}
		if let tempQuarantineEndTime = targetUser.tempQuarantineUntil {
			guard tempQuarantineEndTime <= Date() else {
				throw Abort(.badRequest, reason: "Temp Quarantined users may not be promoted to moderators.")
			}
		}
		targetUser.accessLevel = .moderator
		try await targetUser.save(on: req.db)
		try await req.userCache.updateUser(targetUser.requireID())
		// TODO: Might want to make the creation of a mod a ModeratorAction so it'll get tracked?
		return .ok
	}
	
	/// `POST /api/v3/admin/user/demote/:user_id`
	/// 
	/// Sets the target user's accessLevel to `.verified` if it was `.moderator`, `.twitarrteam`, or `.tho`. 
	/// Must be THO or higher to call any of these; must be admin to demote THO users.
	///  
	/// - Throws: badRequest if the target user isn't a mod.
	/// - Returns: 200 OK if the user was demoted successfully.
	func demoteToVerifiedHandler(_ req: Request) async throws -> HTTPStatus {
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		guard targetUser.accessLevel >= .moderator else {
			throw Abort(.badRequest, reason: "User is not at moderator/twitarrteam/THO level: cannot demote to verified.")
		}
		try guardNotSpecialAccount(targetUser)
		targetUser.accessLevel = .verified
		try await targetUser.save(on: req.db)
		try await req.userCache.updateUser(targetUser.requireID())
		return .ok
	}
	
	/// `GET /api/v3/admin/twitarrteam`
	/// 
	///  Returns a list of all TwitarrTeam members. Only THO and above may call this method.
	///  
	/// - Returns: Array of <doc:UserHeader>.
	func getTwitarrTeamHandler(_ req: Request) async throws -> [UserHeader] {
		let twitarrTeam = try await User.query(on: req.db).filter(\.$accessLevel == .twitarrteam).all()
		return try twitarrTeam.map { try UserHeader(user: $0) }
	}
	
	/// `POST /api/v3/admin/twitarrteam/promote/:user_id`
	/// 
	/// Makes the target user a member of TwitarrTeam. Only admins may call this method. The user must have an access level of `.verified` and not 
	/// be temp-quarantined.
	///  
	/// - Throws: badRequest if the target user isn't verified, or if they're temp quarantined.
	/// - Returns: 200 OK if the user was made a mod.
	func makeTwitarrTeamHandler(_ req: Request) async  throws -> HTTPStatus {
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		try guardNotSpecialAccount(targetUser)
		if targetUser.accessLevel == .twitarrteam {
			throw Abort(.badRequest, reason: "Cannot promote: User is already at level twitarrteam.")
		}
		if targetUser.accessLevel > .twitarrteam {
			throw Abort(.badRequest, reason: "Cannot promote to twitarrteam: Access level is above twitarrteam!")
		}
		guard targetUser.accessLevel >= .verified else {
			throw Abort(.badRequest, reason: "Only verified users may be promoted to twitarrteam.")
		}
		if let tempQuarantineEndTime = targetUser.tempQuarantineUntil {
			guard tempQuarantineEndTime <= Date() else {
				throw Abort(.badRequest, reason: "Temp Quarantined users may not be promoted to twitarrteam.")
			}
		}
		targetUser.accessLevel = .twitarrteam
		try await targetUser.save(on: req.db)
		try await req.userCache.updateUser(targetUser.requireID())
		return .ok
	}
	
	/// `GET /api/v3/admin/tho`
	/// 
	///  Returns a list of all users with THO access level. Only THO and Admin may call this method.
	///  
	///  THO access level lets users promote other users to Modaerator and TwitarrTeam access, and demote to Banned status. THO users can also post notifications
	///  and set daily themes.
	///  
	/// - Returns: Array of <doc:UserHeader>.
	func getTHOHandler(_ req: Request) async throws -> [UserHeader] {
		let tho = try await User.query(on: req.db).filter(\.$accessLevel == .tho).all()
		return try tho.map { try UserHeader(user: $0) }
	}
	
	/// `POST /api/v3/admin/tho/promote/:user_id`
	/// 
	/// Makes the target user a member of THO (The Home Office). Only admins may call this method. The user must have an access level of `.verified` and not 
	/// be temp-quarantined.
	///  
	/// - Throws: badRequest if the target user isn't verified, or if they're temp quarantined.
	/// - Returns: 200 OK if the user was made a mod.
	func makeTHOHandler(_ req: Request) async throws -> HTTPStatus {
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		try guardNotSpecialAccount(targetUser)
		if targetUser.accessLevel == .tho {
			throw Abort(.badRequest, reason: "Cannot promote: User is already at level THO.")
		}
		if targetUser.accessLevel > .tho {
			throw Abort(.badRequest, reason: "Cannot promote to THO: Access level is above THO!")
		}
		guard targetUser.accessLevel >= .verified else {
			throw Abort(.badRequest, reason: "Only verified users may be promoted to THO.")
		}
		if let tempQuarantineEndTime = targetUser.tempQuarantineUntil {
			guard tempQuarantineEndTime <= Date() else {
				throw Abort(.badRequest, reason: "Temp Quarantined users may not be promoted to THO.")
			}
		}
		targetUser.accessLevel = .tho
		try await targetUser.save(on: req.db)
		try await req.userCache.updateUser(targetUser.requireID())
		return .ok
	}
	
	/// `GET /api/v3/admin/userroles/:user_role`
	/// 
	///  Returns a list of all users that have the given role.
	///  
	/// - Returns: Array of <doc:UserHeader>.
	func getUsersWithRole(_ req: Request) async throws -> [UserHeader] {
		guard let parameter = req.parameters.get(userRoleParam.paramString) else {
			throw Abort(.badRequest, reason: "No UserRoleType found in request.")
		}
		let role = try UserRoleType(fromAPIString: parameter)		
		let userIDsWithRole = try await User.query(on: req.db).join(UserRole.self, on: \User.$id == \UserRole.$user.$id)
				.filter(UserRole.self, \.$role == role).all(\.$id)
		return req.userCache.getHeaders(userIDsWithRole)
	}
	
	/// `POST /api/v3/admin/userroles/:user_id/addrole/:user_role`
	/// 
	/// Adds the given role to the given user's role list. Only THO and above may call this method.
	///  
	/// - Throws: badRequest if the target user already has the role.
	/// - Returns: 200 OK if the user now has the given role.
	func addRoleForUser(_ req: Request) async throws -> HTTPStatus {
		let targetUser = try await User.findFromParameter(userIDParam, on: req)
		guard let userRoleString = req.parameters.get(userRoleParam.paramString) else {
			throw Abort(.badRequest, reason: "No UserRoleType found in request.")
		}
		let targetUserID = try targetUser.requireID()
		let role = try UserRoleType(fromAPIString: userRoleString)		
		if let _ = try await UserRole.query(on: req.db).filter(\.$role == role).filter(\.$user.$id == targetUserID).first() {
			throw Abort(.badRequest, reason: "User \(targetUser.username) already has role of \(role.label)")
		}
		try await UserRole(user: targetUserID, role: role).create(on: req.db)
		try await req.userCache.updateUser(targetUserID)
		return .ok
	}
	
	/// `POST /api/v3/admin/userroles/:user_id/removerole/:user_role`
	/// 
	/// Removes the given role from the target user's role list. Only THO and above may call this method.
	///  
	/// - Throws: badRequest if the target user isn't a Karaoke Manager.
	/// - Returns: 200 OK if the user was demoted successfully.
	func removeRoleForUser(_ req: Request) async throws -> HTTPStatus {
		guard let userRoleString = req.parameters.get(userRoleParam.paramString) else {
			throw Abort(.badRequest, reason: "No UserRoleType found in request.")
		}
		let role = try UserRoleType(fromAPIString: userRoleString)		
		guard let targetUserIDStr = req.parameters.get(userIDParam.paramString), let targetUserID = UUID(targetUserIDStr) else {
			throw Abort(.badRequest, reason: "Missing user ID parameter.")
		}
		try await UserRole.query(on: req.db).filter(\.$role == role).filter(\.$user.$id == targetUserID).delete()
		try await req.userCache.updateUser(targetUserID)
		return .ok
	}


// MARK: - Utilities

	// Gets the path where the uploaded schedule is kept. Only one schedule file can be in the hopper at a time.
	// This fn ensures intermediate directories are created.
	func uploadSchedulePath() throws -> URL {
		let filePath = Settings.shared.adminDirectoryPath.appendingPathComponent("uploadschedule.ics")
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

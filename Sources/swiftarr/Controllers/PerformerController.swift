import Fluent
import FluentSQL
import Vapor
import CoreXLSX

/// The collection of `/api/v3/performer/*` route endpoints and handler functions related to the official performers and shadow event organizers..
struct PerformerController: APIRouteCollection {

	// Returned by the Excel spreadsheet parser. Used to match events from the spreadsheet to events in the db, and then
	// link those events to performers.
	struct PerformerLinksData {
		var eventTime: Date
		var eventName: String
		var performerNames: [String]
	}
	
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/users endpoints
		let performerRoutes = app.grouped("api", "v3", "performer")

		// Flexible access endpoints that behave differently for logged-in users
		let optionalAuthGroup = performerRoutes.flexRoutes(feature: .performers)
		optionalAuthGroup.get("official", use: getOfficialPerformers).setUsedForPreregistration()
		optionalAuthGroup.get("shadow", use: getShadowPerformers).setUsedForPreregistration()
		optionalAuthGroup.get(performerIDParam, use: getPerformer).setUsedForPreregistration()

		// endpoints available only when logged in
		let tokenAuthGroup = performerRoutes.tokenRoutes(feature: .performers)
		tokenAuthGroup.get("self", use: getSelfPerformer).setUsedForPreregistration()
		tokenAuthGroup.post("forevent", eventIDParam, use: addSelfPerformerForEvent).setUsedForPreregistration()
		tokenAuthGroup.post("self", use: editSelfPerformer).setUsedForPreregistration()
		tokenAuthGroup.post("self", "delete", use: deleteSelfPerformer).setUsedForPreregistration()
		tokenAuthGroup.delete("self", use: deleteSelfPerformer).setUsedForPreregistration()
		tokenAuthGroup.post("forevent", eventIDParam, "delete", use: deleteSelfPerformerForEvent).setUsedForPreregistration()
		tokenAuthGroup.delete("forevent", eventIDParam, use: deleteSelfPerformerForEvent).setUsedForPreregistration()

		// Endpoints available to TT and up
		let ttAuthGroup = app.tokenRoutes(feature: .performers, minAccess: .twitarrteam, path: "api", "v3", "admin")
		ttAuthGroup.post("performer", "upsert", use: upsertPerformer)
		ttAuthGroup.post("performer", "link", "upload", use: uploadPerformerLinkSpreadsheet)
		ttAuthGroup.get("performer", "link", "verify", use: performerLinkVerificationHandler)
		ttAuthGroup.post("performer", "link", "apply", use: performerLinkApplyHandler)
		ttAuthGroup.delete("performer", performerIDParam, use: deletePerformerHandler).setUsedForPreregistration()
	}
	
// MARK: Getting Performer Data
	
	/// `GET /api/v3/performer/official`
	///
	///  Gets the list of official performers. Should match what's on jococruise.com and on Sched.com when deployed; for the rest of the year, data should be loaded that
	///  matches the schedule data. That is, we move to next year's performers when next year's schedule comes out, even though performer info is iusually released long
	///  before the schedule.
	///
	/// **URL Query Parameters:**
	///	* `?start=INT` - Offset from start of results set
	/// * `?limit=INT` - the maximum number of games to retrieve: 1-200, default is 50.
	func getOfficialPerformers(_ req: Request) async throws -> PerformerResponseData {
		let start = req.query[Int.self, at: "start"] ?? 0
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = Performer.query(on: req.db).filter(\.$officialPerformer == true).sort(\.$sortOrder)
		let performerCount = try await query.count()
		let performers = try await query.copy().range(start..<(start+limit)).all()
		let performerDataArray = try performers.map { try PerformerHeaderData($0) }
		return PerformerResponseData(performers: performerDataArray, paginator: Paginator(total: performerCount, start: start, limit: limit))
	}
	
	/// `GET /api/v3/performer/shadow`
	///
	/// Gets the list of shadow event organizers. We haven't been told that we need to keep the official performer list separate from the shadow performers list, but if 
	/// someone puts them in the same list it in their UI, we probably will get told to separate them.
	/// 
	/// Currently shadow cruise organizers can fill in their Performer form themselves during pre-registration (before cruise embarks, after shadow events are put on the schedule).
	/// The form doesn't include years attended or social media links; those fields will be empty.
	///
	/// **URL Query Parameters:**
	///	* `?start=INT` - Offset from start of results set
	/// * `?limit=INT` - the maximum number of games to retrieve: 1-200, default is 50.
	func getShadowPerformers(_ req: Request) async throws -> PerformerResponseData {
		let start = req.query[Int.self, at: "start"] ?? 0
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let query = Performer.query(on: req.db).filter(\.$officialPerformer == false).sort(\.$sortOrder)
				.join(User.self, on: \Performer.$user.$id == \User.$id)
				.filter(User.self, \.$accessLevel != .banned)
		let performerCount = try await query.count()
		let performers = try await query.copy().range(start..<(start+limit)).with(\.$events).all()
		let performerDataArray = try performers.map { try PerformerHeaderData($0) }
		return PerformerResponseData(performers: performerDataArray, paginator: Paginator(total: performerCount, start: start, limit: limit))
	}
		
	/// `GET /api/v3/performer/self`
	///
	/// Returns the Performer data for the current user. Only Shadow Event organizers have their Performer data associated with their Twitarr user.
	func getSelfPerformer(_ req: Request) async throws -> PerformerData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let performer = try await Performer.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
				.with(\.$events, { event in event.with(\.$performers) }).first() else {
			return PerformerData()
		}
		let favorites = try await getFavorites(in: req, from: performer.events)
		return try PerformerData(performer, favoriteEventIDs: favorites, user: cacheUser.makeHeader())
	}
	
	/// `GET /api/v3/performer/:performer_id`
	///
	/// Returns the Performer data for the given performer ID. Performer ID is separate from userID,
	func getPerformer(_ req: Request) async throws -> PerformerData {
		guard let performerID = req.parameters.get(performerIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Request parameter identifying Performer is missing.")
		}
		guard let performer = try await Performer.query(on: req.db).filter(\.$id == performerID)
			.with(\.$events, { event in event.with(\.$performers) }).first()  else {
			throw Abort(.badRequest, reason: "No Performer profile found with given ID ")
		}
		let favorites = try await getFavorites(in: req, from: performer.events)
		var result = try PerformerData(performer, favoriteEventIDs: favorites)
		// Mods and above can identify the Twitarr user who made the Performer, as can themselves.
		if let currentUser = req.auth.get(UserCacheData.self), let userID = performer.$user.id, currentUser.accessLevel.hasAccess(.moderator) || currentUser.userID == userID {
			result.user = try req.userCache.getHeader(userID)
		}
		return result
	}
	
// MARK: Modifying Performer Data
		
	/// `POST /api/v3/performer/forevent/:event_id`
	///
	/// Creates or updates a Performer profile for the current user, associating them with the given event if they're not already associated with it. This method is only for
	/// shadow events, but can be called by any verified user. Each user may only have one Performer associated with it, so if this user already has a Perfomer profile
	/// the new data updates it.
	/// 
	/// When associating a shadow event organizer a new event, callers should take care to call `/api/v3/performer/self` to check if this user
	/// has a profile already and if so, return their existing Performer fields--unless the user wants to edit them.
	/// 
	/// Does not currently use the `eventUIDs'`array in `PerformerUploadData`. This method could be modified to use this field, allowing multiple events to be 
	/// set for a performer at once.
	///
	/// - Parameter eventID: in URL path
	/// - Parameter PerformerUploadData: JSON POST content.
	/// - Returns: HTTP status.
	func addSelfPerformerForEvent(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let userReg = try await RegistrationCode.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first() else {
			throw Abort(.badRequest, reason: "No registration code found for this user. Only users created with registration codes may make Performer profiles.")
		}
		// Discord-linked accounts *can* create Performer profiles, they just won't get transferred to the boat. Anyone with a Discord-linked account
		// should eventually get a JoCo reg code to use for their 'real' account. If someone wants to try making a Performer profile early, they
		// can get the UserRole, and we'll remind them it's just for testing.
		guard !userReg.isDiscordUser || cacheUser.userRoles.contains(.performerselfeditor) else {
			throw Abort(.badRequest, reason: "This account is linked to a Discord user and won't be transferred to the ship when we sail. You should get a registration code from JoCo that will work.")
		}
		guard Settings.shared.enablePreregistration || cacheUser.userRoles.contains(.performerselfeditor) else {
			throw Abort(.forbidden, reason: "Editing your Performer profile is limited to pre-registration; see the Help Desk if you need to change something.")
		}
		guard let eventID = req.parameters.get(eventIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Request parameter identifying Event is missing.")
		}
		guard let _ = try await Event.find(eventID, on: req.db) else {
			throw Abort(.badRequest, reason: "Event ID doesn't match any event in database.")
		}		 
		let eventCount = try await EventPerformer.query(on: req.db)
				.join(Performer.self, on: \EventPerformer.$performer.$id == \Performer.$id)
				.filter(Performer.self, \.$user.$id == cacheUser.userID).count()
		guard eventCount <= 5 else {
			throw Abort(.badRequest, reason: "Twitarr doesn't let a single person be the organizer for more than 5 Shadow Events as an anti-brigading defense. If you're actually the organizer for all these events (not ATTENDING them, ORGANIZING them) let us know.")
		}
		let uploadData = try req.content.decode(PerformerUploadData.self)
		// This will attempt to look up the callers existing Performer record, even if it is deleted.
		// If they have none then a blank one is created. This is to ensure that there is only ever
		// one Performer per User.
		var performer = try await Performer.query(on: req.db).filter(\.$user.$id == cacheUser.userID).withDeleted().first() ?? Performer()
		if (performer.deletedAt != nil) {
			try await performer.restore(on: req.db)
		}
		try await buildPerformerFromUploadData(performer: &performer, uploadData: uploadData, on: req)
		performer.officialPerformer = false
		performer.$user.id = cacheUser.userID
		let performerForCapture = performer
		try await req.db.transaction { database in
			try await performerForCapture.save(on: database)			// Updates or creates
			let attachedEvent = try await EventPerformer.query(on: database).filter(\.$performer.$id == performerForCapture.requireID())
					.filter(\.$event.$id == eventID).first() 
			if attachedEvent == nil {
				let newEventPerformer = EventPerformer()
				newEventPerformer.$performer.id = try performerForCapture.requireID()
				newEventPerformer.$event.id = eventID
				try await newEventPerformer.save(on: database)
			}
		}
		return .ok
	}

	/// `POST /api/v3/performer/self`
	///
	/// Creates or updates a Performer profile for the current user. This method can be called
	/// by any verified user. Each user may only have one Performer associated with it, so if
	/// this user already has a Perfomer profile the new data updates it.
	/// 
	/// When updating a profile, callers should take care to call `/api/v3/performer/self` to
	/// check if this user has a profile already and if so, return their existing Performer
	/// fields--unless the user wants to edit them.
	/// 
	/// Does not currently use the `eventUIDs'`array in `PerformerUploadData`. This method
	/// could be modified to use this field, allowing multiple events to be set for a performer
	/// at once.
	///
	/// I think we should eventually make a `POST /api/v3/performer/:performer_ID` edit endpoint
	/// that conditionally requires twitarrTeam authentication whether you're editing your own
	/// profile or an official profile. There is some functionality duplicated with upsertPerformer
	/// at `POST /api/v3/performer/upsert`.
	///
	/// - Parameter PerformerUploadData: JSON POST content.
	/// - Returns: HTTP status.
	func editSelfPerformer(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let userReg = try await RegistrationCode.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first() else {
			throw Abort(.badRequest, reason: "No registration code found for this user. Only users created with registration codes may make Performer profiles.")
		}
		// Discord-linked accounts *can* create Performer profiles, they just won't get transferred to the boat. Anyone with a Discord-linked account
		// should eventually get a JoCo reg code to use for their 'real' account. If someone wants to try making a Performer profile early, they
		// can get the UserRole, and we'll remind them it's just for testing.
		guard !userReg.isDiscordUser || cacheUser.userRoles.contains(.performerselfeditor) else {
			throw Abort(.badRequest, reason: "This account is linked to a Discord user and won't be transferred to the ship when we sail. You should get a registration code from JoCo that will work.")
		}
		guard Settings.shared.enablePreregistration || cacheUser.userRoles.contains(.performerselfeditor) else {
			throw Abort(.forbidden, reason: "Editing your Performer profile is limited to pre-registration; see the Help Desk if you need to change something.")
		}
		let uploadData = try req.content.decode(PerformerUploadData.self)
		var performer = try await Performer.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first() ?? Performer()
		try await buildPerformerFromUploadData(performer: &performer, uploadData: uploadData, on: req)
		performer.officialPerformer = false
		performer.$user.id = cacheUser.userID
		try await performer.save(on: req.db) // Updates or creates
		return .ok
	}

	
	/// `POST /api/v3/performer/self/delete`
	/// `DELETE /api/v3/performer/self/performer`
	/// 
	///  Deletes a shadow event organizer's Performer record and any of their EventPerformer records (linking their Performer to their Events).
	func deleteSelfPerformer(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let performer = try await Performer.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first() else {
			throw Abort(.badRequest, reason: "User does not have a performer profile.")
		}
		guard Settings.shared.enablePreregistration || cacheUser.userRoles.contains(.performerselfeditor) || cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Editing your Performer profile is limited to pre-registration; see the Help Desk if you need to change something.")
		}
		try await EventPerformer.query(on: req.db).filter(\.$performer.$id == performer.requireID()).delete()
		try await performer.delete(on: req.db)
		return .ok
	}

	/// `POST /api/v3/performer/forevent/:event_ID/delete`
	/// `DELETE /api/v3/performer/forevent/:event_ID`
	/// 
	/// Removes the callers shadow event organizer Performer from the given Event.
	/// At this time this capability has not been added to the site UI. Those users will
	/// still delete their entire profile to remove from an event.
	func deleteSelfPerformerForEvent(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let performer = try await Performer.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first() else {
			return .noContent
		}
		guard Settings.shared.enablePreregistration || cacheUser.userRoles.contains(.performerselfeditor) || cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Editing your Performer profile is limited to pre-registration; see the Help Desk if you need to change something.")
		}
		guard let eventID = req.parameters.get(eventIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Request parameter identifying Event is missing.")
		}
		guard let _ = try await Event.find(eventID, on: req.db) else {
			throw Abort(.badRequest, reason: "Event ID doesn't match any event in database.")
		}		 
		let eventCount = try await EventPerformer.query(on: req.db)
				.join(Performer.self, on: \EventPerformer.$performer.$id == \Performer.$id)
				.filter(Performer.self, \.$user.$id == cacheUser.userID).count()
		guard eventCount <= 5 else {
			throw Abort(.badRequest, reason: "Twitarr doesn't let a single person be the organizer for more than 5 Shadow Events as an anti-brigading defense. If you're actually the organizer for all these events (not ATTENDING them, ORGANIZING them) let us know.")
		}

		let eventPerformerQuery = try EventPerformer.query(on: req.db)
			.filter(\.$performer.$id == performer.requireID())
			.filter(\.$event.$id == eventID)

		guard let eventPerformer = try await eventPerformerQuery.first() else {
			return .noContent
		}

		try await eventPerformer.delete(on: req.db)
		return .ok
	}
	
// MARK: TwitarrTeam methods
	
	/// `POST /api/v3/admin/performer/upsert`
	///
	/// Creates or updates a Performer profile. This method may create official Performer models, and may edit Official or Shadow performers.
	/// This method does not associate the performer with any events. 
	/// 
	/// The idea behind this method is that we'll be using a bulk import method to associate events with performers, but may not end up using bulk import for performers. 
	/// 
	/// - Parameter PerformerUploadData: JSON POST content.
	/// - Returns: HTTP status.
	func upsertPerformer(_ req: Request) async throws -> HTTPStatus {
		let uploadData = try req.content.decode(PerformerUploadData.self)
		if uploadData.name == "" {
			throw Abort(.badRequest, reason: "Name field cannot be empty.")
		}
		var existingPerformer: Performer?
		if let performerID = uploadData.performerID {
			existingPerformer = try await Performer.query(on: req.db).filter(\.$id == performerID).first() 
			guard existingPerformer != nil else {
				throw Abort(.badRequest, reason: "No performer found with id \(performerID)")
			}
		}
		else {
			// As a backup, in an attempt to prevent duplicate entries, check for name match if no performerID was provided
			// This could happen if a user does an 'add' of a performer that already exists.
			existingPerformer = try await Performer.query(on: req.db).filter(\.$name == uploadData.name).first()
		}
		var performer = existingPerformer ?? Performer()
		try await buildPerformerFromUploadData(performer: &performer, uploadData: uploadData, on: req)
		try await performer.save(on: req.db)			// Updates or creates
		return .ok
	}
	
	/// `GET /api/v3/performer/link/upload`
	///
	/// Uploads a Excel spreadsheet containing a list of events and which performers (by name) that will be performing at each event.
	/// 
	/// - Returns:`EventPerformerValidationData`
	func uploadPerformerLinkSpreadsheet(_ req: Request) async throws -> HTTPStatus {
		let fileData = try req.content.decode(Data.self)
		let filepath = try uploadedPerformerLinksPath()
		// If we attempt an upload, it's important we end up with the uploaded file or nothing at the filepath.
		// Leaving the previous file there would be bad.
		try? FileManager.default.removeItem(at: filepath)
		try await req.fileio.writeFile(ByteBuffer(data: fileData), at: filepath.path)
		return .ok
	}
	
	/// `GET /api/v3/performer/link/verify`
	///
	/// Parses the Excel file uploaded in `uploadPerformerLinkSpreadsheet()`, matches events listed in the spreadsheet to database Events,
	/// matches performer names in the spread sheet to Performers in the db.
	/// 
	/// This method doesn't modify the db, it just does all the matching and reports any errors.
	/// 
	/// - Returns:`EventPerformerValidationData`
	func performerLinkVerificationHandler(_ req: Request) async throws -> EventPerformerValidationData {
		let filepath = try uploadedPerformerLinksPath()
		let buffer = try await req.fileio.collectFile(at: filepath.path)
		guard let fileData = buffer.getData(at: 0, length: buffer.readableBytes) else {
			throw Abort(.badRequest, reason: "Could not read performer/event links file.")
		}
		var (events, errors) = try parsePerformerLinksExcelDoc(from: fileData)
		let performers = events.reduce(Set<String>()) { $0.union($1.performerNames) }
		let dbEvents = try await Event.query(on: req.db).all()
		let dbPerformers = try await Performer.query(on: req.db).filter(\.$officialPerformer == true).all()
		var matchedEventCount = 0
		var unmatchedEventCount = 0
		for event in events {
			if let _ = dbEvents.first(where: { $0.startTime == event.eventTime && $0.title == event.eventName }) {
				matchedEventCount += 1
			}
			else {
				let dateFormatter = DateFormatter()
				dateFormatter.dateStyle = .short
				dateFormatter.timeStyle = .short
				dateFormatter.locale = Locale(identifier: "en_US")
				dateFormatter.timeZone = Settings.shared.timeZoneChanges.tzAtTime(event.eventTime)
				let startTimeString = "\(dateFormatter.string(from: event.eventTime)) \(dateFormatter.timeZone.abbreviation() ?? "")"
				errors.append("Excel event '\(event.eventName)' starting at \(startTimeString) didn't match any event in DB.")
				unmatchedEventCount += 1
			}
		}
		// Validations using the performer and event lists
		let dbPerformerNames = Set(dbPerformers.map { $0.name })
		let excelPerformerNames = Set(performers)
		let missingPerformerNames = excelPerformerNames.subtracting(dbPerformerNames)
		let noEventPerformerNames = dbPerformerNames.subtracting(excelPerformerNames)
		if missingPerformerNames.count > 0 {
			errors.append("\(missingPerformerNames.count) performers mentioned in the spreadsheet didn't match up to any Performer name in the DB: \(missingPerformerNames)")
		}
		if noEventPerformerNames.count > 0 {
			errors.append("\(noEventPerformerNames.count) performers in the DB don't seem to be performing at any event: \(noEventPerformerNames)")
		}
		// We don't check the EventPerformer pivots here because the spreadsheet is always supposed to be definitive and complete for these.
		// When we execute the update, we'll delete all existing EventPerformer pivots for official performers and then create updated ones.
		// The idea is that, on verify, telling the user that the operation will create 5 more pivots and delete one isn't useful.
		return EventPerformerValidationData(oldPerformerCount: dbPerformers.count, newPerformerCount: performers.count,
				missingPerformerCount: missingPerformerNames.count, noEventsPerformerCount: noEventPerformerNames.count, 
				eventsWithPerformerCount: matchedEventCount, unmatchedEventCount: unmatchedEventCount, errors: errors)
	}
	
	/// `GET /api/v3/performer/link/apply`
	///
	///	Parses the Excel file uploaded in `uploadPerformerLinkSpreadsheet()`, matches events listed in the spreadsheet to database Events,
	/// matches performer names in the spread sheet to Performers in the db, creates EventPerformer pivots linking Events and their Performers.
	/// 
	/// This method deletes all existing EventPerformer pivots for official performers before saving the new ones; the assumption is that the Excel spreadsheet is the new 
	/// definitive (and complete) source for which performers are at which events.
	/// 
	/// - Returns:HTTP status.
	func performerLinkApplyHandler(_ req: Request) async throws -> HTTPStatus {
		let filepath = try uploadedPerformerLinksPath()
		let buffer = try await req.fileio.collectFile(at: filepath.path)
		guard let fileData = buffer.getData(at: 0, length: buffer.readableBytes) else {
			throw Abort(.badRequest, reason: "Could not read performer/event links file.")
		}
		let (events, _) = try parsePerformerLinksExcelDoc(from: fileData)
		let dbEvents = try await Event.query(on: req.db).all()
		let dbPerformers = try await Performer.query(on: req.db).filter(\.$officialPerformer == true).all()
		var builtPerformerPivots = [EventPerformer]()
		for event in events {
			if let foundEvent = dbEvents.first(where: { $0.startTime == event.eventTime && $0.title == event.eventName }) {
				for performerName in event.performerNames {
					if let foundPerformer = dbPerformers.first(where: { $0.name == performerName }) {
						builtPerformerPivots.append(try EventPerformer(event: foundEvent, performer: foundPerformer))
					}
				}
			}
		}
		let pivots = try await EventPerformer.query(on: req.db).join(Performer.self, on: \EventPerformer.$performer.$id == \Performer.$id)
				.filter(Performer.self, \.$officialPerformer == true).all()
		try await pivots.delete(on: req.db)
		try await builtPerformerPivots.create(on: req.db)
		return .ok
	}

	// `DELETE /api/v3/performer/:performer_ID`
	//
	// Delete a performer profile.
	func deletePerformerHandler(_ req: Request) async throws -> HTTPStatus {
		guard let performerID = req.parameters.get(performerIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Request parameter identifying Performer is missing.")
		}
		if let performer = try await Performer.query(on: req.db).filter(\.$id == performerID).first() {
			try await performer.delete(on: req.db)
			return .ok
		}
		return .noContent
	}
	
	// MARK: Utilities
	
	// Gets the path where the uploaded schedule is kept. Only one schedule file can be in the hopper at a time.
	// This fn ensures intermediate directories are created.
	func uploadedPerformerLinksPath() throws -> URL {
		let filePath = Settings.shared.adminDirectoryPath.appendingPathComponent("uploadperformerlinks.ics")
		return filePath
	}

	// Returns a set of EventIDs indicating which of hte given events are favorited by the current user, or an empty set
	// if no user is logged in. 
	func getFavorites(in req: Request, from events: [Event]? = nil) async throws -> Set<UUID> {
		guard let cacheUser = req.auth.get (UserCacheData.self) else {
			return Set()
		}
		let query = EventFavorite.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
		if let events = events {
			try query.filter(\.$event.$id ~~ events.map { try $0.requireID() })
		}
		return try await Set(query.all().map { $0.$event.id })
	}
	
	// Fills in a Performer from data in a PerformerUploadData object. Not an initializer because this may be used to
	// update an existing Performer model.
	func buildPerformerFromUploadData(performer: inout Performer, uploadData: PerformerUploadData, on req: Request) async throws {
		performer.name = uploadData.name.trimmingCharacters(in: .whitespaces)
		performer.sortOrder = (performer.name.split(separator: " ").last?.string ?? performer.name).uppercased()
		performer.pronouns = uploadData.pronouns
		performer.bio = uploadData.bio
		let photoFilename = uploadData.photo.filename == "" ? nil : uploadData.photo.filename
		performer.photo = try await processImage(data: uploadData.photo.image, usage: .userProfile, on: req) ?? photoFilename
		performer.organization = uploadData.organization
		performer.title = uploadData.title
		performer.yearsAttended = uploadData.yearsAttended.sorted()
		performer.website = uploadData.website
		performer.facebookURL = uploadData.facebookURL
		performer.xURL = uploadData.xURL
		performer.instagramURL = uploadData.instagramURL
		performer.youtubeURL = uploadData.youtubeURL
		performer.officialPerformer = uploadData.isOfficialPerformer
	}
	
	// Uses CoreXLSX to parse the given Excel document, returning an array of `PerformerLinksData` containing identifying information
	// for events along with an array of the performers at the event. Does not return all the fields for the Events; this method isn't 
	// set up to be used as a general importer for Event data. 
	//
	// There's a couple of reasons ton not use this file as a source for Event data. 1) This file doesn't have the event UIDs that Sched
	// has; the UIDs make it possible to determine that an event has changed time and title but is still the same event so people following
	// it still follow it. 2) Single Source of Truth--we have hourly automatic updates set up for Sched's info, if we update events manually
	// from the spreadsheet we could end up auto-reverting on the next automatic update.
	func parsePerformerLinksExcelDoc(from fileData: Data) throws -> ([PerformerLinksData], [String]){
		var events = [PerformerLinksData]()
		var errors = [String]()
		var foundFullScheduleSheet = false
		var sheetCount = 0
		let spreadsheet = try XLSXFile(data: fileData)
		let sharedStrings = try spreadsheet.parseSharedStrings()
		for wbk in try spreadsheet.parseWorkbooks() {
			for (name, path) in try spreadsheet.parseWorksheetPathsAndNames(workbook: wbk) {
				sheetCount += 1
				if name == "Full Schedule" {
					foundFullScheduleSheet = true
				}
	  			let worksheet = try spreadsheet.parseWorksheet(at: path)
	  			guard let row1 = worksheet.data?.rows.first(where: { $0.reference == 1 }) else {
	  				continue
	  			}
	  			let dayCol = findExcelHeaderColumn(named: "Day", in: row1, sharedStrings: sharedStrings, defaultValue: "A", errors: &errors)
	  			let startCol = findExcelHeaderColumn(named: "Start", in: row1, sharedStrings: sharedStrings, defaultValue: "B", errors: &errors)
	  			let eventNameCol = findExcelHeaderColumn(named: "EventName", in: row1, sharedStrings: sharedStrings, defaultValue: "G", errors: &errors)
	  			let featuringCol = findExcelHeaderColumn(named: "Featuring", in: row1, sharedStrings: sharedStrings, defaultValue: "J", errors: &errors)
				for row in worksheet.data?.rows ?? [] {
					if row.reference == 1 {
						continue
					}
					if let featuring = cellValue(in: row, col: featuringCol, sharedStrings: sharedStrings), 
							let day = cellValue(in: row, col: dayCol, sharedStrings: sharedStrings),
							let startTime = cellValue(in: row, col: startCol, sharedStrings: sharedStrings), 
							let eventName = cellValue(in: row, col: eventNameCol, sharedStrings: sharedStrings) {
						guard var weekday = Calendar.current.shortWeekdaySymbols.firstIndex(of: day) else {
							errors.append("In Row \(row.reference): Couldn't convert '\(day)' into a 0-6 day of week index. Skipping row.")
							continue
						}
						weekday += 1 // 1...7
						// The "Start" cell can have the value "All Day" instead of a time. These events transform into 7:00AM until Midnight, local time.
						var hours = 7
						var minutes = 0
						if startTime != "All Day" {
							let startTimeComponents = startTime.split(separator: ":")
							guard startTimeComponents.count == 2, let hoursInt = Int(startTimeComponents[0]), (1...12).contains(hoursInt),
									let minutesInt = Int(startTimeComponents[1].prefix(2)),
									(0...59).contains(minutesInt), startTimeComponents[1].lowercased().hasSuffix("am") ||
									startTimeComponents[1].lowercased().hasSuffix("pm") else {
								errors.append("In Row \(row.reference): Couldn't convert '\(startTime)' into ints for hours and minutes. Skipping row.")
								continue
							}
							hours = (hoursInt % 12) + (startTimeComponents[1].lowercased().hasSuffix("pm") ? 12 : 0)
							minutes = minutesInt
						}
						
						let portCalendar = Settings.shared.getPortCalendar()
						let timeOfDayComponents = DateComponents(calendar: portCalendar, timeZone: portCalendar.timeZone, 
								hour: hours, minute: minutes, weekday: weekday)
						guard let approxEventTime = portCalendar.nextDate(after: Settings.shared.cruiseStartDate(), matching: timeOfDayComponents, 
								matchingPolicy: .nextTime) else {
							errors.append("In Row \(row.reference): Couldn't create Date object by offsetting CruiseStartDate by '\(day)' and '\(startTime)'. Skipping row.")
							continue
						}
						let cruiseCalendar = Settings.shared.calendarForDate(approxEventTime)
						guard let eventTime = cruiseCalendar.nextDate(after: Settings.shared.cruiseStartDate(), matching: timeOfDayComponents, 
								matchingPolicy: .nextTime) else {
							errors.append("In Row \(row.reference): Couldn't create Date object by offsetting CruiseStartDate by '\(day)' and '\(startTime)'. Skipping row.")
							continue
						}
						let performerNames = featuring.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
						events.append(PerformerLinksData(eventTime: eventTime, eventName: eventName, performerNames: performerNames))
					}
				}
			}
		}
		if sheetCount > 1 { errors.insert("Document contains multiple worksheets; THO's Full Schedule doc isn't supposed to?", at: 0) }
		if !foundFullScheduleSheet { errors.insert("Didn't find sheet named 'Full Schedule'", at: 0) }
		return (events, errors)
	}
	
	// Returns the worksheet column most likely to contain the data field we're looking for. Examines the header row for a column with the
	// given title. Uses the default column if we can't find a match.
	func findExcelHeaderColumn(named: String, in row: Row, sharedStrings: SharedStrings, defaultValue: String, errors: inout [String]) -> ColumnReference {
		if let defaultCell = row.cells.first(where: { $0.reference.column.value == defaultValue }),
				 let str = defaultCell.stringValue(sharedStrings), str == named {
			return defaultCell.reference.column
		}
		if let foundCell = row.cells.first(where: { $0.stringValue(sharedStrings) == named }) {
			errors.append("Column header '\(named)' not found in default column '\(defaultValue)'. Found it in column '\(foundCell.reference.column.value)' instead; using that.")
			return foundCell.reference.column
		}
		errors.append("Column header '\(named)' not found. Will attempt to use default of '\(defaultValue); hoping this column contains the right data.")
		return ColumnReference(defaultValue)!
	}
	
	// Finds a cell in a row using its column reference.
	func cellValue(in row: Row, col: ColumnReference, sharedStrings: SharedStrings) -> String? {
		return row.cells.first { $0.reference.column == col }?.stringValue(sharedStrings)
	}
}

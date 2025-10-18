import FluentSQL
import Vapor

/// The collection of `/api/v3/admin` route endpoints and handler functions related to admin tasks.
///
/// All routes in this group should be restricted to users with administrator priviliges. This controller returns data of
/// a privledged nature, and has control endpoints for setting overall server state.
struct AdminController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/admin endpoints
		let adminRoutes = app.grouped("api", "v3", "admin")
		
		// Open routes with no auth requirements
		adminRoutes.get("timezonechanges", use: timeZoneChangeHandler).setUsedForPreregistration()

		// endpoints available to TwitarrTeam and above
		let ttAuthGroup = adminRoutes.tokenRoutes(minAccess: .twitarrteam)
		ttAuthGroup.post("schedule", "update", use: scheduleUploadPostHandler)
		ttAuthGroup.get("schedule", "verify", use: scheduleChangeVerificationHandler)
		ttAuthGroup.post("schedule", "update", "apply", use: scheduleChangeApplyHandler)
		ttAuthGroup.get("schedule", "viewlog", use: scheduleChangeLogHandler)
		ttAuthGroup.get("schedule", "viewlog", scheduleLogIDParam, use: scheduleGetLogEntryHandler)
		ttAuthGroup.post("schedule", "reload", use: reloadScheduleHandler)

		ttAuthGroup.get("regcodes", "stats", use: regCodeStatsHandler)
		ttAuthGroup.get("regcodes", "find", searchStringParam, use: userForRegCodeHandler)
		ttAuthGroup.get("regcodes", "findbyuser", userIDParam, use: regCodeForUserHandler)
		ttAuthGroup.get("regcodes", "discord", "allocate", searchStringParam, use: assignDiscordRegCode)

		ttAuthGroup.get("serversettings", use: settingsHandler)
		ttAuthGroup.get("rollup", use: serverRollupCounts)

		ttAuthGroup.post("notifications", "reload", use: triggerConsistencyJobHandler)

		// endpoints available for THO and Admin only
		let thoAuthGroup = adminRoutes.tokenRoutes(minAccess: .tho)
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

		// Routes that only the Admin account can access
		let adminAuthGroup = adminRoutes.tokenRoutes(minAccess: .admin)
		adminAuthGroup.post("serversettings", "update", use: settingsUpdateHandler)
		adminAuthGroup.post("timezonechanges", "reloadtzdata", use: reloadTimeZoneChangeData)
		adminAuthGroup.get("bulkuserfile", "download", use: userfileDownloadHandler)
		adminAuthGroup.on(.POST, "bulkuserfile", "upload", body: .stream,  use: userfileUploadPostHandler)
		adminAuthGroup.get("bulkuserfile", "verify", use: userfileVerificationHandler)
		adminAuthGroup.get("bulkuserfile", "update", "apply", use: userfileApplyHandler)

		// Only admin may promote to THO
		adminAuthGroup.post("tho", "promote", userIDParam, use: makeTHOHandler)
	}

	/// `POST /api/v3/admin/dailytheme/create`
	///
	/// Creates a new daily theme for a day of the cruise (or some other day). The 'day' field is unique, so attempts to create a new record
	/// with the same day as an existing record will fail--instead, you probably want to edit the existing DailyTheme for that day.
	///
	/// - Parameter requestBody: `DailyThemeUploadData`
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
	/// - Parameter requestBody: `DailyThemeUploadData`
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
	/// - Returns: `SettingsAdminData`
	func settingsHandler(_ req: Request) throws -> SettingsAdminData {
		return SettingsAdminData(Settings.shared)
	}

	/// `POST /api/v3/admin/serversettings/update`
	///
	///  Updates a bunch of settings in the Settings.shared object.
	///
	/// - Parameter requestBody: `SettingsUpdateData`
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK` if the settings were updated.
	func settingsUpdateHandler(_ req: Request) async throws -> HTTPStatus {
		let data = try ValidatingJSONDecoder().decode(SettingsUpdateData.self, fromBodyOf: req)
		if let value = data.minUserAccessLevel, let level = UserAccessLevel(fromRawString: value),
				[.banned, .moderator, .twitarrteam, .tho, .admin].contains(level) {
			Settings.shared.minAccessLevel = level
		}
		else {
			Settings.shared.minAccessLevel = .banned
		}
		if let value = data.enablePreregistration {
			Settings.shared.enablePreregistration = value
		}
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
		if let value = data.scheduleUpdateURL {
			Settings.shared.scheduleUpdateURL = value
		}
		if let value = data.upcomingEventNotificationSeconds {
			Settings.shared.upcomingEventNotificationSeconds = Double(value)
		}
		if let value = data.upcomingEventNotificationSetting {
			Settings.shared.upcomingEventNotificationSetting = value
		}
		if let value = data.upcomingLFGNotificationSetting {
			Settings.shared.upcomingLFGNotificationSetting = value
		}
		if let value = data.enableSiteNotificationDataCaching {
			Settings.shared.enableSiteNotificationDataCaching = value
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
	/// - Returns: `TimeZoneChangeData`
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
	
	/// `GET /api/v3/admin/rollup`
	/// 
	///  Returns a bunch of summary data about how many rows of certain database objects we've created. Useful when we want to check
	///  whether a certain row-creating  operation is working, whether any operation is creating way more rows than we expect, or just to guage
	///  the popularity of various server features.
	///  
	///  More sophisticated servers run an operation like this on a cronjob and analyze the results each time to check that recent db activity matches expectations.
	///  Mostly this is just a quick way for us to check usage.
	func serverRollupCounts(_ req: Request) async throws -> ServerRollupData {
		let counts = try await withThrowingTaskGroup(of: (countType: ServerRollupData.CountType, value: Int32).self) { group in
			let tasks: [ServerRollupData.CountType : EventLoopFuture<Int>] = [
					// User
					.user :  User.query(on: req.db).count(),
					.profileEdit: ProfileEdit.query(on: req.db).count(),
					.userNote: UserNote.query(on: req.db).count(),
					.alertword: AlertWord.query(on: req.db).count(),
					.muteword: MuteWord.query(on: req.db).count(),
					.photoStream: StreamPhoto.query(on: req.db).count(),

					// LFGs and Seamails
					.lfg: FriendlyFez.query(on: req.db).filter(\.$fezType ~~ FezType.lfgTypes).count(),
					.lfgParticipant: FezParticipant.query(on: req.db)
							.join(FriendlyFez.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
							.filter(FriendlyFez.self, \.$fezType  ~~ FezType.lfgTypes).count(),
					.lfgPost: FezPost.query(on: req.db).join(FriendlyFez.self, on: \FezPost.$fez.$id == \FriendlyFez.$id)
							.filter(FriendlyFez.self, \.$fezType ~~ FezType.lfgTypes).count(),
					.seamail: FriendlyFez.query(on: req.db).filter(\.$fezType ~~ FezType.seamailTypes).count(),
					.seamailPost: FezPost.query(on: req.db).join(FriendlyFez.self, on: \FezPost.$fez.$id == \FriendlyFez.$id)
							.filter(FriendlyFez.self, \.$fezType ~~ FezType.seamailTypes).count(),
					.privateEvent: FriendlyFez.query(on: req.db).filter(\.$fezType == FezType.privateEvent).count(),
					.personalEvent: FriendlyFez.query(on: req.db).filter(\.$fezType == FezType.personalEvent).count(),

					// Forums
					.forum: Forum.query(on: req.db).count(),
					.forumPost: ForumPost.query(on: req.db).count(),
					.forumPostEdit: ForumPostEdit.query(on: req.db).count(),
					.forumPostLike: PostLikes.query(on: req.db).filter(\.$likeType != nil).count(),
					
					// Games and Karaoke
					.karaokePlayedSong: KaraokePlayedSong.query(on: req.db).count(),
					.microKaraokeSnippet: MKSnippet.query(on: req.db).count(),
					
					// Favorites
					.userFavorite: UserFavorite.query(on: req.db).count(),
					.eventFavorite: EventFavorite.query(on: req.db).count(),
					.forumFavorite: ForumReaders.query(on: req.db).filter(\.$isFavorite == true).count(),
					.forumPostFavorite: PostLikes.query(on: req.db).filter(\.$isFavorite == true).count(),
					.boardgameFavorite: BoardgameFavorite.query(on: req.db).count(),
					.karaokeFavorite: KaraokeFavorite.query(on: req.db).count(),

					// Moderation
					.report: Report.query(on: req.db).count(),
					.moderationAction: ModeratorAction.query(on: req.db).count(),
			]
			
			for (key, task) in tasks {
				group.addTask {
					return try await (key, Int32(task.get()))
				}
			}
			var result = [Int32](repeating: 0, count: tasks.count)
			for try await (key, value) in group {
				result[key.rawValue] = Int32(value)
			}
			return result
		}
		return ServerRollupData(counts: counts)
	}
	
	
// MARK: - Reg Codes
	/// `GET /api/v3/admin/regcodes/stats`
	///
	///  Returns basic info about how many regcodes have been used to create accounts, and how many there are in total.
	///  In the future, we may add a capability for admins to create and issue replacement codes to users (or pull codes from a pre-allocated
	///  'replacement' list, or something). This returns stats on those theoretical codes too, but the numbers are all 0.
	///
	/// - Returns: `RegistrationCodeStatsData`
	func regCodeStatsHandler(_ req: Request) async throws -> RegistrationCodeStatsData {
		let codeCount = try await RegistrationCode.query(on: req.db).filter(\.$isDiscordUser == false).count()
		let usedCodes = try await RegistrationCode.query(on: req.db).filter(\.$isDiscordUser == false).filter(\.$user.$id != nil).count()
		let allocatedDiscord = try await RegistrationCode.query(on: req.db).filter(\.$isDiscordUser == true).count()
		let assignedDiscord = try await RegistrationCode.query(on: req.db).filter(\.$isDiscordUser == true).filter(\.$discordUsername != nil).count()
		let usedDiscord = try await RegistrationCode.query(on: req.db).filter(\.$isDiscordUser == true).filter(\.$user.$id != nil).count()
		return RegistrationCodeStatsData(
			allocatedCodes: codeCount,
			usedCodes: usedCodes,
			unusedCodes: codeCount - usedCodes,
			allocatedDiscordCodes: allocatedDiscord,
			assignedDiscordCodes: assignedDiscord,
			usedDiscordCodes: usedDiscord,
			adminCodes: 0
		)
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
		guard regCode.count == 6, regCode.allSatisfy({ $0.isLetter || $0.isNumber }) else {
			throw Abort(.badRequest, reason: "Registration code search parameter is malformed.")
		}
		guard let foundRecord = try await RegistrationCode.query(on: req.db).filter(\.$code == regCode).first() else {
			throw Abort(.badRequest, reason: "\(regCode) is not found in the registration code table.")
		}
		guard let parentUserID = foundRecord.$user.id else {
			// This is the case where the reg code is valid, exists in the table, but hasn't been used to create a user account.
			return []
		}
		let subAccountIDs = try await User.query(on: req.db).filter(\.$parent.$id == parentUserID).all()
			.map { try $0.requireID() }
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
		return RegistrationCodeUserData(users: resultUsers, regCode: regCode, isForDiscordUser: regCodeResult?.isDiscordUser ?? false,
				discordUsername: regCodeResult?.discordUsername)
	}
	
	/// `POST /api/v3/admin/regcodes/discord/allocate/:username`
	/// 
	/// Finds an unallocated regcode that was reserved for Discord users, allocates it and assigns it to the given Discord user. This method allows TwitarrTeam
	/// members to hand out reg codes to be used on the preproduction Twitarr server for account creation, tying those reg codes to a Discord username.
	/// 
	/// This method is for Pre-Production only, as the boat server should not have any regcodes reserved for Discord users in its database.
	func assignDiscordRegCode(_ req: Request) async throws -> RegistrationCodeUserData {
		guard let discordUser = req.parameters.get(searchStringParam.paramString, as: String.self) else {
			throw Abort(.badRequest, reason: "Missing discord uesrname parameter")
		}
		// Check the discord username is valid, according to Discord's guidelines:
		// https://support.discord.com/hc/en-us/articles/12620128861463-New-Usernames-Display-Names
		guard Set("abcdefghijklmnopqrstuvwxyz0123456789._").isSuperset(of: discordUser) else {
			throw Abort(.badRequest, reason: "Invalid discord username. Make sure you're using the username, not the display name.")
		}
		// Find a Discord regcode that isn't assigned to a Discord user, and isn't associated with a Twitarr account.
		let registrationCode = try await RegistrationCode.query(on: req.db).filter(\.$isDiscordUser == true)
				.filter(\.$discordUsername == nil).filter(\.$user.$id == nil).first()
		guard let registrationCode = registrationCode else {
			throw Abort(.badRequest, reason: "No registration codes are available for this purpose.")
		}
		registrationCode.discordUsername = discordUser
		try await registrationCode.save(on: req.db)
		return RegistrationCodeUserData(users: [], regCode: registrationCode.code, isForDiscordUser: true, discordUsername: discordUser)
	}

	// MARK: - Promote/Demote
	/// `GET /api/v3/admin/moderators`
	///
	///  Returns a list of all site moderators. Only THO and above may call this method.
	///
	/// - Returns: Array of `UserHeader`.
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
			throw Abort(
				.badRequest,
				reason: "User is not at moderator/twitarrteam/THO level: cannot demote to verified."
			)
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
	/// - Returns: Array of `UserHeader`.
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
	func makeTwitarrTeamHandler(_ req: Request) async throws -> HTTPStatus {
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
	/// - Returns: Array of `UserHeader`.
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
	/// - Returns: Array of `UserHeader`.
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
		if let _ = try await UserRole.query(on: req.db).filter(\.$role == role).filter(\.$user.$id == targetUserID)
			.first()
		{
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
		guard let targetUserIDStr = req.parameters.get(userIDParam.paramString),
			let targetUserID = UUID(targetUserIDStr)
		else {
			throw Abort(.badRequest, reason: "Missing user ID parameter.")
		}
		try await UserRole.query(on: req.db).filter(\.$role == role).filter(\.$user.$id == targetUserID).delete()
		try await req.userCache.updateUser(targetUserID)
		return .ok
	}
	
	// MARK: - Schedule Updating
	
	/// `POST /api/v3/admin/schedule/update`
	///
	///  Handles the POST of a new schedule .ics file.
	///
	///  - Warning: Updating the schedule isn't thread-safe, especially if admin is logged in twice. Uploading a schedule file while another
	///  admin account was attempting to apply its contents will cause errors. Once uploaded, an events file should be safe to verify and
	///  apply multiple times in parallel.
	///
	/// - Parameter requestBody: `EventsUpdateData` which is really one big String (the .ics file) wrapped in JSON.
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
	/// - Returns: `EventUpdateDifferenceData`
	func scheduleChangeVerificationHandler(_ req: Request) async throws -> EventUpdateDifferenceData {
		let filepath = try uploadSchedulePath()
		let buffer = try await req.fileio.collectFile(at: filepath.path)
		guard let scheduleFileStr = buffer.getString(at: 0, length: buffer.readableBytes) else {
			throw Abort(.badRequest, reason: "Could not read schedule file.")
		}
		let result =  try await EventParser().validateEventsInICS(scheduleFileStr, on: req.db)
		return result
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
		let differences =  try await EventParser().validateEventsInICS(scheduleFileStr, on: req.db)
		try await EventParser().updateDatabaseFromICS(scheduleFileStr, on: req.db, forumAuthor: user.makeHeader(), 
				processDeletes: processDeletes, makeForumPosts: makeForumPosts)
		try await ScheduleLog(diff: differences, isAutomatic: false).save(on: req.db)
		return .ok
	}
	
	/// `GET /api/v3/admin/schedule/viewlog`
	///
	///  Gets the last 100 entries in the schedule update log, showing what the automatic (and manual) updates to the schedule have been doing.
	///
	/// - Returns: `[EventUpdateLogData]` the most recent 100 log entries, in descending order of update time.
	func scheduleChangeLogHandler(_ req: Request) async throws -> [EventUpdateLogData] {
		let logEntries = try await ScheduleLog.query(on: req.db).sort(\.$createdAt, .descending).limit(100).all()
		return try logEntries.map { try .init($0) }
	}
	
	/// `GET /api/v3/admin/schedule/viewlog/:log_id`
	///
	/// ** Parameters:**
	/// - `:log_id` the ID of the schedule change log entry to return.
	/// 
	///  NOTE: Unless you've requested the most recent change, the returned data may not match the state of the schedule in the db.  
	///
	/// - Returns: `EventUpdateDifferenceData` showing what events were modified by this change to the schedule
	func scheduleGetLogEntryHandler(_ req: Request) async throws -> EventUpdateDifferenceData {
		guard let entryIDString = req.parameters.get(scheduleLogIDParam.paramString, as: String.self), let entryID = Int(entryIDString) else {
			throw Abort(.badRequest, reason: "Could not parse log ID from request URL.")
		}
		guard let entry = try await ScheduleLog.query(on: req.db).filter(\.$id == entryID).first() else {
			throw Abort(.badRequest, reason: "No schedule log entry with this ID.")
		}
		guard let differenceData = entry.differenceData else {
			// Return an empty difference data object if this was an automatic schedule update that resulted in no changes.
			return EventUpdateDifferenceData()
		}
		// Yes, in this case we're decoding the JSON into the struct just so the response builder can encode it back.
		return try JSONDecoder().decode(EventUpdateDifferenceData.self, from: differenceData)
	}

	/// `GET /api/v3/admin/schedule/reload`
	///
	/// Trigger a reload of the Sched event schedule. Normally this happens automatically every hour.
	///
	/// - Returns: HTTP 200 OK.
	func reloadScheduleHandler(_ req: Request) async throws -> HTTPStatus {
		try await req.queue.dispatch(OnDemandScheduleUpdateJob.self, .init())
		return .ok
	}

	/// `POST /api/v3/admin/notifications/reload`
	///
	/// Trigger an internal consistency check job for Redis data.
	///
	/// - Returns: HTTP 200 OK.
	func triggerConsistencyJobHandler(_ req: Request) async throws -> HTTPStatus {
		try await req.queue.dispatch(OnDemandUpdateRedisJob.self, .init())
		return .ok
	}
	
	// MARK: - Bulk User Update
	
	/// `GET /api/v3/admin/bulkuserfile/download`
	///
	///  Handles the GET of a userfile. A userfile is a zip file continaing a bunch of user records, with profile data and avatars. Intended to be used to
	///  facilitate server-to-server transfer of users.
	///  
	///  Warning: Uses blocking IO--the thing that isn't great for multithreaded servers. 
	///
	/// - Parameter requestBody: `EventsUpdateData` which is really one big String (the .ics file) wrapped in JSON.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK`
	func userfileDownloadHandler(_ req: Request) async throws -> Response {
		guard Settings.shared.minAccessLevel == .admin else {
			throw Abort(.badRequest, reason: "Server should be in admin-only mode before downloading a userfile archive.")
		}
		guard Settings.shared.enablePreregistration == false else {
			throw Abort(.badRequest, reason: "Server's 'enable pre-embark UI' setting should be OFF before downloading a userfile archive.")
		}
		let archiveName = "Twitarr_userfile"
		let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
				.appendingPathComponent(UUID().uuidString, isDirectory: true)
		let sourceDirectoryURL = temporaryDirectoryURL.appendingPathComponent(archiveName, isDirectory: true)
		try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
		// Get the list of users we'll be archiving, save to 'userfile.json'
		let users = try await User.query(on: req.db)
				.filter(\.$verification != "generated user")
				.filter(\.$verification != nil)
				.join(RegistrationCode.self, on: \User.$id == \RegistrationCode.$user.$id)
				.filter(RegistrationCode.self, \RegistrationCode.$isDiscordUser == false)
				.with(\.$favoriteEvents.$pivots) { favoriteEvent in
					favoriteEvent.with(\.$event)
				}
				.with(\.$roles)
				.with(\.$performer) { performer in
					performer.with(\.$events)
				}
				.all()
		let userData = users.compactMap { UserSaveRestoreData(user: $0) }
		let performers = try await Performer.query(on: req.db).filter(\.$officialPerformer == true).with(\.$events).all()
		let performerData = try performers.map { try PerformerUploadData($0) }
		let needsPhotographerEvents = try await Event.query(on: req.db).filter(\.$needsPhotographer == true).all().map { $0.uid }
		let dto = SaveRestoreData(users: userData, performers: performerData, needsPhotographer: needsPhotographerEvents)
		let data = try JSONEncoder().encode(dto)
		let userfile = sourceDirectoryURL.appendingPathComponent("userfile.json", isDirectory: true)
		try data.write(to: userfile, options: .atomic)

		// Copy user avatar images into the '/images' dir inside our temp dir.
		let destImageDir = sourceDirectoryURL.appendingPathComponent("userImages", isDirectory: true)
		try FileManager.default.createDirectory(at: destImageDir, withIntermediateDirectories: true)
		let imageNames = users.compactMap { $0.userImage } + users.compactMap { $0.performer?.photo } +
				performerData.compactMap { $0.photo.filename }
		for imageName in imageNames {
			do {
				let imgSource = Settings.shared.userImagesRootPath.appendingPathComponent(ImageSizeGroup.full.rawValue)
						.appendingPathComponent(String(imageName.prefix(2)))
						.appendingPathComponent(imageName)
				let imgDest = destImageDir.appendingPathComponent(imageName, isDirectory: false)
				try FileManager.default.copyItem(at: imgSource, to: imgDest)
			}
			catch {
				req.logger.error("While copying userImage: \(error.localizedDescription)")
			}
		}
		// Zip the whole thing, stream download it.
		let zipDestURL = temporaryDirectoryURL.appendingPathComponent("\(archiveName).zip")
		try FileManager.default.zipItem(at: sourceDirectoryURL, to: zipDestURL, compressionMethod: .deflate)
		let	response = req.fileio.streamFile(at: zipDestURL.path)
		response.headers.replaceOrAdd(name: "Content-Disposition", value: "attachment; filename=\"\(archiveName).zip\"")
		return response
	}

	/// `POST /api/v3/admin/bulkuserfile/upload`
	///
	///  Handles the POST of a new userfile.
	///
	/// - Parameter requestBody: `Data` of the zip'ed userfile..
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK`
	func userfileUploadPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard Settings.shared.minAccessLevel == .admin else {
			throw Abort(.badRequest, reason: "Server must be in admin-only mode when uploading a userfile archive.")
		}
		guard Settings.shared.enablePreregistration == false else {
			throw Abort(.badRequest, reason: "Server's 'enable pre-embark UI' setting should be OFF when uploading a userfile archive.")
		}
		let destDirPath = try uploadUserDirPath()
		try? FileManager.default.removeItem(at: destDirPath)
		let destFilePath = try uploadUserfilePath()
		// If we attempt an upload, it's important we end up with the uploaded file or nothing at the filepath.
		// Leaving the previous file there would be bad. Also, 'unzippedDirPath' is what the zipfile *should* create 
		// when we unzip it, but what it actually creates is embedded in the zipfile itself.
		let unzippedDirPath = destDirPath.appendingPathComponent("Twitarr_userfile", isDirectory: true)
		guard !FileManager.default.fileExists(atPath: destFilePath.path), !FileManager.default.fileExists(atPath: unzippedDirPath.path) else {
			throw Abort(.internalServerError, reason: "Userfile upload dir not empty after emptying it--this could lead to applying a previously-uploaded userfile and not the one you tried to upload just now.")
		}
				
		FileManager.default.createFile(atPath: destFilePath.path, contents: nil)
		if let fileHandle = FileHandle(forWritingAtPath: destFilePath.path)  {
			defer {
				try? fileHandle.close()
			}
			for try await fileChunk in req.body {
				fileHandle.seekToEndOfFile()
				fileHandle.write(Data(buffer: fileChunk))
			}
		}
		else {		
			throw Abort(.internalServerError, reason: "Could not open file for writing Userfile zip contents.")
		}
		try FileManager.default.unzipItem(at: destFilePath, to: destDirPath)
		let userfileJsonPath = try uploadUserDirPath().appendingPathComponent("Twitarr_userfile/userfile.json", isDirectory: false)
		guard FileManager.default.fileExists(atPath: userfileJsonPath.path) else {
			throw Abort(.badRequest, reason: "userfile.json file not found in zip file after expansion. Is this the correct user archive file?")
		}
		return .ok
	}

	/// `GET /api/v3/admin/bulkuserfile/verify`
	///
	///  Returns a struct showing the differences between the current schedule and the (already uploaded and saved to a local file) new schedule.
	///
	///  - Note: This is a separate GET call, instead of the response from POSTing the updated .ics file, so that verifying and applying a schedule
	///  update can be idempotent. Once an update is uploaded, you can call the validate and apply endpoints repeatedly if necessary.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `EventUpdateDifferenceData`
	func userfileVerificationHandler(_ req: Request) async throws -> BulkUserUpdateVerificationData {
		return try await importUsersFromUploadedUserfile(req, verifyOnly: true)
	}

	/// `POST /api/v3/admin/bulkuserfile/update/apply`
	///
	/// 
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK`
	func userfileApplyHandler(_ req: Request) async throws -> BulkUserUpdateVerificationData {
		return try await importUsersFromUploadedUserfile(req, verifyOnly: false)
	}
	
	// MARK: - Utilities

	// Imports each user in the userfile into the database. 
	func importUsersFromUploadedUserfile(_ req: Request, verifyOnly: Bool) async throws -> BulkUserUpdateVerificationData {
		guard Settings.shared.minAccessLevel == .admin else {
			throw Abort(.badRequest, reason: "Bulk User Import is only allowed when the server is in Admin-only mode..")
		}
		guard Settings.shared.enablePreregistration == false else {
			throw Abort(.badRequest, reason: "Server's 'enable pre-embark UI' setting must be OFF when performing bulk user import.")
		}
		let filepath = try uploadUserDirPath().appendingPathComponent("Twitarr_userfile/userfile.json", isDirectory: false)
		guard FileManager.default.fileExists(atPath: filepath.path) else {
			throw Abort(.badRequest, reason: "userfile.json file not found in zip file.")
		}
		let buffer = try await req.fileio.collectFile(at: filepath.path)
		let importData = try JSONDecoder().decode(SaveRestoreData.self, from: buffer)
		var verification = BulkUserUpdateVerificationData(forVerification: verifyOnly)
		for newUser in importData.users where newUser.parentUsername == nil {
			await importUser(req, userToImport: newUser, verifyOnly: verifyOnly, verification: &verification)
		}
		for newUser in importData.users where newUser.parentUsername != nil {
			await importUser(req, userToImport: newUser, verifyOnly: verifyOnly, verification: &verification)
		}
		for performer in importData.performers {
			await importPerformer(req, performerData: performer, verifyOnly: verifyOnly, verification: &verification)
		}
		for needsPhotog in importData.needsPhotographer {
			await importNeedPhotographer_Event(req, eventUID: needsPhotog, verifyOnly: verifyOnly, verification: &verification)
		}
		return verification
	}

	// Imports a single user, as described in a `UserSaveRestoreData` struct, into the `User` table. Does a bunch of validity checcks
	// as part of importing, records results of the import in an existing `BulkUserUpdateVerificationData` structure.
	//
	// Since we don't want an error thrown during a single user's import to fail the entire operation, and also *some* errors shouldn't 
	// cancel a single user's import, and we want to log all the errors that occur, this method has some zany error handling.
	func importUser(_ req: Request, userToImport: UserSaveRestoreData, verifyOnly: Bool, verification: inout BulkUserUpdateVerificationData) async {
		// Exists because we can't pass the inout verification struct into the transaction
		enum ImportResult {
			case duplicate
			case regCodeConflict(String)
			case usernameConflict(String)
			case noRegCodeFound(String)
			case errorNotImported(String)
			case imported(UUID?)
		}
		
		// Copy the userImage first; in the db transaction below we set the user.userImage to nil if the userImage copy failed. 
		var copiedUserImage: String?
		var imageImportError: String?
		do {
			if let userImage = userToImport.userImage {
				copiedUserImage = try await copyImage(userImage, verifyOnly: verifyOnly, on: req)
			}
		}
		catch {
			// Gets added to verification.otherErrors if the user import succeeds.
			imageImportError = "Couldn't copy userImage for user \(userToImport.username): \(error.localizedDescription)"
		}
		
		let userImage = copiedUserImage
		var importedUserID: UUID?
		do {
			let importResult: ImportResult = try await req.db.transaction { transaction in
				if let _ = try await User.query(on: transaction).filter(\.$verification == userToImport.verification.lowercased())
						.filter(\.$username == userToImport.username).first() {
					return .duplicate
				}
				if let dbUserNameMatch = try await User.query(on: transaction).filter(\.$username == userToImport.username).first() {
					return .usernameConflict(dbUserNameMatch.username)
				}
				guard let regCode = try await RegistrationCode.query(on: transaction).filter(\.$code == userToImport.verification).first() else {
					return .noRegCodeFound(userToImport.username)
				}
				let newUser = User(username: userToImport.username, password: userToImport.password, recoveryKey: userToImport.recoveryKey, 
						accessLevel: userToImport.accessLevel)
				if let parentUsername = userToImport.parentUsername {
					guard let parentUser = try await User.query(on: transaction).filter(\.$username == parentUsername).first()  else {
						return .errorNotImported("While importing alternate account \"\(userToImport.username)\": Couldn't find primary account to attach")
					}
					guard parentUser.$parent.id == nil else {
						return .errorNotImported("While importing alternate account \"\(userToImport.username)\": 'parent' account is not a primary account")
					}
					guard parentUser.verification == userToImport.verification else {
						return .errorNotImported("While importing alternate account \"\(userToImport.username)\": primary account has different verification code.")
					}
					let altAccountCount = try await User.query(on: transaction).filter(\.$parent.$id == parentUser.requireID()).count()
					guard altAccountCount < Settings.shared.maxAlternateAccounts else {
						return .errorNotImported("While importing alternate account \"\(userToImport.username)\": Maximum number of alternate accounts reached.")
					}
					newUser.$parent.id = try parentUser.requireID()
				}
				else if regCode.$user.id != nil {
					// If the regcode is already assigned, it's an error unless we're adding an alt account to the same primary, with the same regcode
					return .regCodeConflict("While importing \"\(userToImport.username)\": Reg code already in use") 
				}
				newUser.verification = userToImport.verification
				newUser.displayName = userToImport.displayName
				newUser.realName = userToImport.realName
				newUser.userImage = userImage
				newUser.about = userToImport.about
				newUser.email = userToImport.email
				newUser.homeLocation = userToImport.homeLocation
				newUser.message = userToImport.message
				newUser.preferredPronoun = userToImport.preferredPronoun
				newUser.roomNumber = userToImport.roomNumber
				newUser.displayName = userToImport.displayName
				newUser.dinnerTeam = userToImport.dinnerTeam
				if verifyOnly {
					return .imported(nil)
				}
				else {
					try await newUser.save(on: transaction)
					let newUserID = try newUser.requireID()
					regCode.$user.id = newUserID
					try await regCode.save(on: transaction)
					for role in userToImport.roles {
						let newRole = UserRole(user: newUserID, role: role)
						try await newRole.save(on: transaction)
					}
					return try .imported(newUser.requireID())
				}
			}
			switch importResult {
				case .duplicate:
					verification.userCounts.duplicateCount += 1
				case .usernameConflict(let name): verification.usernameConflicts.append("User \(name) already exists; tied to a different reg code")
					verification.userCounts.errorCount += 1
				case .regCodeConflict(let errorstring): verification.regCodeConflicts.append(errorstring)
					verification.userCounts.errorCount += 1
				case .noRegCodeFound(let name): verification.errorNotImported.append("While importing \(name): Reg code doesn't match any code in db")
					verification.userCounts.errorCount += 1
				case .errorNotImported(let err): verification.errorNotImported.append(err.localizedDescription)
					verification.userCounts.errorCount += 1
				case .imported(let userID): importedUserID = userID
					verification.userCounts.importedCount += 1
			}
		}
		catch {
			verification.errorNotImported.append("During db transaction for user \(userToImport.username): \(error.localizedDescription)")
			verification.userCounts.errorCount += 1
		}
		verification.userCounts.totalRecordsProcessed += 1
		
		// Now do other importing actions related to this user; stuff that shouldn't fail the user import transaction if it doesn't work
		if let newUserID = importedUserID {
			do {
				// Import the user's Performer; attach the Performer to shadow events they're running
				if let performerData = userToImport.performer {
					await importPerformer(req, performerData: performerData, verifyOnly: verifyOnly, userID: newUserID, verification: &verification)
				}

				if !verifyOnly {
					// Add the user to the userCache
					try await req.userCache.updateUser(newUserID)
					guard let addedUser = try await User.find(newUserID, on: req.db) else {
						throw Abort(.internalServerError, reason: "User not found in User table")
					}
					if let err = imageImportError {
						verification.otherErrors.append(err)
					}
					// Import the user's favorited events
					let eventList = Set(userToImport.favoriteEvents + userToImport.photographerEvents)
					let matchedEvents = try await Event.query(on: req.db).filter(\.$uid ~~ eventList).all()
					for event in matchedEvents {
						try await event.$favorites.attach(addedUser, on: req.db) { pivot in
							pivot.favorite = userToImport.favoriteEvents.contains(event.uid)
							pivot.photographer = userToImport.photographerEvents.contains(event.uid)
							// "Shouldn't" occur, but let's disallow pivots where neither favorite nor photographer are true.
							if !(pivot.favorite || pivot.photographer) {
								pivot.favorite = true
							}
						}
					}
					_ = try await storeNextFollowedEvent(userID: newUserID, on: req)
				}				
			}
			catch {
				verification.otherErrors.append(error.localizedDescription)
			}
		}
	}
	
	// Imports a single performer into the Performer table. Works with both official and non-official (shadow) performers.
	// For a shadow performer, you must set the userID of the Twitarr user that 'owns' the performer object.
	// If `verifyOnly` is set, no db changes occur, but `verification` gets filled in with any import errors.
	func importPerformer(_ req: Request, performerData: PerformerUploadData, verifyOnly: Bool, userID: UUID? = nil,
			verification: inout BulkUserUpdateVerificationData) async {
		// Copy the performer's image first;
		var copiedUserImage: String?
		do {
			if let image = performerData.photo.filename {
				copiedUserImage = try await copyImage(image, verifyOnly: verifyOnly, on: req)
			}
		}
		catch {
			verification.otherErrors.append("Couldn't copy photo for Performer named \(performerData.name): \(error.localizedDescription)")
		}
		
		verification.performerCounts.totalRecordsProcessed += 1
		do {
			if performerData.isOfficialPerformer, userID != nil {
				throw ImportError("Official performers cannot be attached to a user.")
			}
			else if !performerData.isOfficialPerformer, userID == nil {
				throw ImportError("Shadow event performers must have a user attached.")
			}
			
			if let foundPerformer = try await Performer.query(on: req.db).filter(\.$name == performerData.name).first() {
				if foundPerformer.officialPerformer != performerData.isOfficialPerformer {
					throw ImportError("Found Performer in db with same name as import record, but officialPerformer bool doesn't match.")
				}
				if let userID = userID, foundPerformer.$user.id != userID {
					throw ImportError("Performer already exists and is associated with a different user.")
				}
				verification.performerCounts.duplicateCount += 1
				return
			}
			else if let userID = userID, let foundSameUser = try await Performer.query(on: req.db).filter(\.$user.$id == userID).first() {
				throw ImportError("Associated user \"\(foundSameUser.name)\" already has a performer record, with a different name")
			}
			var performer = Performer()
			try await PerformerController().buildPerformerFromUploadData(performer: &performer, uploadData: performerData, on: req)
			performer.$user.id = userID
			performer.$photo.value = copiedUserImage
			if !verifyOnly {
				try await performer.save(on: req.db)			// Updates or creates
			}
			for eventUID in performerData.eventUIDs {
				guard let event = try await Event.query(on: req.db).filter(\.$uid == eventUID).first() else {
					verification.otherErrors.append("Couldn't find Event that Performer \"\(performerData.name)\" is performing in: UID = \(eventUID)")
					continue
				}
				if !verifyOnly {
					let attachedEvent = try await EventPerformer.query(on: req.db)
							.filter(\.$performer.$id == performer.requireID()).filter(\.$event.$id == event.requireID()).first()
					if attachedEvent == nil {
						let newEventPerformer = EventPerformer()
						newEventPerformer.$performer.id = try performer.requireID()
						newEventPerformer.$event.id = try event.requireID()
						try await newEventPerformer.save(on: req.db)
					}
				}
			}
			verification.performerCounts.importedCount += 1
		}
		catch {
			verification.otherErrors.append("Error when importing Performer \"\(performerData.name)\": \(error.localizedDescription)")
			verification.performerCounts.errorCount += 1
		}
	}
	
	// Imports a single "Needs Photographer" flag, which is a field in the Event model. This fn works on a single Event
	// at a time due to the way verification works. Even then, this could work as a single fn that takes the array of Event UIDs,
	// but this makes the fn work the same way as the other importers.
	func importNeedPhotographer_Event(_ req: Request, eventUID: String, verifyOnly: Bool, 
			verification: inout BulkUserUpdateVerificationData) async {
		do {
			verification.needsPhotographerCounts.totalRecordsProcessed += 1
			guard let event = try await Event.query(on: req.db).filter(\Event.$uid == eventUID).first() else {
				throw ImportError("Event not found in database.")
			}
			if event.needsPhotographer {
				verification.needsPhotographerCounts.duplicateCount += 1
				return
			}
			event.needsPhotographer = true
			if !verifyOnly {
				try await event.save(on: req.db)
			}
			verification.needsPhotographerCounts.importedCount += 1
		}
		catch {
			verification.needsPhotographerCounts.errorCount += 1
			verification.otherErrors.append("Error when importing Needs Photographer flag for event with UID \(eventUID): \(error.localizedDescription)")
		}
	}

	// Copy an image from the uploaded data bundle to the expected location on the filesystem.
	func copyImage(_ image: String, verifyOnly: Bool, on req: Request) async throws -> String {
		let archiveSource = try uploadUserDirPath().appendingPathComponent("Twitarr_userfile/userImages", isDirectory: true)
				.appendingPathComponent(image)
		let serverImageDestDir = Settings.shared.userImagesRootPath.appendingPathComponent(ImageSizeGroup.full.rawValue)
				.appendingPathComponent(String(image.prefix(2)))
		let serverImageDest = serverImageDestDir.appendingPathComponent(image)
		if !FileManager.default.fileExists(atPath: archiveSource.path) {
			throw Abort(.badRequest, reason: "Source image file not found")
		}
		if !verifyOnly, !FileManager.default.fileExists(atPath: serverImageDest.path) {
			// Testing this requires copying from Computer A to Computer B or otherwise
			// wiping the local images directory.
			if (!FileManager.default.fileExists(atPath: serverImageDestDir.path)) {
				try FileManager.default.createDirectory(at: serverImageDestDir, withIntermediateDirectories: true)
			}
			try FileManager.default.copyItem(at: archiveSource, to: serverImageDest)
		}
		if !verifyOnly {
			try await regenerateThumbnail(for: serverImageDest, on: req)
		}
		return image
	}

	// Gets the path where the uploaded schedule is kept. Only one schedule file can be in the hopper at a time.
	// This fn ensures intermediate directories are created.
	func uploadSchedulePath() throws -> URL {
		let filePath = Settings.shared.adminDirectoryPath.appendingPathComponent("uploadschedule.ics")
		return filePath
	}

	// Gets the directory path to the directory where we store the "Twitarr_userfile.zip" and the unzipped "Twitarr_userfile" dir.
	// Creates the dir if necessary. 
	func uploadUserDirPath() throws -> URL {
		let dirPath = Settings.shared.adminDirectoryPath.appendingPathComponent("uploadUserfileDir")
		try FileManager.default.createDirectory(at: dirPath, withIntermediateDirectories: true)
		return dirPath
	}
	
	// Gets the path where the uploaded userfile.zip is kept. Only one file can be in the hopper at a time.
	// The folder decompressed from the ZIP archive will be right alonsize the archive, at "/<adminDirectoryPath>/Twitarr_userfile/"
	// This fn ensures intermediate directories are created.
	func uploadUserfilePath() throws -> URL {
		let filePath = try uploadUserDirPath().appendingPathComponent("Twitarr_userfile.zip")
		return filePath
	}

	// An error type for the admin-level bulk importers to use. Really it just wraps a string; its purpose is to enable
	// localizedError to work correclty.
	struct ImportError: LocalizedError {
		var str: String
		public var errorDescription: String? { return str }
		init(_ string: String) {
			str = string
		}
	}
}


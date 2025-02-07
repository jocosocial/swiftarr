import Vapor

/// structs in this file should only be used by Admin APIs, that is: API calls that require administrator access.

/// For admins to create and edit Annoucements.
public struct AnnouncementCreateData: Content {
	/// The text of the announcement
	var text: String
	/// How long to display the announcement to users. User-level API route methods will only return this Announcement until this time. The given Date is interpreted
	/// as a floating time in the ship's Port timezone.
	var displayUntil: Date
}

extension AnnouncementCreateData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(!text.isEmpty, forKey: .text, or: "Text cannot be empty")
		tester.validate(text.count < 2000, forKey: .text, or: "Announcement text has a 2000 char limit")
		tester.validate(
			displayUntil > Date(),
			forKey: .displayUntil,
			or: "Announcement DisplayUntil date must be in the future."
		)
	}
}

/// Used during bulk import of `User` information. Reports the result of merging the new User data into the database, or for the Verify operation, previews
/// what that result will be.Purposefully does not report specific regCodes that are in conflict.
/// 
/// The idea behind this struct is to split out cases where we might get 1000+ errors under certain import conditions, so we don't just return an array of `Error`s
/// where there's one important error buried in a thousand 'duplicate name and regcode' errors.
public struct BulkUserUpdateVerificationData: Content {
	/// If TRUE, this structure is returned as the result of the 'apply' method, and the values in this struct reflect changes actually made to the db.
	/// If FALSE, this structure shows the result of the validation pass and no database changes were saved.
	var changesApplied: Bool

	public struct BulkUserUpdateCounts: Content {
		/// Number of  records found in the file
		var totalRecordsProcessed: Int
		/// The number of records that were successfully imported.
		var importedCount: Int
		/// Number of records that we didn't import because it appars the record is already in the DB.
		/// For Users, this means the same reg code and same username. Doesn't check the other fields in the user object.
		/// For Performers, this means a Performer record with the same name.
		/// These cases are almost certainly true duplicates--either a previous bulk import, or the same user managed to create accounts on both servers.
		var duplicateCount: Int
		/// Number of records that we couldn't import due to errors. 
		var errorCount: Int
	}
	/// Counts for User import. 
	var userCounts: BulkUserUpdateCounts
	/// Counts for Performer import. Includes both official and shadow performers.
	var performerCounts: BulkUserUpdateCounts

	/// Cases where the server has a registered user with the same regcode as the update file, but the usernames differ.
	/// This may mean the user preregistered and then (somehow) registered on-boat with a different username before the bulk import happened.
	var regCodeConflicts: [String]		
	/// Cases where a username already exists on the server, tied to a different regcode. 
	/// This indicates someone else took the username on the server, and we can't import this user from the preregistration file.
	/// These are actual merge conflicts where someone who expects to have an account on-boat on embark day won't have one (but they can still create one with their regcode).
	var usernameConflicts: [String]
	/// Cases where the import threw an error.
	var errorNotImported: [String]
	/// Errors that occurred while processing non-critical user data. These errors did not prevent import, but some data tied to the user (like favorite events/songs/boardgames) may not have imported.
	var otherErrors: [String]
}

extension BulkUserUpdateVerificationData {
	init(forVerification: Bool) {
		changesApplied = !forVerification
		userCounts = BulkUserUpdateCounts(totalRecordsProcessed: 0, importedCount: 0, duplicateCount: 0, errorCount: 0)
		performerCounts = BulkUserUpdateCounts(totalRecordsProcessed: 0, importedCount: 0, duplicateCount: 0, errorCount: 0)
		regCodeConflicts = []
		usernameConflicts = []
		errorNotImported = []
		otherErrors = []
	}
}

/// For admins to upload new daily themes, or edit existing ones.
public struct DailyThemeUploadData: Content {
	/// A short string describing the day's theme. e.g. "Cosplay Day", or "Pajamas Day", or "Science Day".
	var title: String
	/// A longer string describing the theme, possibly with a call to action for users to participate.
	var info: String
	/// An optional image that relates to the theme.
	var image: ImageUploadData?
	/// Day of cruise, counted from `Settings.shared.cruiseStartDate`. 0 is embarkation day. Values could be negative (e.g. Day -1 is "Anticipation Day")
	var cruiseDay: Int32
}

/// Used to update the `Event` database.
///
/// Required by: `POST /api/v3/events/update`
///
/// See `EventController.eventsUpdateHandler(_:data:)`.
public struct EventsUpdateData: Content {
	/// The `.ics` event schedule file.
	var schedule: String
}

/// Used to validate changes to the `Event` database. This public struct shows the differrences between the current schedule and the
/// (already uploaded but not processed) updated schedule. Event identity is based on the `uid` field--two events with the same
/// `uid` are the same event, and if they show different times, we conclude the event's time changed. Two events with different `uid`s
/// are different events, even if all other fields are exactly the same.
///
/// Events that are added or deleted will only appear in deleted or created event arrays. Modified events could appear in any or all of the 3 modification arrays.
/// Deleted events take their contents from the database. All other arrays take content from the update.
///
/// Required by: `POST /api/v3/admin/schedule/verify`
///
/// See `EventController.eventsUpdateHandler(_:data:)`.
public struct EventUpdateDifferenceData: Content {
	/// Events in db but not in update. EventData is based on the current db values.
	var deletedEvents: [EventData] = []
	/// Events in update but not in db.
	var createdEvents: [EventData] = []
	/// Events that will change their time as part of the update. Items here can also show up in `locationChangeEvents` and `minorChangeEvents`.
	var timeChangeEvents: [EventData] = []
	var locationChangeEvents: [EventData] = []
	var minorChangeEvents: [EventData] = []
}

public struct EventUpdateLogData: Content {
	/// The ID of this log entry
	var entryID: Int
	/// TRUE if this was an automatic, scheduled update.
	var automaticUpdate: Bool
	/// How many changes were made to the db as a result of this schedule update. 0 if the update resulted in an error; may also be zero if no changes detected.
	var changeCount: Int
	/// When the update was processed.
	var timestamp: Date
	/// If the update failed, the reason why.
	var error: String?
}

extension EventUpdateLogData {
	init(_ logEntry: ScheduleLog) throws{
		self.entryID = try logEntry.requireID()
		self.automaticUpdate = logEntry.automaticUpdate
		self.changeCount = logEntry.changeCount
		self.timestamp = logEntry.createdAt ?? Date()
		self.error = logEntry.errorResult
	}
}

/// Used to report  what the results of applying an update to the Event-Performer pivots is going to do. The uploaded source information
/// is an Excel spreadsheet containing all the published events, with information on which official performers (if any) will be performing at each event.
/// 
/// When uploading a new performer links spreadsheet, it's important that both Events and Performers are fully updated first. This operation doesn't create
/// performers or events, just links them with a pivot.
///
/// Returned  by: `POST /api/v3/admin/schedule/verify`
public struct EventPerformerValidationData: Content {
	/// The number of performers in the database
	var oldPerformerCount: Int
	/// The number of performers found in the Excel spreadsheet.
	var newPerformerCount: Int
	/// The number of performers in the spreadsheet that aren't in the db.
	var missingPerformerCount: Int
	/// The number of performers in the db but not in the spreadsheet
	var noEventsPerformerCount: Int
	/// The number of Events in the spreadsheet that list official performers and were matched with db events.
	var eventsWithPerformerCount: Int
	/// Number of events in spreadsheet that we couldn't match with any database event.
	var unmatchedEventCount: Int
	/// Errors detected while processing. Most errors won't prevent the update (although "Couldn't Open Worksheet" will).
	var errors: [String]
}

public struct HuntCreateData: Content {
	var title: String
	var description: String
	var puzzles: [HuntPuzzleCreateData]
}

public struct HuntPuzzleCreateData: Content {
	var title: String
	var body: String
	var unlockTime: Date?
	var answer: String
	var hints: [String:String]
}

extension HuntCreateData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(!puzzles.isEmpty, forKey: .puzzles, or: "Puzzles cannot be empty")
	}
}

public enum ExplicitNull<C: Codable & Sendable>: Codable, Sendable {
	case absent
	case null
	case present(C)

	public init(from decoder: any Decoder) throws {
		let single = try decoder.singleValueContainer()
		if single.decodeNil() {
			self = .null
		} else {
			self = .present(try single.decode(C.self))
		}
	}

	public func encode(to encoder: any Encoder) throws {
		switch self {
			case .absent:
				return
			case .null:
        		var container = encoder.singleValueContainer()
				try container.encodeNil()
			case .present(let value):
        		try value.encode(to: encoder)
		}
	}
}

extension KeyedDecodingContainer {
  	func decode<T>(_ type: ExplicitNull<T>.Type, forKey key: Key) throws -> ExplicitNull<T> {
		if !contains(key) {
			return .absent
		}
		if try decodeNil(forKey: key) {
			return .null
		}
		return .present(try decode(T.self, forKey: key))
 	}
}

extension KeyedEncodingContainer {
	mutating func encode<T>(_ explicit: ExplicitNull<T>, forKey key: Key) throws {
		switch explicit {
			case .absent:
				return
			case .null:
				try encodeNil(forKey: key)
			case .present(let value):
				try encode(value, forKey: key)
		}
	}
}

/// Used to modify a puzzle.
/// Optional fields in this are required fields in Puzzle;
/// if not nil, the value in the puzzle will be modified.
/// ExplicitNull fields in this are optional in Puzzle.
/// If absent in the JSON, not affected.
/// If present and null, will unset the field.
public struct HuntPuzzlePatchData: Content {
	var body: String?
	var unlockTime: ExplicitNull<Date>
}

/// Returns the registration code associated with a user. Not all users have registration codes; e.g. asking for the reg code for 'admin' will return an error.
public struct RegistrationCodeUserData: Content {
	// User accounts associated with the reg code. First item in the array is the primary account.
	var users: [UserHeader]
	/// The registration code associated with this account. If this account doesn't have an associated regcode, will be the empty string.
	var regCode: String
	/// TRUE if this reg code was created to get allocated to a user on Discord for the purpose of creating an account on the pre-prod server.
	var isForDiscordUser: Bool
	/// If this reg code has been allocated to a Discord user, the name of the user. Nil if not a Discord regcode or if not yet allocated.
	var discordUsername: String?
}

/// Returns general info about registration codes.
///
/// Each passenger gets sent an email with a unique registration code; the reg code allows them to create verified accounts.
/// This struct lets the admins quickly view some basic stats on account usage.
public struct RegistrationCodeStatsData: Content {
	/// How many 'normal' reg codes are in the database.
	var allocatedCodes: Int
	/// How many codes have been used to create verified accounts.
	var usedCodes: Int
	/// How many codes have not yet been used.
	var unusedCodes: Int
	/// The total number of Registration codes alloced for the purpose of offering to users on Discord to create accounts on the pre-prod server.
	/// Will be 0 on producation.
	var allocatedDiscordCodes: Int
	/// The number of codes that have been assigend to Discord users.
	var assignedDiscordCodes: Int
	/// The number of Discord codes that have been used to create Twitarr accounts on the pre-prod server.
	var usedDiscordCodes: Int
	/// This exists so that if admins create new reg codes for people who lost theirs, we can track it.
	/// There isn't yet any API for admins to do this; the number will be 0.
	var adminCodes: Int
}

/// The Bulk User Download file is a serialization of this object, plus a bunch of image files, all zipped up.
public struct SaveRestoreData: Content {
	/// Array of users to save and restore. 
	var users: [UserSaveRestoreData]
	/// Array of official performers to save and restore.
	var performers: [PerformerUploadData]
}

/// An array of totals for various database entities. Each value in the array is essentially a `SQL SELECT COUNT() FROM <table>`,
/// although some values apply filters to the counted rows. 
/// 
/// The `CountType` enum defines what each value in the counts array means, so `counts[0]` is a count of the Users in the database.
/// 
/// Used by: `GET /api/v3/admin/rollup`
struct ServerRollupData: Content {
	///  An array with `CountType.allCases.count` values.
	var counts: [Int32]
	
	/// An int-valued enum that defines what each value in the counts array means. For API staibility it's best if we only add values to the 
	/// end of the list; causing existing elements to change threir index could cause confusion.
	enum CountType: Int, CaseIterable {
		// User
		case user = 0
		case profileEdit 
		case userNote 
		case alertword 
		case muteword 
		case photoStream 

		// LFGs and Seamails
		case lfg 
		case lfgParticipant 
		case lfgPost
		case seamail
		case seamailPost 

		// Forums
		case forum 
		case forumPost 
		case forumPostEdit 
		case forumPostLike 

		// Games and Karaoke
		case karaokePlayedSong 
		case microKaraokeSnippet
		
		// Favorites
		case userFavorite 
		case eventFavorite 
		case forumFavorite 
		case forumPostFavorite
		case boardgameFavorite
		case karaokeFavorite
		
		// Moderation
		case report
		case moderationAction			// Note that 'moderationAction' includes instances of Mods using the 'Post as Moderator' option.
	}
}

/// Used to enable/disable features. A featurePair with name: "kraken" and feature: "schedule" indicates the Schedule feature of the Kraken app.
/// When the server indicates this app:feature pair is disabled, the client app should not show the feature to users, and should avoid calling API calls
/// related to that feature. Either the app or feature field could be 'all'.
///
/// Used in: `SettingsAdminData`, `SettingsUpdateData`
public struct SettingsAppFeaturePair: Content {
	/// Should match a SwiftarrClientApp.rawValue
	var app: String
	/// Should match a SwiftarrFeature.rawValue
	var feature: String
}

/// Used to return the current `Settings` values. 
///
/// Required by: `GET /api/v3/events/update`
///
/// See `AdminController.settingsHandler()`.
public struct SettingsAdminData: Content {
	var minAccessUserLevel: String
	var enablePreregistration: Bool
	var maxAlternateAccounts: Int
	var maximumTwarrts: Int
	var maximumForums: Int
	var maximumForumPosts: Int
	/// Max Image size in bytes. Images larger than this are rejected. The server separately enforces maximum x and y image dimensions, downsizing the
	/// image if possible. Mostly this option is designed to reject very large gif images.
	var maxImageSize: Int
	var forumAutoQuarantineThreshold: Int
	var postAutoQuarantineThreshold: Int
	var userAutoQuarantineThreshold: Int
	var allowAnimatedImages: Bool
	/// Currently disabled app:feature pairs.
	var disabledFeatures: [SettingsAppFeaturePair]
	var shipWifiSSID: String?
	var scheduleUpdateURL: String
	var upcomingEventNotificationSeconds: Int
	var upcomingEventNotificationSetting: EventNotificationSetting
	var upcomingLFGNotificationSetting: EventNotificationSetting
	var enableSiteNotificationDataCaching: Bool
}

extension SettingsAdminData {
	init(_ settings: Settings) {
		self.minAccessUserLevel = settings.minAccessLevel.rawValue
		self.enablePreregistration = settings.enablePreregistration
		self.maxAlternateAccounts = settings.maxAlternateAccounts
		self.maximumTwarrts = settings.maximumTwarrts
		self.maximumForums = settings.maximumForums
		self.maximumForumPosts = settings.maximumForumPosts
		self.maxImageSize = settings.maxImageSize
		self.forumAutoQuarantineThreshold = settings.forumAutoQuarantineThreshold
		self.postAutoQuarantineThreshold = settings.postAutoQuarantineThreshold
		self.userAutoQuarantineThreshold = settings.userAutoQuarantineThreshold
		self.allowAnimatedImages = settings.allowAnimatedImages
		disabledFeatures = []
		for (app, features) in settings.disabledFeatures.value {
			for feature in features {
				disabledFeatures.append(SettingsAppFeaturePair(app: app.rawValue, feature: feature.rawValue))
			}
		}
		self.shipWifiSSID = settings.shipWifiSSID
		self.scheduleUpdateURL = settings.scheduleUpdateURL
		self.upcomingEventNotificationSeconds = Int(settings.upcomingEventNotificationSeconds)
		self.upcomingEventNotificationSetting = settings.upcomingEventNotificationSetting
		self.upcomingLFGNotificationSetting = settings.upcomingLFGNotificationSetting
		self.enableSiteNotificationDataCaching = settings.enableSiteNotificationDataCaching
	}
}

/// Used to update the `Settings` values. Doesn't update everything--some values aren't meant to be updated live. The updated values are saved so
/// that they'll persist through app launches. Any optional values set to nil are not used to update Settings values.
///
/// Required by: `POST /api/v3/events/update`
///
/// See `AdminController.settingsUpdateHandler()`.
public struct SettingsUpdateData: Content {
	var minUserAccessLevel: String?
	var enablePreregistration: Bool?
	var maxAlternateAccounts: Int?
	var maximumTwarrts: Int?
	var maximumForums: Int?
	var maximumForumPosts: Int?
	var maxImageSize: Int?
	var forumAutoQuarantineThreshold: Int?
	var postAutoQuarantineThreshold: Int?
	var userAutoQuarantineThreshold: Int?
	var allowAnimatedImages: Bool?
	/// Currently disabled app:feature pairs to enable. Note that `all` is treated as just another value here; you can't disable `all:forums` and then
	/// enable `swiftarr:forums` to disable forums everywhere but swiftarr. Only list deltas here; don't add every possible app:feature pair to this array.
	var enableFeatures: [SettingsAppFeaturePair]
	/// App:feature pairs to disable. Only list deltas here; no need to re-list currently disabled app:feature pairs..
	var disableFeatures: [SettingsAppFeaturePair]
	/// The wifi name of the onboard wifi network
	var shipWifiSSID: String?
	/// The URL to use for automated schedule updates. The server polls this every hour to update the Events table.
	var scheduleUpdateURL: String?
	/// Number of seconds before an event to trigger the Soon notifications.
	var upcomingEventNotificationSeconds: Int?
	/// Upcoming event notification setting
	var upcomingEventNotificationSetting: EventNotificationSetting?
	/// Upcoming joined LFG notification setting
	var upcomingLFGNotificationSetting: EventNotificationSetting?
	/// Enable site UI notification data caching
	var enableSiteNotificationDataCaching: Bool?
}

/// Used to return information about the time zone changes scheduled to occur during the cruise.
///
/// Returned by: `GET /api/v3/admin/timezonechanges`
public struct TimeZoneChangeData: Content {
	public struct Record: Content {
		/// When the new time zone becomes active.
		var activeDate: Date
		/// The 3 letter abbreviation for the timezone that becomes active at `activeDate`
		var timeZoneAbbrev: String
		/// The Foundation ID for the timezone that becomes active at `activeDate`. Prefer using this to make TimeZone objects over the abbreviation.
		/// There is a list of all Foundation TimeZone names at `seeds/TimeZoneNames.txt`
		var timeZoneID: String
	}

	/// All the timezone changes that will occur during the cruise, sorted by activeDate.
	var records: [Record]
	/// The 3 letter abbreviation for the timezone the ship is currently observing.
	var currentTimeZoneAbbrev: String
	/// The Foundation ID of the current time zone.
	var currentTimeZoneID: String
	/// The number of seconds between the current timezone and GMT. Generally a negative number in the western hemisphere.
	var currentOffsetSeconds: Int
}

extension TimeZoneChangeData {
	init(_ changeSet: TimeZoneChangeSet) {
		records = changeSet.changePoints.map {
			Record(activeDate: $0.startTime, timeZoneAbbrev: $0.timeZoneName, timeZoneID: $0.timeZoneID)
		}
		let current = changeSet.tzAtTime(Date())
		currentTimeZoneAbbrev = current.abbreviation(for: Date()) ?? "EST"
		currentTimeZoneID = current.identifier
		currentOffsetSeconds = current.secondsFromGMT(for: Date())
	}
}

/// Used to bulk save/restore user accounts. This was created to allow us to download an archive of all registered users from the staging server just before 
/// embarkation, and then load the archived users onto the prod server as soon as we get on the boat.
/// 
/// Just archiving `User`s directly would work, but using a DTO gives us better control in the case of schema changes between staging and prod, or if
/// we need to massage the data to get the restore to work correctly. Also, this method tries whenever possible to put data from related tables we want
/// to save/restore right in the User object; otherwise we'd have to export `RegistrationCode` and `EventFavorite`(and maybe a bunch of other tables)
/// and match everything up as part of import.
/// 
/// Also: This DTO contains sensitive data and should only be used for Admin routes.
struct UserSaveRestoreData: Content, Sendable {
	let username: String
	let displayName: String?
	let realName: String?
	// BCrypt hashed.
	let password: String					
	// BCrypt hashed.
	let recoveryKey: String					
	// Registration code - 6 letters, lowercased
	let verification: String				
	let accessLevel: UserAccessLevel
	let userImage: String?
	let about: String?
	let email: String?
	let homeLocation: String?
	let message: String?
	let preferredPronoun: String?
	let roomNumber: String?
	let dinnerTeam: DinnerTeam?
	let parentUsername: String?
	let roles: [UserRoleType]
	/// Event UIDs, the thing in the ICS file spec--NOT database IDs!
	let favoriteEvents: [String]
	/// For shadow event organizers, their associated Performer data (which contains the event UIDs for the events 'they're running).
	let performer: PerformerUploadData?
	// karaoke, game favorites?
}

extension UserSaveRestoreData {
	/// For this to work: Must use `.with(\.$roles).with(\.$favoriteEvents).with(\.$performer).with(\.$performer.events)` in query
	init?(user: User) {
		guard var regCode = user.verification else {
			return nil
		}
		if regCode.first == "*" {
			regCode = String(regCode.dropFirst())
		}
		// Stuff that's important to get right for security reasons
		username = user.username
		parentUsername = user.parent?.username
		password = user.password
		recoveryKey = user.recoveryKey
		verification = regCode
		accessLevel = user.accessLevel
		roles = user.roles.map { $0.role }

		// User Profile stuff
		displayName = user.displayName
		realName = user.realName
		userImage = user.userImage
		about = user.about
		email = user.email
		homeLocation = user.homeLocation
		message = user.message
		preferredPronoun = user.preferredPronoun
		roomNumber = user.roomNumber
		dinnerTeam = user.dinnerTeam
		favoriteEvents = user.favoriteEvents.map { $0.uid }
		if let perf = user.performer {
			performer = try? PerformerUploadData(perf)
		}
		else {
			performer = nil
		}
	}
}


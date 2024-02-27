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

/// Returns the registration code associated with a user. Not all users have registration codes; e.g. asking for the reg code for 'admin' will return an error.
public struct RegistrationCodeUserData: Content {
	// User accounts associated with the reg code. First item in the array is the primary account.
	var users: [UserHeader]
	/// The registration code associated with this account. If this account doesn't have an associated regcode, will be the empty string.
	var regCode: String
}

/// Returns general info about registration codes.
///
/// Each passenger gets sent an email with a unique registration code; the reg code allows them to create verified accounts.
/// This struct lets the admins quickly view some basic stats on account usage.
public struct RegistrationCodeStatsData: Content {
	/// How many reg codes are in the database.
	var allocatedCodes: Int
	/// How many codes have been used to create verified accounts.
	var usedCodes: Int
	/// How many codes have not yet been used.
	var unusedCodes: Int
	/// This exists so that if admins create new reg codes for people who lost theirs, we can track it.
	/// There isn't yet any API for admins to do this; the number will be 0.
	var adminCodes: Int
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
}

extension SettingsAdminData {
	init(_ settings: Settings) {
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
	}
}

/// Used to update the `Settings` values. Doesn't update everything--some values aren't meant to be updated live. The updated values are saved so
/// that they'll persist through app launches. Any optional values set to nil are not used to update Settings values.
///
/// Required by: `POST /api/v3/events/update`
///
/// See `AdminController.settingsUpdateHandler()`.
public struct SettingsUpdateData: Content {
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

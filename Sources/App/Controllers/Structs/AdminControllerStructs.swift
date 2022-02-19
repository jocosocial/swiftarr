import Vapor

/// structs in this file should only be used by Admin APIs, that is: API calls that require administrator access.

/// For admins to create and edit Annoucements.
public struct AnnouncementCreateData: Content {
	/// The text of the announcement
	var text: String
	/// How long to display the announcement to users. User-level API route methods will only return this Announcement until this time. 
	var displayUntil: Date
}

extension AnnouncementCreateData: RCFValidatable {
	func runValidations(using decoder: ValidatingDecoder) throws {
		let tester = try decoder.validator(keyedBy: CodingKeys.self)
		tester.validate(!text.isEmpty, forKey: .text, or: "Text cannot be empty")
		tester.validate(text.count < 2000, forKey: .text, or: "Announcement text has a 2000 char limit")
		tester.validate(displayUntil > Date(), forKey: .displayUntil, or: "Announcement DisplayUntil date must be in the future.")
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

/// Used to return the current `Settings` values. Doesn't update everything--some values aren't meant to be updated live, and others are 
///
/// Required by: `POST /api/v3/events/update`
///
/// See `EventController.eventsUpdateHandler(_:data:)`.
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
	}
}

/// Used to update the `Settings` values. Doesn't update everything--some values aren't meant to be updated live. The updated values are saved so
/// that they'll persist through app launches. Any optional values set to nil are not used to update Settings values.
///
/// Required by: `POST /api/v3/events/update`
///
/// See `EventController.eventsUpdateHandler(_:data:)`.
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
}

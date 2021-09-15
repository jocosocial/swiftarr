import Vapor

/// Structs in this file should only be used by Admin APIs, that is: API calls that require administrator access.

/// For admins to create and edit Annoucements.
struct AnnouncementCreateData: Content {
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
struct DailyThemeUploadData: Content {
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
struct EventsUpdateData: Content {
    /// The `.ics` event schedule file.
    var schedule: String
}

/// Used to enable/disable features. A featurePair with name: "kraken" and feature: "schedule" indicates the Schedule feature of the Kraken app.
/// When the server indicates this app:feature pair is disabled, the client app should not show the feature to users, and should avoid calling API calls
/// related to that feature. Either the app or feature field could be 'all'.
///
/// Used in: `SettingsAdminData`, `SettingsUpdateData`
struct SettingsAppFeaturePair: Content {
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
struct SettingsAdminData: Content {
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
}

extension SettingsAdminData {
	init(_ settings: Settings) {
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
	}
}

/// Used to update the `Settings` values. Doesn't update everything--some values aren't meant to be updated live. The updated values are saved so
/// that they'll persist through app launches.
///
/// Required by: `POST /api/v3/events/update`
///
/// See `EventController.eventsUpdateHandler(_:data:)`.
struct SettingsUpdateData: Content {
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
}

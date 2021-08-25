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


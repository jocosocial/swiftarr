import Vapor

/// A (hopefully) thread-safe singleton that provides modifiable global settings.

final class Settings {
    
    /// Wraps settings properties, making them thread-safe.
	@propertyWrapper class SettingsValue<T> {
		private var internalValue: T
		var wrappedValue: T {
			get { return Settings.settingsQueue.sync { internalValue } }
			set { Settings.settingsQueue.async { self.internalValue = newValue } }
		}
		
		init(wrappedValue: T) {
			internalValue = wrappedValue
		}
	}
	
    /// The shared instance for this singleton.
    static let shared = Settings()
    
    /// DispatchQueue to use for thread-safety synchronization.
    fileprivate static let settingsQueue = DispatchQueue(label: "settingsQueue")
    
    /// Required initializer.
    private init() {}
        
    /// The ID of the blocked user placeholder.
    @SettingsValue var blockedUserID: UUID = UUID()

    /// The ID of the FriendlyFez user placeholder.
	@SettingsValue var friendlyFezID: UUID = UUID()
    
// MARK: Limits
    /// The maximum number of twartts allowed per request.
    @SettingsValue var maximumTwarrts: Int = 200

    /// The maximum number of twartts allowed per request.
    @SettingsValue var maximumForumPosts: Int = 200

	/// Largest image we allow to be uploaded, in bytes.
    @SettingsValue var maxImageSize: Int = 20 * 1024 * 1024

// MARK: Quarantine
    /// The number of reports to trigger forum auto-quarantine.
    @SettingsValue var forumAutoQuarantineThreshold: Int = 3
    
    /// The number of reports to trigger post/twarrt auto-quarantine.
	@SettingsValue var postAutoQuarantineThreshold: Int = 3
    
    /// The number of reports to trigger user auto-quarantine.
    @SettingsValue var userAutoQuarantineThreshold: Int = 5
    
// MARK: Dates
	/// A Date set to midnight on the day the cruise ship leaves port, in the timezone the ship leaves from. Used by the Events Controller for date arithimetic.
	@SettingsValue var cruiseStartDate: Date = Calendar.autoupdatingCurrent.date(from: DateComponents(calendar: Calendar.current, 
			timeZone: TimeZone(abbreviation: "EST")!, year: 2020, month: 3, day: 7))!
	
	/// The day of week when the cruise embarks, expressed as number as Calendar's .weekday uses them: Range 1...7, Sunday == 1.
	@SettingsValue var cruiseStartDayOfWeek: Int = 7

	/// The length in days of the cruise, includes partial days. A cruise that embarks on Saturday and returns the next Saturday should have a value of 8.
	@SettingsValue var cruiseLengthInDays: Int = 8
	
// MARK: Images
	/// The  set of image file types that we can parse with the GD library. I believe GD hard-codes these values on install based on what ./configure finds.
	/// If our server app is moved to a new machine after it's built, the valid input types will likely differ.
	@SettingsValue var validImageInputTypes: [String] = []

	/// The  set of image file types that we can create with the GD library. I believe GD hard-codes these values on install based on what ./configure finds.
	/// If our server app is moved to a new machine after it's built, the valid input types will likely differ.
	@SettingsValue var validImageOutputTypes: [String] = []
	
	/// If FALSE, animated images are converted into static jpegs upon upload. Does not affect already uploaded images.
	@SettingsValue var allowAnimatedImages: Bool = true
}

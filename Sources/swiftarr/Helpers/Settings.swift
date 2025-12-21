import Redis
import Vapor

/// A (hopefully) thread-safe singleton that provides modifiable global settings.

final class Settings: Encodable, @unchecked Sendable {

	/// Wraps settings properties, making them thread-safe. All access to the internalValue should be done through the wrapper
	/// because of the thread-safety thing.
	@propertyWrapper class SettingsValue<T>: Encodable, @unchecked Sendable where T: Encodable & Sendable {
		fileprivate var internalValue: T
		var wrappedValue: T {
			get { return Settings.settingsQueue.sync { internalValue } }
			set { Settings.settingsQueue.async { self.internalValue = newValue } }
		}

		init(wrappedValue: T) {
			internalValue = wrappedValue
		}

		func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(wrappedValue)
		}
	}

	/// Wraps settings properties, making them thread-safe. Contains methods for loading/storing values from a Redis hash.
	/// Use this for settings that should be database-backed.
	@propertyWrapper class StoredSettingsValue<T>: SettingsValue<T>, StoredSetting, @unchecked Sendable
	where T: Encodable & RESPValueConvertible & Sendable {
		var projectedValue: StoredSettingsValue<T> { self }
		var redisField: String
		override var wrappedValue: T {
			get { return Settings.settingsQueue.sync { internalValue } }
			set { Settings.settingsQueue.async { self.internalValue = newValue } }
		}

		init(_ field: String, defaultValue: T) {
			self.redisField = field
			super.init(wrappedValue: defaultValue)
		}

		func readFromRedis(redis: RedisClient) async throws {
			let result = try await redis.readSetting(redisField)
			if let value = T(fromRESP: result) {
				self.wrappedValue = value
			}
		}

		// Call after setting value
		func writeToRedis(redis: RedisClient) async throws -> Bool {
			return try await redis.hset(redisField, to: wrappedValue, in: "Settings").get()
		}
	}

	/// The shared instance for this singleton.
	static let shared = Settings()

	/// DispatchQueue to use for thread-safety synchronization.
	fileprivate static let settingsQueue = DispatchQueue(label: "settingsQueue")

	/// The ID of the blocked user placeholder.
	@SettingsValue var blockedUserID: UUID = UUID()

	/// The ID of the FriendlyFez user placeholder.
	@SettingsValue var friendlyFezID: UUID = UUID()

	// MARK: Sections / Features / Apps
	
	/// Sets a minimum access level to use the full server. Logged-in users who don't have this access level will get errors for most routes, but won't redirect to login.
	@StoredSettingsValue("minAccessLevel", defaultValue: .banned) var minAccessLevel: UserAccessLevel

	/// If TRUE, those that don't have full server access (due to `minAccessLevel`) can create accounts, log in, and edit their user profile in an alternate, restricted UI.
	/// If FALSE, account creation is disabled and only users with certain elevated user access levels may log in.
	@StoredSettingsValue("enablePreregistration", defaultValue: false) var enablePreregistration: Bool

	/// Each key-value pair identifies an application and a set of features disabled for that application. Either the app or the featureset may contain '.all'.
	@StoredSettingsValue("disabledFeatures", defaultValue: DisabledFeaturesGroup(value: [:])) var disabledFeatures: DisabledFeaturesGroup

	/// The name of the onboard Wifi network. Delivered to cients in the notification endpoint.
	@StoredSettingsValue("shipWifiSSID", defaultValue: "NieuwAmsterdam-Guest") var shipWifiSSID: String
	
	/// The URL to use when checking for automatic schedule updates. Genearlly a sched.com URL of the form `https://jococruise2024.sched.com/all.ics`
	/// Should always point to an URL that returns an iCalendar formatted file.
	@StoredSettingsValue("scheduleUpdateURL", defaultValue: "http://jococruise2025.sched.com/all.ics") var scheduleUpdateURL: String

	// MARK: Limits
	/// The maximum number of alt accounts per primary user account.
	@StoredSettingsValue("maxAlternateAccounts", defaultValue: 6) var maxAlternateAccounts: Int

	/// The maximum number of twartts allowed per request.
	@StoredSettingsValue("maximumTwarrts", defaultValue: 200) var maximumTwarrts: Int

	/// The maximum number of twartts allowed per request.
	@StoredSettingsValue("maximumForums", defaultValue: 200) var maximumForums: Int

	/// The maximum number of twartts allowed per request.
	@StoredSettingsValue("maximumForumPosts", defaultValue: 200) var maximumForumPosts: Int

	/// Largest image we allow to be uploaded, in bytes.
	@StoredSettingsValue("maxImageSize", defaultValue: 20 * 1024 * 1024) var maxImageSize: Int

	/// Maximum number of images allowed per forum post.
	@StoredSettingsValue("maxForumPostImages", defaultValue: 4) var maxForumPostImages: Int

	/// Default maximum HTTP request body size in bytes. Used for routes that don't specify a custom limit.
	@SettingsValue var defaultMaxBodySize: Int = 10 * 1024 * 1024

	/// Maximum HTTP request body size in bytes for routes that upload images.
	@SettingsValue var imageMaxBodySize: Int = 30 * 1024 * 1024

	/// How long a single user must wait between photostream uploads, in seconds.
	@StoredSettingsValue("photostreamUploadRateLimit", defaultValue: 300) var photostreamUploadRateLimit: TimeInterval

	// MARK: Quarantine
	/// The number of reports to trigger forum auto-quarantine.
	@StoredSettingsValue("forumAutoQuarantineThreshold", defaultValue: 3) var forumAutoQuarantineThreshold: Int

	/// The number of reports to trigger post/twarrt auto-quarantine.
	@StoredSettingsValue("postAutoQuarantineThreshold", defaultValue: 3) var postAutoQuarantineThreshold: Int

	/// The number of reports to trigger user auto-quarantine.
	@StoredSettingsValue("userAutoQuarantineThreshold", defaultValue: 5) var userAutoQuarantineThreshold: Int

	// MARK: Dates
	/// A Date set to midnight on the day the cruise ship leaves port, in the timezone the ship leaves from. Used by the Events Controller for date arithimetic.
	/// The default here should get overwritten in configure.swift. This is purely for convenience to set the start date via
	/// configure.swift. This setting should not be referenced anywhere. That's what `cruiseStartDate()` below is for.
	/// This must align with cruiseStartDayOfWeek set immediately below.
	@SettingsValue var cruiseStartDateComponents: DateComponents = DateComponents(year: 2025, month: 3, day: 2)

	/// The day of week when the cruise embarks, expressed as number as Calendar's .weekday uses them: Range 1...7, Sunday == 1.
	/// Doing DateComponents(year: 2024, month: 3, day: 9).weekday! didnt work here. Hmm....
	@SettingsValue var cruiseStartDayOfWeek: Int = 1

	/// The length in days of the cruise, includes partial days. A cruise that embarks on Saturday and returns the next Saturday should have a value of 8.
	@SettingsValue var cruiseLengthInDays: Int = 8

	/// TimeZone representative of where we departed port from. This should equal the TZ that Sched.com uses to list Events.
	@SettingsValue var portTimeZone: TimeZone = TimeZone(identifier: "America/New_York")!

	/// Struct representing a set of TimeZoneChange's for this cruise. This setting can then be referenced elsewhere in the application.
	@SettingsValue var timeZoneChanges: TimeZoneChangeSet = TimeZoneChangeSet()

	/// Hour in the server runtimes time zone to run nightly scheduled jobs.
	/// The default value of 9 is "9AM UTC" == "4AM EST" == "5AM EDT/AST" which corresponds to our
	/// historical quietest period.
	@SettingsValue var nightlyJobHour: Int = 9

	/// Number of minutes before an event to trigger notifications. Some day this should be set per-user
	/// based on their preferences. But since we don't have the concept of "User Settings" yet we set
	/// a sane default instead. This is a StoredSettingsValue so that it can be modified in real time.
	/// This is a Double because that's what most range comparison operations desire. Though it does make this
	/// a bit more complex on the Server Settings views and [Site]AdminController because we expose them as Ints
	/// to the UI. This is to prevent anyone from using truly whacky values.
	@StoredSettingsValue("upcomingEventNotificationSeconds", defaultValue: 10 * 60.0) var upcomingEventNotificationSeconds: Double

	/// Number of seconds after an upcoming event starts to no longer consider it happening.
	/// The desired default value means 5 minutes after an event starts notifications/banners will stop.
	/// However at this time, the AlertController does honor this and cycles the UserNotificationData.nextFollowedEventTime
	/// immediately afterward. Until that changes, this should be 0.
	/// This also might entirely go away? Here for consistency throughout the app, but possibly irrelevant.
	@SettingsValue var upcomingEventPastSeconds: Double = 0 * 60.0

	/// Configuration of the upcoming event notifications.
	@StoredSettingsValue("upcomingEventNotificationSetting", defaultValue: EventNotificationSetting.cruiseWeek) var upcomingEventNotificationSetting: EventNotificationSetting

	/// Configuration of the upcoming LFG notifications.
	@StoredSettingsValue("upcomingLFGNotificationSetting", defaultValue: EventNotificationSetting.current) var upcomingLFGNotificationSetting: EventNotificationSetting

	/// Enable Late Day Flip where the site UI shows the next days schedule after 3:00AM rather than after Midnight.
	/// For example, with this setting enabled opening the schedule at 2:00AM on Thursday will show you Wednesday's
	/// schedule by default. If this setting is disabled, at 2:00AM on Thursday you would see Thursdays schedule by default.
	@SettingsValue var enableLateDayFlip: Bool = false

	// MARK: Images
	/// The  set of image file types that we can parse with the GD library. I believe GD hard-codes these values on install based on what ./configure finds.
	/// If our server app is moved to a new machine after it's built, the valid input types will likely differ.
	@SettingsValue var validImageInputTypes: [String] = []

	/// The  set of image file types that we can create with the GD library. I believe GD hard-codes these values on install based on what ./configure finds.
	/// If our server app is moved to a new machine after it's built, the valid input types will likely differ.
	@SettingsValue var validImageOutputTypes: [String] = []

	/// If FALSE, animated images are converted into static jpegs upon upload. Does not affect already uploaded images.
	@StoredSettingsValue("allowAnimatedImages", defaultValue: true) var allowAnimatedImages: Bool

	/// Set the size of automatically generated image thumbnails. This is the height value in pixels.
	@SettingsValue var imageThumbnailSize: Int = 200

	// MARK: Directories
	/// Root dir for files used by Swiftarr. The front-end's CSS, JS, static image files, all the Leaf templates are in here,
	/// as are all the seeds files used for database migrations by the backend..
	/// The Resources and Seeds dirs get *copied* into this dir from the root of the git repo by the build system.
	@SettingsValue var staticFilesRootPath: URL = FileManager.default.homeDirectoryForCurrentUser

	/// User uploaded images will be inside this dir.
	@SettingsValue var userImagesRootPath: URL = URL(filePath: "./swiftarrImages", directoryHint: .isDirectory, relativeTo: FileManager.default.homeDirectoryForCurrentUser).absoluteURL

	// MARK: URLs
	/// This is the EXTERNALLY VISIBLE URL for the server. If a user asks "What should I type into my browser to get to Twitarr?" you could tell them this.
	/// The server uses this to generate URLs referring to itself. Be wary of using this for web UI URLs; it could cause cross-origin problems in browsers.
	@SettingsValue var canonicalServerURLComponents: URLComponents = URLComponents(string: "http://localhost:8081")!

	/// Canonical hostnames for the Twitarr server. The server uses this to find links to itself inside posts.
	@SettingsValue var canonicalHostnames: [String] = ["twitarr.com", "joco.hollandamerica.com"]

	/// Base URL that the web UI uses to call API level endpoints.
	@SettingsValue var apiUrlComponents: URLComponents = URLComponents(string: "http://localhost:8081/api/v3")!

	/// Enable caching the `UserNotificationData` in the users session data in `NotificationMiddleware`.
	/// Disabling this can be useful for debugging the site UI in real time.
	/// This was originally called disableSiteNotificationDataCaching requiring administrators to opt-out.
	/// But https://github.com/jocosocial/swiftarr/issues/346 got in my way. Also "enableing" a "disable"
	/// feels more gross the more I say it.
	@StoredSettingsValue("enableSiteNotificationDataCaching", defaultValue: true) var enableSiteNotificationDataCaching: Bool

}

/// Derivative directory paths. These are computed property getters that return a path based on a root path.
/// These properties could be changed into their own roots by making them into their own `@SettingsValue`s.
extension Settings {
	/// Path to the 'admin' directory, inside the 'seeds' directory. Certain seed files can be upload by admin here, and ingested while the server is running.
	var adminDirectoryPath: URL {
		let result = userImagesRootPath.appendingPathComponent("seeds/admin")
		try? FileManager.default.createDirectory(at: result, withIntermediateDirectories: true, attributes: nil)
		return result
	}

	/// Path to the 'admin' directory, inside the 'seeds' directory. Certain seed files can be upload by admin here, and ingested while the server is running.
	var seedsDirectoryPath: URL {
		return staticFilesRootPath.appendingPathComponent("seeds")
	}
}

/// Provide one common place for time-related objects.
extension Settings {
	func cruiseStartDate() -> Date {
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = portTimeZone
		var startDateComponents = cruiseStartDateComponents
		startDateComponents.calendar = Calendar(identifier: .gregorian)
		startDateComponents.timeZone = portTimeZone
		guard let result = cal.date(from: startDateComponents) else {
			fatalError("Swiftarr Settings: must be able to produce a Date from cruiseStartDate.")
		}
		return result
	}

	/// Calendar to use for calculating dates (like what day it is). The returned calendar has the correct timezone for the given date.
	func calendarForDate(_ date: Date) -> Calendar {
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = timeZoneChanges.tzAtTime(date)
		return cal
	}
	
	func getPortCalendar() -> Calendar {
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = portTimeZone
		return cal
	}

	// Generate a `Date` that lets us pretend we are at that point in time during the sailing.
	// It can be difficult to test schedule functionality because the events are all coded for
	// their actual times. So at various points in the app we display the data of "what would be".
	// This takes it a step further and pretends based on the time rather than just a weekday.
	//
	// There have been multiple version of this function over time that deal with DST to various
	// degrees of success. This code was lifted from EventController and seems to do the job 
	// "correctly". Hey we even have tests for it now.
	func getDateInCruiseWeek(from date: Date = Date()) -> Date {
		let cruiseStartDate = Settings.shared.cruiseStartDate()
		var filterDate = date
		// If the cruise is in the future or more than 10 days in the past, construct a fake date during the cruise week
		let secondsPerDay = 24 * 60 * 60.0
		if cruiseStartDate.timeIntervalSinceNow > 0
			|| cruiseStartDate.timeIntervalSinceNow < 0 - Double(Settings.shared.cruiseLengthInDays) * secondsPerDay
		{
			// This filtering nonsense is whack. There is a way to do .DateComponents() without needing the in: but then you
			// have to specify the Calendar.Components that you want. Since I don't have enough testing around this I'm going
			// to keep pumping the timezone in which lets me bypass that requirement.
			let cal = Settings.shared.getPortCalendar()
			var filterDateComponents = cal.dateComponents(in: Settings.shared.portTimeZone, from: cruiseStartDate)
			let currentDateComponents = cal.dateComponents(in: Settings.shared.portTimeZone, from: filterDate)
			filterDateComponents.hour = currentDateComponents.hour
			filterDateComponents.minute = currentDateComponents.minute
			filterDateComponents.second = currentDateComponents.second
			filterDate = cal.date(from: filterDateComponents) ?? filterDate
			if let currentDayOfWeek = currentDateComponents.weekday {
				let daysToAdd = (7 + currentDayOfWeek - Settings.shared.cruiseStartDayOfWeek) % 7
				if let adjustedDate = cal.date(byAdding: .day, value: daysToAdd, to: filterDate) {
					filterDate = adjustedDate
				}
			}
		}
		return filterDate
	}

	// This is sufficiently complex enough to merit its own function. Unlike the Settings.shared.getDateInCruiseWeek(),
	// just adding .seconds to Date() isn't enough because Date() returns millisecond-precision. Which no one tells you
	// unless you do a .timeIntervalSince1970 and get the actual Double value back to look at what's behind the dot.
	// I'm totally not salty about spending several hours chasing this down. Anywho...
	// This takes the current Date(), strips the ultra-high-precision that we don't want, and returns Date().
	func getCurrentFilterDate(from date: Date = Date()) -> Date {
		let todayCalendar = Settings.shared.calendarForDate(date)
		let todayComponents = todayCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
		return todayCalendar.date(from: todayComponents)!
	}

	// Common accessor for getting a comparison reference date to an Event or LFG.
	// Often in the code we use Date() to get the current time, but this can sometimes cause
	// strange behavior because we occasionally pretend to be in the cruise week.
	func getScheduleReferenceDate(_ settingType: EventNotificationSetting, from date: Date = Date()) -> Date {
		// The reference date is calculated as either:
		// 1) The current date (as in what the server is experiencing right now).
		// 2) The current time/day transposed within the cruise week (when we pretend it is).
		var filterDate: Date
		if (settingType == .cruiseWeek) {
			filterDate = Settings.shared.getDateInCruiseWeek(from: date)
		} else {
			filterDate = Settings.shared.getCurrentFilterDate(from: date)
		}
		return filterDate
	}

}

protocol StoredSetting {
	func readFromRedis(redis: RedisClient) async throws
	func writeToRedis(redis: RedisClient) async throws -> Bool
}

extension Settings {
	// Reads settings from Redis
	func readStoredSettings(app: Application) async throws {
		for child in Mirror(reflecting: self).children {
			guard let storedSetting = child.value as? StoredSetting else {
				continue
			}
			try await storedSetting.readFromRedis(redis: app.redis)
		}
		try await readTimeZoneChanges(app)
	}

	// Stores all settings to Redis
	func storeSettings(on req: Request) async throws {
		for child in Mirror(reflecting: self).children {
			if let storedSetting = child.value as? StoredSetting {
				_ = try await storedSetting.writeToRedis(redis: req.redis)
			}
		}
	}

	// TimeZoneChanges load in from postgres
	func readTimeZoneChanges(_ app: Application) async throws {
		timeZoneChanges = try await TimeZoneChangeSet(app.db)
	}
}

// To maintain thread safety, this 1-value struct needs to be immutable, so that mutating Settings.disabledFeatures
// can only be done by swapping out this entire struct.
struct DisabledFeaturesGroup: Codable, RESPValueConvertible {
	let value: [SwiftarrClientApp: Set<SwiftarrFeature>]

	init(value: [SwiftarrClientApp: Set<SwiftarrFeature>]) {
		self.value = value
	}

	init?(fromRESP value: RESPValue) {
		guard let encodedData = value.string?.data(using: .utf8),
			let val = try? JSONDecoder().decode([SwiftarrClientApp: Set<SwiftarrFeature>].self, from: encodedData)
		else {
			return nil
		}
		self.value = val
	}

	func convertedToRESPValue() -> RESPValue {
		guard let encodedData = try? JSONEncoder().encode(value),
			let encodedStr = String(data: encodedData, encoding: .utf8)
		else {
			return RESPValue(from: "")
		}
		return RESPValue(from: encodedStr)
	}

	func buildDisabledFeatureArray() -> [DisabledFeature] {
		var result = [DisabledFeature]()
		self.value.forEach { (appName, features) in
			for feature in features {
				result.append(DisabledFeature(appName: appName, featureName: feature))
			}
		}
		return result
	}
	
	// Returns TRUE if:
	// 		- The given feature is disabled for the given app (if an app is provided)
	//		- The given feature is disabled for all apps
	//		- All features are disabled for the given app (if an app is provided)
	//		- All features are disabled for all apps
	// Note: Althogh this fn shows how to do it, the server shouldn't be evaluating individual app disables 
	// other than the built-in swiftarr web UI. Clients should be doing that themselves with the info the server provides.
	func isFeatureDisabled(_ feature: SwiftarrFeature, inApp: SwiftarrClientApp? = nil) -> Bool {
		if let allApps = value[.all], allApps.contains(feature) || allApps.contains(.all) {
			return true
		}
		if let app = inApp, let appDisables = value[app], appDisables.contains(feature) || appDisables.contains(.all) {
			return true
		}
		return false
	}
}

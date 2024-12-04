import Foundation
import Vapor
import Fluent

/// A `TimeZoneChange` model says that at a specific UTC Date the ship will adopt a given timezone, specified by abbreviation and UTC offset.
/// 
/// The 'current' TimeZoneChange is the one with the a start date in the most recent past.  The timezone indicated by the current TimeZoneChange 
/// is in force until the next (in Date order) TimeZoneChange becomes current.
/// 
final class TimeZoneChange: Model {
	static let schema = "time_zone_change"
	
   // MARK: Properties
	
	/// The TimeZoneChange's ID, provisioned automatically.
	@ID(key: .id) var id: UUID?
	
	/// The time, in absolute tems, when this Time Zone comes into effect. The TZ stays in effect until superceded by another TimeZoneChange; the last one is in effect forever, as far as we're concerned.
	@Field(key: "start_time") var startTime: Date
		
	/// Abbreviation of the timezone, such as EST.
	@Field(key: "timezone_name") var timeZoneName: String

	/// Foundation has a bunch of TimeZone Identifier strings for timezones, and they specify a timezone with more granularity than an EST-style abbreviation.
	/// For example, `America/Halifax` and `America/Puerto_Rico` are both in the AST timezone, but Halifax observes DST and Puerto Rico doesn't.
	@Field(key: "timezone_id") var timeZoneID: String
	
	// MARK: Initializaton
	
	// Used by Fluent
 	init() { }
 	
	/// Initializes a new TimeZoneChange.
	///
	/// - Parameters:
	///   - startTime: When the timezone goes into effect
	///   - offset: GMT offset in hours.
	///   - name: The abbreviated name for the timezone, e.g. "EST".
	///   - id: The Apple identifier for the timezone, e.g. "America/New_York".
	init(startTime: Date, name: String, id: String) throws {
		guard TimeZone(identifier: id) != nil else {
			throw Abort(.internalServerError, reason: "TimeZoneChange Identifier \"\(id)\" not in the list of Time Zone Identifiers (Identifiers aren't abreviations like \"EST\").")
		}
		self.startTime = startTime
		self.timeZoneName = name
		self.timeZoneID = id
	}
}

/// This is the migration that creates the TimeZoneChange table.
struct CreateTimeZoneChangeSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("time_zone_change")
				.id()
				.field("start_time", .datetime, .required)
 				.field("timezone_name", .string, .required)
 				.field("timezone_id", .string, .required)
				.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("time_zone_change").delete()
	}
}

// An easy way to use TimeZoneChanges. Create one of these with its async init, then get the TimeZone
// the boat will be in at a given time. 
struct TimeZoneChangeSet : Codable {
	var changePoints: [TimeZoneChange] = []
	
	/// Required by Settings, but not useful with this initializer. Hopefully this becomes more fixable when Settings becomes an Actor.
	init() {
		changePoints = []
	}
	
	/// Loads all the `TimeZoneChange` entries in the db into an array and stores them in this object.
	init(_ db: Database) async throws {
		changePoints = try await TimeZoneChange.query(on: db).sort(\.$startTime, .ascending).all()
	}
	
	/// Returns the TimeZone the ship will be in at the given Date, or the current time if no Date specified. If you're using this with a 'floating' date (e.g. "2:00 PM in whatever
	/// timezone the boat is in that day") be sure to call `portTimeToDisplayTime()` first, and call this fn with the returned Date.
	func tzAtTime(_ time: Date? = nil) -> TimeZone {
		let actualTime = time ?? Date()
		if let currentTZ = changePoints.last(where: { $0.startTime <= actualTime }),
				let result = TimeZone(identifier: currentTZ.timeZoneID) ?? TimeZone(abbreviation: currentTZ.timeZoneName) {
			return result
		}
		return Settings.shared.portTimeZone
	}
	
	/// Returns the 3 letter abbreviation for the time zone the ship will be in at the given Date, or the current time if no Date specified. If you're using this with 
	/// a 'floating' date (e.g. "2:00 PM in whatever timezone the boat is in that day") be sure to call `portTimeToDisplayTime()` first, and call this fn with the returned Date.
	/// Also, do not use these abbreviations to later make TimeZone objects (with `TimeZone(abbreviation:)`). Use `tzAtTime()` instead.
	func abbrevAtTime(_ time: Date? = nil) -> String {
		let actualTime = time ?? Date()
		if let currentRecord = changePoints.last(where: { $0.startTime <= actualTime }),
				let tz = TimeZone(identifier: currentRecord.timeZoneID) ?? TimeZone(abbreviation: currentRecord.timeZoneName) {
			return tz.abbreviation(for: actualTime) ?? currentRecord.timeZoneName
		}
		return Settings.shared.portTimeZone.abbreviation(for: actualTime) ?? "EST"
	}
	
	// Twitarr often has to deal with Date objects that actually attempt to specify a 'floating local time', e.g. `March 10, 2:00 PM`
	// in whatever the local timezone is on March 10th. However, we store dates as Date() objects, which are just Doubles and don't
	// support a floating local time concept. And no, we're not going to switch to storing "20220310T1400" strings, that's a recipe
	// for about a million sort bugs. 
	// 
	// Instead, we declare floating Dates stored in the db to be in 'port time', usually EST for sailings departing Fort Lauderdale.
	// The advantage over storing GMT is that the dates are +/- one hour from the 'correct' time, reducing the severity of mistakes
	// with filters that grab "all events happening on Tuesday". When the API delivers Date objects to clients we convert the date
	// into the current timezone the boat is in. 
	//
	// This means that if for some reason the boat isn't where it's expected to be or the captain declares an unexpected TZ change,
	// all 'floating' dates will still be correct once the TimeZoneChange table is updated.
	//
	// Finally: call this fn to convert timezones. Make another fn like this one if you need to do another kind of tz conversion.
	// Do not calculate the offset between timezones and add/subtract that value from a Date object.
	func portTimeToDisplayTime(_ time: Date? = nil) -> Date {
		let actualTime = time ?? Date()
		if let currentRecord = changePoints.last(where: { $0.startTime <= actualTime }), 
				let currentTZ = TimeZone(identifier: currentRecord.timeZoneID) {
			let cal = Settings.shared.getPortCalendar()
			var dateComponents = cal.dateComponents(in: Settings.shared.portTimeZone, from: actualTime)
			dateComponents.timeZone = currentTZ
			return cal.date(from: dateComponents) ?? actualTime
		}
		return actualTime
	}
	
	// Adjusts the given Date so that it's the same 'clock time' but in the boat's Port timezone. Useful for building queries
	// against Date objects in the db that are really 'floating' dates meant to be interpreted as 'clock time' in the local tz.
	func displayTimeToPortTime(_ time: Date? = nil) -> Date {
		let actualTime = time ?? Date()
		if let currentRecord = changePoints.last(where: { $0.startTime <= actualTime }), 
				let currentTZ = TimeZone(identifier: currentRecord.timeZoneID) {
			let cal = Settings.shared.getPortCalendar()
			var dateComponents = cal.dateComponents(in: currentTZ, from: actualTime)
			dateComponents.timeZone = Settings.shared.portTimeZone
			return cal.date(from: dateComponents) ?? actualTime
		}
		return actualTime
	}
	
	// When a user submits a time value for a future date, they usually enter what's effectively an HTML 'datetime-local', 
	// (even native clients do this unless they ask for a TZ specifically). The user sees "5 PM Thursday" but the server
	// sees a UTC Date value.
	//
	// Assuming the user's TZ is set correctly, the UTC date object we get is 5 PM Thursday in the *current server* TZ, not necessarily the TZ
	// the boat will be in at that future time. So, we offset the date value to be 5 PM Thursday in the port timezone when we save it to the db,
	// and offset it again on retrieval to be in the tz the boat will be in at the given time.
	//
	// Note that this SHOULD NOT BE USED for timestamping things. When saving a db record with a timestamp, that timestamp is the 
	// absolute time 'now', and should not be modified for time zones.
	func serverTimeToPortTime(_ time: Date?) -> Date? {
		guard let time else { return nil }
		let currentTime = Date()
		if let currentRecord = changePoints.last(where: { $0.startTime <= currentTime }), 
				let currentTZ = TimeZone(identifier: currentRecord.timeZoneID) {
			let cal = Settings.shared.getPortCalendar()
			var dateComponents = cal.dateComponents(in: currentTZ, from: time)
			dateComponents.timeZone = Settings.shared.portTimeZone
			return cal.date(from: dateComponents) ?? time
		}
		return time
	}
}

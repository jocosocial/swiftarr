import Fluent
import Foundation
import Vapor

/// Parser for a sched.com `.ics` file, based on https://jococruise2019.sched.com export.

final class EventParser {

	/// Parses an array of raw sched.com `.ics` strings to an `Event` array.
	///
	/// - Parameters:
	///   - icsArray: Array of strings from a sched.com `.ics` export.
	///   - connection: The connection to a database.
	/// - Returns: `[Event]` containing the events.
	func parse(_ dataString: String) throws -> [Event] {
		var icsArray = dataString.split(whereSeparator: \.isNewline)
		// Unfold any folded lines
		for icsIndex in (1..<icsArray.count).reversed() {
			if let firstChar = icsArray[icsIndex].first, firstChar.isWhitespace {
				icsArray[icsIndex - 1].append(contentsOf: icsArray[icsIndex].dropFirst())
				icsArray.remove(at: icsIndex)
			}
		}
		var events: [Event] = []
		var eventComponents: [String] = []
		var inEvent: Bool = false
		var lineIndex = 1
		for element in icsArray {
			switch element {
				case "BEGIN:VEVENT":
					if inEvent {
						throw Abort(.internalServerError, reason: "Found a BEGIN:VEVENT while processing an event -> near line \(lineIndex)")
					}
					inEvent = true
					eventComponents = []
				case "END:VEVENT":
					if !inEvent {
						throw Abort(.internalServerError, reason: "Found an END:VEVENT with no matching BEGIN -> near line \(lineIndex)")
					}
					do {
						if inEvent, let event = try makeEvent(from: eventComponents) {
							events.append(event)
						}
					}
					catch let err as Abort {
						var wrappedError = err
						wrappedError.reason += " -> processing event ending at line \(lineIndex)"
						throw wrappedError
					}
					inEvent = false
				// Here is where we could put tag recognizers for other iCal objects: VALARM and VTIMEZONE are likely additions,
				// but VTODO, VFREEBUSY and VJOURNAL could show up as well.
				default:
					break
			}
			if inEvent { 
				// Gather components of this event
				eventComponents.append(String(element))
			}
			lineIndex += 1
		}
		return events
	}

	/// Creates an `Event` from an array of the raw lines appearing between `BEGIN:VEVENT` and
	/// `END:VEVENT` lines in a sched.com `.ics` file. Escape characters that may appear in
	/// "SUMMARY", "DESCRIPTION" and "LOCATION" values are stripped.
	///
	/// - Parameter components: `[String]` containing the lines to be processed.
	/// - Returns: `Event` if the date strings could be parsed, else `nil`.
	func makeEvent(from properties: [String]) throws -> Event? {
		var startTime: Date?
		var endTime: Date?
		var title: String?
		var description: String = ""
		var location: String = ""
		var eventType: EventType = .general
		var uid: String?

		do {
			for property in properties {
				// stray newlines make empty elements
				guard !property.isEmpty else {
					continue
				}
				let pair = property.split(separator: ":", maxSplits: 1)
				let keyParams = pair[0].split(separator: ";")
				let key = keyParams[0].uppercased()
				let value = (pair.count == 2 ? String(pair[1]) : "")
						.replacingOccurrences(of: "&amp;", with: "&")
						.replacingOccurrences(of: "\\\\", with: "\\")
						.replacingOccurrences(of: "\\,", with: ",")
						.replacingOccurrences(of: "\\;", with: ";")
						.replacingOccurrences(of: "\\n", with: "\n")
						.replacingOccurrences(of: "\\N", with: "\n")
				switch key {
				case "DTSTART":
					startTime = try parseDateFromProperty(property: keyParams, value: value)
				case "DTEND":
					endTime = try parseDateFromProperty(property: keyParams, value: value)
				case "SUMMARY":
					title = unescapedTextValue(value)
				case "DESCRIPTION":
					description = unescapedTextValue(value)
				case "LOCATION":
					location = unescapedTextValue(value)
				case "CATEGORIES":
					var firstCat = (value.split(separator: ",").first ?? "").trimmingCharacters(in: .whitespaces).uppercased()
					firstCat = unescapedTextValue(firstCat)
					switch firstCat {
					case "GAMING":
						eventType = .gaming
					case "LIVE PODCAST":
						eventType = .livePodcast
					case "MAIN CONCERT":
						eventType = .mainConcert
					case "OFFICE HOURS":
						eventType = .officeHours
					case "PARTY":
						eventType = .party
					case "Q&A / PANEL", "Q&A", "PANEL":						// "Q&A" and "PANEL" are not canonical
						eventType = .qaPanel
					case "READING / PERFORMANCE", "READING", "PERFORMANCE": // "READING" and "PERFORMANCE" are not canonical
						eventType = .readingPerformance
					case "SHADOW CRUISE":
						eventType = .shadow
					case "SIGNING":
						eventType = .signing
					case "WORKSHOP":
						eventType = .workshop
					default:
						eventType = .general
					}
				case "UID":
					uid = value
				default:
					continue
				}
			}
		}
		guard let start = startTime, let end = endTime, let title = title, let uid = uid else {
			throw Abort(.internalServerError, reason: "Event object missing required properties")
		}
		return Event(startTime: start, endTime: end, title: title, description: description, location: location,
				eventType: eventType, uid: uid)
	}
	
	// Used to remove .ics character escape sequeneces from TEXT value types. The spec specifies different escape sequences for 
	// text-valued property values than for other value types, or for strings that aren't property values.
	func unescapedTextValue(_ value: any StringProtocol) -> String {
		return value.replacingOccurrences(of: "&amp;", with: "&")
				.replacingOccurrences(of: "\\\\", with: "\\")
				.replacingOccurrences(of: "\\,", with: ",")
				.replacingOccurrences(of: "\\;", with: ";")
				.replacingOccurrences(of: "\\n", with: "\n")
				.replacingOccurrences(of: "\\N", with: "\n")
	}
	
	// A DateFormatter for converting ISO8601 strings of the form "19980119T070000Z". RFC 5545 calls these 'form 2' date strings.
	let gmtDateFormatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
		dateFormatter.timeZone = TimeZone(identifier: "GMT")
		return dateFormatter
	}()
	
	// From testing: If the dateFormat doesn't have a 'Z' GMT specifier, conversion will fail if the string to convert contains a 'Z'. 
	let tzDateFormatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
		dateFormatter.timeZone = TimeZone(identifier: "GMT")
		return dateFormatter
	}()
	
	// Even if the Sched.com file were to start using floating datetimes (which would solve several timezone problems) we're not
	// currently set up to work with them directly. Instead we convert all ics datetimes to Date() objects, and try to get the tz right.
	// This also means that 'Form 3' dates (ones with a time zone reference) lose their associated timezone but still indicate the 
	// correct time.
	func parseDateFromProperty(property keyAndParams: [Substring], value: String) throws -> Date {
		for index in 1..<keyAndParams.count {
			// The TZID parameter value points to a "VTIMEZONE" component in the file if the TZID doesn't start with "/", or
			// a value from a "globally defined timezone registry" if the TZID value is prefixed with "/"
			var timeZoneID: Substring?
			if keyAndParams[index].hasPrefix("TZID=/") {
				timeZoneID = keyAndParams[index].dropFirst(6)
			}
			else if keyAndParams[index].hasPrefix("TZID=") {
				// Even if the TZID points to a local iCal object, the name might match a TZ identifier. It'll just fail if it's not.
				// I'm not adding code to parse the local VTIMEZONE component, because it's insane.
				timeZoneID = keyAndParams[index].dropFirst(5)
			}
			if let tzIdentifier = timeZoneID {
				guard let tz = TimeZone(identifier: String(tzIdentifier)) else {
					throw Abort(.internalServerError, reason: "Event Parser: couldn't create timezone from identifier.")
				}
				tzDateFormatter.timeZone = tz
				// An ics date value that has a timezone property must be a Form 3 date like "19980119T020000"
				guard let result = tzDateFormatter.date(from: String(value)) else {
					throw Abort(.internalServerError, reason: "Event Parser: couldn't parse a date value.")
				}
				return result
			}
		}
		tzDateFormatter.timeZone = Settings.shared.portTimeZone
		if let floatingDate = tzDateFormatter.date(from: String(value)) {
			// A floating date is 'whatever tz we're in at that time' and the tzChangeSet tells us what timezone we'll be in.
			let tzChangeSet = Settings.shared.timeZoneChanges
			return tzChangeSet.portTimeToDisplayTime(floatingDate)
		}
		else if let gmtDate = gmtDateFormatter.date(from: String(value)) {
			return gmtDate
		}
		else {
			throw Abort(.internalServerError, reason: "Event Parser: couldn't parse a date value.")
		}
	}
}

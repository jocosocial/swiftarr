import Foundation

// This is a collection of functions to build ICS files from event-like objects.
// It previously lived in the SiteEventsController but with the addition of PersonalEvents
// the code got a bit unwieldy.
final class ICSHelper {
	static func buildEventICS(events: [EventData], username: String = "") -> String {
		let yearFormatter = DateFormatter()
		yearFormatter.setLocalizedDateFormatFromTemplate("y")
		let cruiseYear = yearFormatter.string(from: Settings.shared.cruiseStartDate())
		var resultICSString = """
			BEGIN:VCALENDAR
			VERSION:2.0
			X-WR-CALNAME:JoCo Cruise \(cruiseYear): \(username)
			X-WR-CALDESC:Event Calendar
			METHOD:PUBLISH
			CALSCALE:GREGORIAN
			PRODID:-//Sched.com JoCo Cruise \(cruiseYear)//EN
			X-WR-TIMEZONE:UTC

			"""
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
		for event: EventData in events {
			let startTime = dateFormatter.string(from: event.startTime)
			let endTime = dateFormatter.string(from: event.endTime)
			let stampTime = dateFormatter.string(from: event.lastUpdateTime)  // DTSTAMP is when the ICS was last modified.
			resultICSString.append(
				"""
				BEGIN:VEVENT
				DTSTAMP:\(stampTime)
				DTSTART:\(startTime)
				DTEND:\(endTime)
				SUMMARY:\(icsEscapeString(event.title))
				DESCRIPTION:\(icsEscapeString(event.description))
				CATEGORIES:\(icsEscapeString(event.eventType))
				LOCATION:\(icsEscapeString(event.location))
				SEQUENCE:0
				UID:\(icsEscapeString(event.uid))
				URL:https://jococruise\(cruiseYear).sched.com/event/\(event.uid)
				END:VEVENT

				"""
			)
		}
		resultICSString.append(
			"""
			END:VCALENDAR

			"""
		)
		return resultICSString
	}

	static func buildPersonalEventICS(events: [PersonalEventData], username: String = "") -> String {
		let yearFormatter = DateFormatter()
		yearFormatter.setLocalizedDateFormatFromTemplate("y")
		let cruiseYear = yearFormatter.string(from: Settings.shared.cruiseStartDate())
		var resultICSString = """
			BEGIN:VCALENDAR
			VERSION:2.0
			X-WR-CALNAME:JoCo Cruise \(cruiseYear): \(username)
			X-WR-CALDESC:Event Calendar
			METHOD:PUBLISH
			CALSCALE:GREGORIAN
			PRODID:-//Twitarr.com JoCo Cruise \(cruiseYear)//EN
			X-WR-TIMEZONE:UTC

			"""
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
		for event: PersonalEventData in events {
			let startTime = dateFormatter.string(from: event.startTime)
			let endTime = dateFormatter.string(from: event.endTime)
			let stampTime = dateFormatter.string(from: event.lastUpdateTime)  // DTSTAMP is when the ICS was last modified.
			// TODO URL:https://twitarr.com/personalevents/\(event.personalEventID)

			// If a user made a personal event on the pre-reg server, exported the event
			// to their calendar app, and then re-exported once on the boat,
			// they would get their events doubled up, unless they have the same UID.
			// Having a separate UID field lets you retain the value if the event
			// moves from one server to another.
			let uid = CryptoHelper.sha256Hash(of: "\(startTime)_\(event.personalEventID.uuidString)")
			resultICSString.append(
				"""
				BEGIN:VEVENT
				DTSTAMP:\(stampTime)
				DTSTART:\(startTime)
				DTEND:\(endTime)
				SUMMARY:\(icsEscapeString(event.title))
				DESCRIPTION:\(icsEscapeString(event.description ?? ""))
				LOCATION:\(icsEscapeString(event.location ?? ""))
				SEQUENCE:0
				UID:\(icsEscapeString(uid))
				END:VEVENT

				"""
			)
		}
		resultICSString.append(
			"""
			END:VCALENDAR

			"""
		)
		return resultICSString
	}

	// the ICS file format has specific string escaping requirements. See https://datatracker.ietf.org/doc/html/rfc5545
	private static func icsEscapeString(_ str: String) -> String {
		let result = str.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: ";", with: "\\;")
			.replacingOccurrences(of: ",", with: "\\,")
			.replacingOccurrences(of: "\n", with: "\\n")
		return result
	}
}

import Foundation

// NOTES:
//
// Adding "ATTENDEE" and "ORGANIZER" fields to VEVENTs works, sorta--but we don't have email or LDAP URIs to the
// user's contact info, so these fields don't work great. Also, Apple Calendar really wants to create Address Book entries
// when you click through, and that doesn't make much sense for our use case.
//
// COMMENT fields don't appear to show up in Apple Calendar.
// CONTACT fields don't appear to show up in Apple Calendar.


// This is a collection of functions to build ICS files from event-like objects.
// It previously lived in the SiteEventsController but with the addition of PersonalEvents
// the code got a bit unwieldy.
final class ICSHelper {
	enum ContentType {
		case scheduleEvents
		case personalEvents
		case dayplanner
	}

	static func buildScheduleEventICS(events: [EventData] = [], username: String = "") -> String {
		return buildICSFile(events: events, username: username, contentType: .scheduleEvents)		
	}

	static func buildPersonalEventICS(personalEvents: [PersonalEventData] = [], username: String = "") -> String {
		return buildICSFile(personalEvents: personalEvents, username: username, contentType: .personalEvents)		
	}

	static func buildICSFile(events: [EventData] = [], lfgs: [FezData] = [],
			personalEvents: [PersonalEventData] = [], username: String = "", contentType: ContentType) -> String {
		let yearFormatter = DateFormatter()
		yearFormatter.setLocalizedDateFormatFromTemplate("y")
		let cruiseYear = yearFormatter.string(from: Settings.shared.cruiseStartDate())
		var contentDescription = "Joco Events"
		var urlString: String?
		switch contentType {
			case .scheduleEvents: contentDescription = "Schedule Events you're following"
			case .personalEvents: contentDescription = "Private Events where you're a member"
			case .dayplanner: contentDescription = "Schedule Events you're following, plus the Looking For Groups and Private Events where you're a member."
				var urlComponents = Settings.shared.canonicalServerURLComponents
				urlComponents.path = "/dayplanner/\(username)/jocoDayPlanner.ics"
				urlString = urlComponents.string
		}
		let contentDescriptionLine = "DESCRIPTION:\(icsEscapeTextValue(contentDescription))\n"
		let sourceLine = urlString != nil ? "SOURCE;VALUE=URI:\(urlString!)\n" : ""
		var resultICSString = """
			BEGIN:VCALENDAR
			VERSION:2.0
			X-WR-CALNAME:JoCo Cruise \(cruiseYear): \(username)
			X-WR-CALDESC:Event Calendar
			METHOD:PUBLISH
			CALSCALE:GREGORIAN
			PRODID:-//Twitarr.com JoCo Cruise \(cruiseYear)//EN
			NAME:JoCo Cruise \(cruiseYear): \(icsEscapeTextValue(username))
			\(contentDescriptionLine)\
			\(sourceLine)\
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
				SUMMARY:\(icsEscapeTextValue(event.title))
				DESCRIPTION:\(icsEscapeTextValue(event.description))
				CATEGORIES:\(icsEscapeTextValue(event.eventType))
				LOCATION:\(icsEscapeTextValue(event.location))
				SEQUENCE:0
				UID:\(icsEscapeTextValue(event.uid))
				URL:https://jococruise\(cruiseYear).sched.com/event/\(event.uid)
				END:VEVENT

				"""
			)
		}
		
		for lfg in lfgs {
			guard let startTime = lfg.startTime, let endTime = lfg.endTime else {
				continue
			}
			let startTimeStr = dateFormatter.string(from: startTime)
			let endTimeStr = dateFormatter.string(from: endTime)
			let stampTimeStr = dateFormatter.string(from: lfg.lastModificationTime)  // DTSTAMP is when the ICS was last modified.

			// If a user made a personal event on the pre-reg server, exported the event
			// to their calendar app, and then re-exported once on the boat,
			// they would get their events doubled up, unless they have the same UID.
			// Having a separate UID field lets you retain the value if the event
			// moves from one server to another.
			let uid = CryptoHelper.sha256Hash(of: "\(startTime)_\(lfg.fezID.uuidString)")
			resultICSString.append(
				"""
				BEGIN:VEVENT
				DTSTAMP:\(stampTimeStr)
				DTSTART:\(startTimeStr)
				DTEND:\(endTimeStr)
				SUMMARY:\(icsEscapeTextValue(lfg.title))
				DESCRIPTION:\(icsEscapeTextValue(lfg.info))
				LOCATION:\(icsEscapeTextValue(lfg.location ?? ""))
				SEQUENCE:0
				UID:\(icsEscapeTextValue(uid))
				URL:http://\(Settings.shared.canonicalServerURLComponents.host ?? "twitarr.com")/lfg/\(lfg.fezID)
				END:VEVENT

				"""
			)
		}
		for event: PersonalEventData in personalEvents {
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
				SUMMARY:\(icsEscapeTextValue(event.title))
				DESCRIPTION:\(icsEscapeTextValue(event.description ?? ""))
				LOCATION:\(icsEscapeTextValue(event.location ?? ""))
				SEQUENCE:0
				UID:\(icsEscapeTextValue(uid))
				END:VEVENT

				"""
			)
		}
		resultICSString.append("END:VCALENDAR\n")
		return resultICSString
	}

	// the ICS file format has specific string escaping requirements. See https://datatracker.ietf.org/doc/html/rfc5545
	// Escaping rules are specific to each value type, so this fn encodes 'TEXT' property values (RFC 5545, sec 3.3.11)
	private static func icsEscapeTextValue(_ str: String) -> String {
		let result = str.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: ";", with: "\\;")
			.replacingOccurrences(of: ",", with: "\\,")
			.replacingOccurrences(of: "\n", with: "\\n")
		return result
	}
	
	// RFC 6868 adds a new escaping scheme for parameter values (NOT property values!), so if we need to generate these,
	// we'll need to use their weird '^' escaping.
	// for reference: PROPERTYNAME;PARAMETERNAME="parameter value":propertyvalue

}

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

// MARK: Validation

	/// Takes an .ics Schedule file and compares it against  the db. Returns a summary of what would change if the schedule is applied. Shows deleted events, added events,
	/// events with modified times, events with changes to their title or description text).
	///
	/// - Parameters:
	///   - scheduleFileStr: The contents of an ICS file; usually a sched.com `.ics` export. Conforms to RFC 5545.
	///   - db: The connection to a database.
	///
	/// - Returns: `EventUpdateDifferenceData` with info on the events that were modified/added/removed .
	func validateEventsInICS(_ scheduleFileStr: String, on db: Database) async throws -> EventUpdateDifferenceData {
		let updateEvents = try parse(scheduleFileStr)
		let existingEvents = try await Event.query(on: db).all()
		// Convert to dictionaries, keyed by uid of the events
		let existingEventDict = Dictionary(existingEvents.map { ($0.uid, $0) }) { first, _ in first }
		let updateEventDict = Dictionary(updateEvents.map { ($0.uid, $0) }) { first, _ in first }
		let existingEventuids = Set(existingEvents.map { $0.uid })
		let updateEventuids = Set(updateEvents.map { $0.uid })
		var responseData = EventUpdateDifferenceData()

		// Deletes
		let deleteduids = existingEventuids.subtracting(updateEventuids)
		try deleteduids.forEach { uid in
			if let existing = existingEventDict[uid] {
				try responseData.deletedEvents.append(EventData(existing))
			}
		}

		// Creates
		let createduids = updateEventuids.subtracting(existingEventuids)
		createduids.forEach { uid in
			if let updated = updateEventDict[uid] {
				// This eventData uses a throwaway UUID as the Event isn't in the db yet
				let eventData = EventData(
					eventID: UUID(),
					uid: updated.uid,
					title: updated.title,
					description: updated.description,
					startTime: updated.startTime,
					endTime: updated.endTime,
					timeZone: "",
					timeZoneID: "",
					location: updated.location,
					eventType: updated.eventType.rawValue,
					lastUpdateTime: updated.updatedAt ?? Date(),
					forum: nil,
					isFavorite: false,
					performers: []
				)
				responseData.createdEvents.append(eventData)
			}
		}

		// Updates
		let updatedEvents = existingEventuids.intersection(updateEventuids)
		updatedEvents.forEach { uid in
			if let existing = existingEventDict[uid], let updated = updateEventDict[uid] {
				let eventData = EventData(
					eventID: UUID(),
					uid: updated.uid,
					title: updated.title,
					description: updated.description,
					startTime: updated.startTime,
					endTime: updated.endTime,
					timeZone: "",
					timeZoneID: "",
					location: updated.location,
					eventType: updated.eventType.rawValue,
					lastUpdateTime: updated.updatedAt ?? Date(),
					forum: nil,
					isFavorite: false,
					performers: []
				)
				if existing.startTime != updated.startTime || existing.endTime != updated.endTime {
					responseData.timeChangeEvents.append(eventData)
				}
				if existing.location != updated.location {
					responseData.locationChangeEvents.append(eventData)
				}
				if existing.title != updated.title || existing.info != updated.info
					|| existing.eventType != updated.eventType
				{
					responseData.minorChangeEvents.append(eventData)
				}
			}
		}

		return responseData
	}

	/// Takes an .ics Schedule file, updates the db with new info from the schedule. Returns a summary of what changed and how (deleted events, added events,
	/// events with modified times, events with changes to their title or description text).
	///
	/// - Parameters:
	///   - scheduleFileStr: The contents of an ICS file; usually a sched.com `.ics` export. Conforms to RFC 5545.
	///   - db: The connection to a database.
	///   - forumAuthor: If there are changes and `makeForumPosts` is TRUE, the user to use as the author of the relevant forum posts.
	///   - processDeletes: If TRUE (the default) events in the db but not in `scheduleFileStr` will be deleted from the db. Set to FALSE if you are applying a schedule
	///   	patch (e.g. a schedule file with a single new event).
	///   - makeForumPosts: Adds forum posts to each Event forum's thread announcing the changes that were made to the event.
	///
	func updateDatabaseFromICS(_ scheduleFileStr: String, on db: Database, forumAuthor: UserHeader,
			processDeletes: Bool = true, makeForumPosts: Bool = true) async throws {
		let updateEvents = try parse(scheduleFileStr)
		let officialCategory = try await Category.query(on: db).filter(\.$title, .custom("ILIKE"), "event%").first()
		let shadowCategory = try await Category.query(on: db).filter(\.$title, .custom("ILIKE"), "shadow%").first()
		// https://github.com/vapor/fluent-kit/issues/375
		// https://github.com/vapor/fluent-kit/pull/555
		let existingEvents = try await Event.query(on: db).withDeleted().with(\.$forum, withDeleted: true).all()
		try await db.transaction { database in
			// Convert to dictionaries, keyed by uid of the events
			let existingEventDict = Dictionary(existingEvents.map { ($0.uid, $0) }) { first, _ in first }
			let updateEventDict = Dictionary(updateEvents.map { ($0.uid, $0) }) { first, _ in first }
			let existingEventuids = Set(existingEvents.map { $0.uid })
			let notDeletedEventuids = Set(existingEvents.compactMap { $0.deletedAt == nil ? $0.uid : nil})
			let updateEventuids = Set(updateEvents.map { $0.uid })

			// Process deletes
			if processDeletes {
				let deleteduids = notDeletedEventuids.subtracting(updateEventuids)
				if makeForumPosts {
					for eventUID in deleteduids {
						if let existingEvent = existingEventDict[eventUID] {
							try await existingEvent.$forum.load(on: database)
							if let forum = existingEvent.forum {
								let newPost = try ForumPost(forum: forum, authorID: forumAuthor.userID,
										text: """
										Automatic Notification of Schedule Change: This event has been deleted from the \
										schedule. Apologies to those planning on attending.

										However, since this is an automatic announcement, it's possible the event got moved or \
										rescheduled and it only looks like a delete to me, your automatic server software. \
										Check the schedule.
										"""
								)
								try await newPost.save(on: database)
							}
						}
					}
				}
				try await Event.query(on: database).filter(\.$uid ~~ deleteduids).delete()
			}

			// Process creates
			let createduids = updateEventuids.subtracting(existingEventuids)
			for uid in createduids {
				if let event = updateEventDict[uid] {
					// Note that for creates, we make an initial forum post whether or not makeForumPosts is set.
					// makeForumPosts only concerns the "Schedule was changed" posts.
					if let officialCategory = officialCategory, let shadowCategory = shadowCategory {
						let forum = try SetInitialEventForums.buildEventForum(event,
								creatorID: forumAuthor.userID, shadowCategory: shadowCategory, officialCategory: officialCategory)
						try await forum.save(on: database)
						// Build an initial post in the forum with information about the event, and
						// a callout for posters to discuss the event.
						let postText = SetInitialEventForums.buildEventPostText(event)
						let infoPost = try ForumPost(forum: forum, authorID: forumAuthor.userID, text: postText)

						// Associate the forum with the event
						event.$forum.id = forum.id
						event.$forum.value = forum
						try await event.save(on: database)
						try await infoPost.save(on: database)
						if makeForumPosts {
							let newPost = try ForumPost(forum: forum, authorID: forumAuthor.userID,
									text: """
									Automatic Notification of Schedule Change: This event was just added to the \
									schedule.
									"""
							)
							try await newPost.save(on: database)
						}
					}
				}
			}

			// Process changes to existing events
			let updatedEvents = existingEventuids.intersection(updateEventuids)
			for uid in updatedEvents {
				if let existing = existingEventDict[uid], let updated = updateEventDict[uid] {
					var changes: Set<EventModification> = Set()
					if let deleteTime = existing.deletedAt, deleteTime < Date() {
						changes.insert(.undelete)
						// We can't actually do this. I thought about adding a conditional akin
						// to "if .undelete in changes" below, but that feels unneccesary.
						// existing.deletedAt = nil
						try await existing.restore(on: database)
					}
					if existing.startTime != updated.startTime {
						changes.insert(.startTime)
						existing.startTime = updated.startTime
						existing.endTime = updated.endTime
					}
					else if existing.endTime != updated.endTime {
						changes.insert(.endTime)
						existing.endTime = updated.endTime
					}
					if existing.location != updated.location {
						changes.insert(.location)
						existing.location = updated.location
					}
					if existing.title != updated.title || existing.info != updated.info
						|| existing.eventType != updated.eventType
					{
						changes.insert(.info)
						existing.title = updated.title
						existing.info = updated.info
						existing.eventType = updated.eventType
					}
					if !changes.isEmpty {
						try await existing.save(on: database)
						if let forum = existing.forum {
							// Un-delete the forum if it was deleted
							if (forum.deletedAt != nil) {
								try await forum.restore(on: database)
							}
							// Update title of event's linked forum
							let dateFormatter = DateFormatter()
							dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
							dateFormatter.dateFormat = "(E, HH:mm)"
							forum.title = dateFormatter.string(from: existing.startTime) + " \(existing.title)"
							try await forum.save(on: database)
							// Update first post of event's forum thread.
							if let firstPost = try await forum.$posts.query(on: database).sort(\.$id, .ascending)
								.first()
							{
								firstPost.text = SetInitialEventForums.buildEventPostText(existing)
								try await firstPost.save(on: database)
							}
							// Add post to forum detailing changes made to this event.
							if makeForumPosts {
								let newPost = try ForumPost(forum: forum, authorID: forumAuthor.userID,
										text: """
										Automatic Notification of Schedule Change: This event has changed.

										\(changes.contains(.undelete) ? "This event was canceled, but now is un-canceled.\r" : "")\
										\(changes.contains(.startTime) ? "Start Time changed\r" : "")\
										\(changes.contains(.endTime) ? "End Time changed\r" : "")\
										\(changes.contains(.location) ? "Location changed\r" : "")\
										\(changes.contains(.info) ? "Event info changed\r" : "")
										"""
								)
								try await newPost.save(on: database)
							}
						}
					}
				}
			}
			// Update the cached counts of how many forums are in each category
			let categories = try await Category.query(on: database).with(\.$forums).all()
			for cat in categories {
				cat.forumCount = Int32(cat.forums.count)
				try await cat.save(on: database)
			}
		}
		// End database transaction
	}

}

// Used internally to track the diffs involved in an calendar update.
private enum EventModification {
	case startTime
	case endTime
	case location
	case undelete
	case info
}

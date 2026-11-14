import Foundation
import Vapor

/// One session (event) from the sched.com `GET /api/session/export?format=json` API. Only the fields Swiftarr uses are decoded.
///
/// Sched returns most values as strings. `event_start` and `event_end` are wall-clock times in the Sched site's own timezone,
/// which isn't necessarily the ship's; `start_time_ts` is the absolute start time.
struct SchedSession: Codable {
	/// The session's unique ID. Matches the `UID` of the same event in the `.ics` export.
	var id: String
	/// "Y" if the session is active. Inactive sessions don't appear in the `.ics` export.
	var active: String
	var name: String
	/// "yyyy-MM-dd HH:mm" in the Sched site's timezone.
	var eventStart: String
	/// "yyyy-MM-dd HH:mm" in the Sched site's timezone.
	var eventEnd: String
	/// Unix timestamp of the session's start.
	var startTimeTS: Int
	/// The session's category, e.g. "Shadow Cruise". Same as the `.ics` CATEGORIES value.
	var eventType: String
	/// Sched's subtype. For JoCo this is the age rating, e.g. "Teens and Older".
	var eventSubtype: String?
	/// HTML-formatted description.
	var description: String?
	var venue: String?
	/// The venue's address, e.g. "Deck 3, Forward".
	var address: String?

	enum CodingKeys: String, CodingKey {
		case id, active, name, description, venue, address
		case eventStart = "event_start"
		case eventEnd = "event_end"
		case startTimeTS = "start_time_ts"
		case eventType = "event_type"
		case eventSubtype = "event_subtype"
	}
}

extension SchedSession {
	/// Decodes a sched.com `session/export` JSON response. Sched reports errors (such as a bad API key) as a plain-text
	/// `ERR: ...` body with a 200 status, so this checks for that before decoding.
	static func decodeSessions(from buffer: ByteBuffer) throws -> [SchedSession] {
		let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? ""
		let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("ERR:") {
			throw Abort(.badRequest, reason: "Sched API returned an error: \(trimmed.prefix(200))")
		}
		do {
			return try JSONDecoder().decode([SchedSession].self, from: Data(trimmed.utf8))
		}
		catch {
			throw Abort(.badRequest, reason: "Could not decode Sched session data: \(error)")
		}
	}

	/// Converts the session to an `Event`, matching what `EventParser` makes from the same session in the `.ics` export
	/// (plus the age rating, which the `.ics` export doesn't have).
	///
	/// - Returns: The `Event`, or nil if the session is inactive.
	func makeEvent() throws -> Event? {
		guard active == "Y" else {
			return nil
		}
		guard let wallStart = SchedSession.wallClockDate(eventStart), let wallEnd = SchedSession.wallClockDate(eventEnd) else {
			throw Abort(.badRequest, reason: "Could not parse start or end time of Sched session \(id).")
		}
		let startTime = Date(timeIntervalSince1970: TimeInterval(startTimeTS))
		let endTime = startTime.addingTimeInterval(wallEnd.timeIntervalSince(wallStart))
		var location = venue ?? ""
		if let address, !address.isEmpty {
			location += location.isEmpty ? address : ", \(address)"
		}
		let event = Event(startTime: startTime, endTime: endTime, title: name,
				description: SchedSession.plainText(fromHTML: description ?? ""), location: location,
				eventType: EventType(schedCategory: eventType), uid: id)
		event.ageRating = eventSubtype.flatMap { subtype in
			AgeRating.allCases.first { $0.label.caseInsensitiveCompare(subtype) == .orderedSame }
		}
		return event
	}

	/// Parses a Sched wall-clock time ("yyyy-MM-dd HH:mm", with or without seconds) as if it were GMT. Only useful for
	/// differences between two times, since the real timezone is the Sched site's.
	static func wallClockDate(_ value: String) -> Date? {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "GMT")
		for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"] {
			formatter.dateFormat = format
			if let date = formatter.date(from: value) {
				return date
			}
		}
		return nil
	}

	/// Converts a Sched HTML description to the plain text the `.ics` export has: tags removed and runs of whitespace collapsed
	/// to a single space. Non-breaking spaces are kept, as the `.ics` export keeps them.
	static func plainText(fromHTML html: String) -> String {
		let stripped = html.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
				.replacingOccurrences(of: "&amp;", with: "&")
		return stripped.replacingOccurrences(of: "[ \t\r\n]+", with: " ", options: .regularExpression)
				.trimmingCharacters(in: CharacterSet(charactersIn: " "))
	}
}

/// Talks to the sched.com API for this cruise's Sched site, using `Settings.schedBaseUrl` and `Settings.schedApiKey`.
struct SchedClient {
	let client: any Client

	/// Gets every session on the schedule from the Sched API.
	///
	/// Error messages never include the request URL, since it contains the API key.
	func exportSessions() async throws -> [SchedSession] {
		let apiKey = Settings.shared.schedApiKey
		guard !apiKey.isEmpty else {
			throw Abort(.internalServerError, reason: "SCHED_API_KEY is not set; can't access the Sched API.")
		}
		guard var components = URLComponents(string: Settings.shared.schedSessionExportURL) else {
			throw Abort(.internalServerError, reason: "SCHED_BASE_URL is not a valid URL.")
		}
		components.queryItems = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "format", value: "json")]
		guard let urlString = components.string else {
			throw Abort(.internalServerError, reason: "Could not build Sched API URL.")
		}
		let userAgent =
			"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
		let response = try await client.get(URI(string: urlString), headers: ["User-Agent": userAgent])
		guard response.status == .ok else {
			throw Abort(.badGateway, reason: "Sched API session export failed with response \(response.status.code).")
		}
		guard let body = response.body else {
			throw Abort(.badGateway, reason: "Sched API session export returned no data.")
		}
		return try SchedSession.decodeSessions(from: body)
	}
}

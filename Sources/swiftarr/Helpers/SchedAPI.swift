import Foundation
import SwiftSoup
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
	/// Decodes a sched.com `session/export` JSON response.
	static func decodeSessions(from buffer: ByteBuffer) throws -> [SchedSession] {
		return try SchedClient.decode([SchedSession].self, from: buffer)
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

/// One speaker from the sched.com `GET /api/role/export?role=speaker` API, when requested with the fields in
/// `SchedClient.speakerFields`. The Sched API has no pronouns, social media links, or years attended.
struct SchedSpeaker: Codable {
	var username: String?
	var name: String
	/// HTML-formatted bio.
	var about: String?
	/// The speaker's website. May be missing its scheme, e.g. "www.example.com".
	var url: String?
	/// Profile photo URL.
	var avatar: String?
	var company: String?
	var position: String?
	/// IDs of the speaker's sessions. Same as the `uid` of the matching `Event`. Null for speakers with no sessions.
	var sessions: [String]?
}

extension SchedSpeaker {
	/// Decodes a sched.com `role/export` JSON response.
	static func decodeSpeakers(from buffer: ByteBuffer) throws -> [SchedSpeaker] {
		return try SchedClient.decode([SchedSpeaker].self, from: buffer)
	}

	/// Converts the speaker to a `PerformerData` for bulk performer import. Fields the Sched API doesn't have are left nil.
	func makePerformerData() throws -> PerformerData {
		var result = PerformerData()
		result.header.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
		result.header.isOfficialPerformer = true
		if let avatar = SchedSpeaker.nonBlank(avatar) {
			result.header.photo = avatar.hasPrefix("//") ? "https:" + avatar : avatar
		}
		if let about = SchedSpeaker.nonBlank(about) {
			let body = try SwiftSoup.parseBodyFragment(about).body()
			result.bio = try SchedSpeaker.nonBlank(body.map { try markdown(fromHTML: $0) })
		}
		if let url = SchedSpeaker.nonBlank(url) {
			result.website = url.contains("://") ? url : "https://\(url)"
		}
		result.organization = SchedSpeaker.nonBlank(company)
		result.title = SchedSpeaker.nonBlank(position)
		result.scrapedEventRefs = (sessions ?? []).map { .init(uid: $0, title: "Sched session \($0)", startTime: nil) }
		return result
	}

	private static func nonBlank(_ value: String?) -> String? {
		guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
			return nil
		}
		return trimmed
	}
}

/// Talks to the sched.com API for this cruise's Sched site, using `Settings.schedBaseUrl` and `Settings.schedApiKey`.
///
/// Error messages never include request URLs, since they contain the API key.
struct SchedClient {
	let client: any Client

	/// The fields requested from `role/export` for speakers.
	static let speakerFields = "username,name,about,url,avatar,company,position,sessions"

	/// Gets every session on the schedule from the Sched API.
	func exportSessions() async throws -> [SchedSession] {
		return try SchedSession.decodeSessions(from: try await get("session/export"))
	}

	/// Gets every speaker from the Sched API.
	func exportSpeakers() async throws -> [SchedSpeaker] {
		let body = try await get("role/export", query: ["role": "speaker", "fields": SchedClient.speakerFields])
		return try SchedSpeaker.decodeSpeakers(from: body)
	}

	/// Decodes a sched.com API JSON response. Sched reports errors (such as a bad API key) as a plain-text
	/// `ERR: ...` body with a 200 status, so this checks for that before decoding.
	static func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T {
		let body = buffer.getString(at: buffer.readerIndex, length: buffer.readableBytes) ?? ""
		let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("ERR:") {
			throw Abort(.badRequest, reason: "Sched API returned an error: \(trimmed.prefix(200))")
		}
		do {
			return try JSONDecoder().decode(type, from: Data(trimmed.utf8))
		}
		catch {
			throw Abort(.badRequest, reason: "Could not decode Sched API data: \(error)")
		}
	}

	/// GETs `{schedBaseUrl}/api/{endpoint}` with the API key and JSON format, plus any other query parameters.
	private func get(_ endpoint: String, query: [String: String] = [:]) async throws -> ByteBuffer {
		let apiKey = Settings.shared.schedApiKey
		guard !apiKey.isEmpty else {
			throw Abort(.internalServerError, reason: "SCHED_API_KEY is not set; can't access the Sched API.")
		}
		guard let baseURL = URL(string: Settings.shared.schedBaseUrl),
				var components = URLComponents(url: baseURL.appendingPathComponent("api/\(endpoint)"), resolvingAgainstBaseURL: false)
		else {
			throw Abort(.internalServerError, reason: "SCHED_BASE_URL is not a valid URL.")
		}
		components.queryItems = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "format", value: "json")]
				+ query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
		guard let urlString = components.string else {
			throw Abort(.internalServerError, reason: "Could not build Sched API URL.")
		}
		let userAgent =
			"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
		let response = try await client.get(URI(string: urlString), headers: ["User-Agent": userAgent])
		guard response.status == .ok else {
			throw Abort(.badGateway, reason: "Sched API \(endpoint) failed with response \(response.status.code).")
		}
		guard let body = response.body else {
			throw Abort(.badGateway, reason: "Sched API \(endpoint) returned no data.")
		}
		return body
	}
}

import Vapor

/// The platform a `ClientApp` runs on. A client app may be available on several platforms.
/// Clients: Be sure to anticipate server values not listed here.
enum ClientAppPlatform: String, CaseIterable, Codable, Sendable {
	case web
	case ios
	case android
	/// Anything that isn't a website, iOS, or Android app (desktop apps, bots, etc.)
	case other

	/// `.label` returns a consumer-friendly display name.
	var label: String {
		switch self {
		case .web: return "Web"
		case .ios: return "iOS"
		case .android: return "Android"
		case .other: return "Other"
		}
	}

	/// For use by the URL-parameter layer. Lowercases the input and maps it to a case. Returns nil for "all" (meaning no filter)
	/// and for an absent/empty value; throws a 400 on unknown values.
	static func fromAPIString(_ str: String?) throws -> Self? {
		guard let lcString = str?.lowercased(), !lcString.isEmpty, lcString != "all" else {
			return nil
		}
		if let result = ClientAppPlatform(rawValue: lcString) {
			return result
		}
		throw Abort(.badRequest, reason: "Unknown platform parameter value.")
	}
}

import Vapor

/// The category of a `QuartermasterItem` — whether the user has the item to offer, or needs it.
enum QuartermasterCategory: String, CaseIterable, Codable, Sendable {
	/// The user has this item and is offering it to others.
	case have
	/// The user needs this item and is looking for someone who has it.
	case need

	/// `.label` returns a consumer-friendly display name.
	var label: String {
		switch self {
		case .have: return "Have"
		case .need: return "Need"
		}
	}

	/// For use by the URL-parameter layer. Lowercases the input and maps it to a case,
	/// throwing a 400 on unknown values.
	///
	/// URL parameters that take a category string should use this function.
	static func fromAPIString(_ str: String) throws -> Self {
		let lcString = str.lowercased()
		if let result = QuartermasterCategory(rawValue: lcString) {
			return result
		}
		throw Abort(.badRequest, reason: "Unknown category parameter value.")
	}
}

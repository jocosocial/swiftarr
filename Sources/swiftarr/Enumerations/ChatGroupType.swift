import Vapor

/// The type of `ChatGroup`.

public enum ChatGroupType: String, CaseIterable, Codable {
	/// A closed chat. Participants are set at creation and can't be changed. No location, start/end time, or capacity.
	case closed
	/// An open chat. Participants can be added/removed after creation *and your UI should make this clear*. No location, start/end time, or capacity.
	case open

	/// Some type of activity.
	case activity
	/// A dining LFG.
	case dining
	/// A gaming LFG.
	case gaming
	/// A general meetup.
	case meetup
	/// A music-related LFG.
	case music
	/// Some other type of LFG.
	case other
	/// A shore excursion LFG.
	case shore

	/// `.label` returns consumer-friendly case names.
	var label: String {
		switch self {
		case .activity: return "Activity"
		case .dining: return "Dining"
		case .gaming: return "Gaming"
		case .meetup: return "Meetup"
		case .music: return "Music"
		case .shore: return "Shore"
		case .closed: return "Private"
		case .open: return "Open"
		default: return "Other"
		}
	}

	/// For use by the UI layer. Returns whether this chatgroup should be labeled as a Seamail chat or as a LFG or some sort.
	var lfgLabel: String {
		switch self {
		case .closed, .open: return "Seamail"
		default: return "LFG"
		}
	}

	/// This gives us a bit more control than `init(rawValue:)`. Since the strings for ChatGroupTypes are part of the API (specifically, they're URL query values),
	/// they should be somewhat abstracted from internal representation.
	/// URL Parameters that take a ChatGroupType string should use this function to make a `ChatGroupType` from the input.
	static func fromAPIString(_ str: String) throws -> Self {
		let lcString = str.lowercased()
		if lcString == "private" {
			return .closed
		}
		if let result = ChatGroupType(rawValue: lcString) {
			return result
		}
		throw Abort(.badRequest, reason: "Unknown chatGroupType parameter value.")
	}
}

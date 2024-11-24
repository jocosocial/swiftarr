import Vapor

/// The type of `FriendlyFez`.

public enum FezType: String, CaseIterable, Codable {
	/// A closed chat. Participants are set at creation and can't be changed. No location, start/end time, or capacity. Not moderated.
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

	/// A personal calendar event. Has a location and start/end time, but no participants and no chat. Operates just like an event in your phone's Calendar app.
	case personalEvent
	/// A calendar event where the owner can add other users (like an open chat), but should display the event's location and time. No capacity.
	/// Unlike LFGs, there's no searching for events you don't belong to.
	case privateEvent
	
	/// The types that are LFGs, and a computed property to test it.
	static var lfgTypes: [FezType] {
		[.activity, .dining, .gaming, .meetup, .music, .other, .shore]
	}
	var isLFGType: Bool {
		FezType.lfgTypes.contains(self)
	}
	
	/// Types that are Seamails.
	static var seamailTypes: [FezType] {
		[.open, .closed]
	}
	var isSeamailType: Bool {
		FezType.lfgTypes.contains(self)
	}
	
	/// Types that are Private Events.
	static var privateEventTypes: [FezType] {
		[.privateEvent, .personalEvent]
	}
	var isPrivateEventType: Bool {
		FezType.privateEventTypes.contains(self)
	}
	
	/// `.label` returns consumer-friendly case names.
	var label: String {
		switch self {
		case .activity: return "Activity"
		case .dining: return "Dining"
		case .gaming: return "Gaming"
		case .meetup: return "Meetup"
		case .music: return "Music"
		case .shore: return "Shore"
		case .closed: return "Private Chat"
		case .open: return "Open Chat"
		case .privateEvent: return "Private Event"
		case .personalEvent: return "Personal Event"
		default: return "Other"
		}
	}

	/// For use by the UI layer. Returns whether this fez should be labeled as a Seamail chat or as an LFG or a Private Event.
	var lfgLabel: String {
		switch self {
		case .closed, .open: return "Seamail"
		case .privateEvent, .personalEvent: return "Private Event"
		default: return "LFG"
		}
	}

	/// This gives us a bit more control than `init(rawValue:)`. Since the strings for FezTypes are part of the API (specifically, they're URL query values),
	/// they should be somewhat abstracted from internal representation.
	/// URL Parameters that take a FezType string should use this function to make a `FezType` from the input.
	static func fromAPIString(_ str: String) throws -> Self {
		let lcString = str.lowercased()
		if lcString == "private" {
			return .closed
		}
		else if lcString == "privateevent" {
			return .privateEvent
		}
		else if lcString == "personalevent" {
			return .personalEvent
		}
		if let result = FezType(rawValue: lcString) {
			return result
		}
		throw Abort(.badRequest, reason: "Unknown fezType parameter value.")
	}
}

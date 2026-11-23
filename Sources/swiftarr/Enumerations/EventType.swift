/// The type of `Event`.

enum EventType: String, Codable {
	/// A gaming event.
	case gaming
	/// An official but uncategorized event.
	case general
	/// A live podcast event.
	case livePodcast
	/// A main concert event.
	case mainConcert
	/// An office hours event.
	case officeHours
	/// A party event.
	case party
	/// A q&a/panel event.
	case qaPanel
	/// A reading/performance event.
	case readingPerformance
	/// A shadow cruise event.
	case shadow
	/// A signing event.
	case signing
	/// A workshop event.
	case workshop
	/// A dining event.
	case dining

	/// `.label` returns consumer-friendly case names.
	var label: String {
		switch self {
		case .gaming: return "Gaming"
		case .general: return "Official"
		case .livePodcast: return "Live Podcast"
		case .mainConcert: return "Main Concert"
		case .officeHours: return "Office Hours"
		case .party: return "Party"
		case .qaPanel: return "Q&A/Panel"
		case .readingPerformance: return "Reading/Performance"
		case .shadow: return "Shadow Event"
		case .signing: return "Signing"
		case .workshop: return "Workshop"
		case .dining: return "Dining"
		}
	}
}

extension EventType {
	/// Maps a sched.com event category (the `.ics` `CATEGORIES` value, or the API's `event_type`) to an `EventType`.
	/// Matching is case-insensitive; unrecognized categories become `.general`.
	init(schedCategory: String) {
		switch schedCategory.trimmingCharacters(in: .whitespaces).uppercased() {
		case "GAMING":
			self = .gaming
		case "LIVE PODCAST":
			self = .livePodcast
		case "MAIN CONCERT":
			self = .mainConcert
		case "OFFICE HOURS":
			self = .officeHours
		case "PARTY":
			self = .party
		case "Q&A / PANEL", "Q&A", "PANEL":						// "Q&A" and "PANEL" are not canonical
			self = .qaPanel
		case "READING / PERFORMANCE", "READING", "PERFORMANCE": // "READING" and "PERFORMANCE" are not canonical
			self = .readingPerformance
		case "SHADOW CRUISE":
			self = .shadow
		case "SIGNING":
			self = .signing
		case "WORKSHOP":
			self = .workshop
		case "DINING":
			self = .dining
		default:
			self = .general
		}
	}
}

/// The type of `Event`.

public enum EventType: String, Codable {
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
		}
	}
}

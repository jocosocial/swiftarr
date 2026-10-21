/// The age appropriateness rating of an `Event`, as designated by the event's organizer.
/// There appears to be no Sched API to configure or read these so they
/// were determined based on the results of the 2026 sailing API values.
/// Additionally, AgeRating does NOT come from the ICS dump from Sched.
enum AgeRating: String, Codable, CaseIterable {
	/// Suitable for everyone.
	case allAges
	/// Suitable for teens and older.
	case teensAndOlder
	/// Adults only.
	case adultsOnly
	/// Specifically for kids.
	case kidsOnly

	/// `.label` returns consumer-friendly case names.
	var label: String {
		switch self {
		case .allAges: return "All Ages"
		case .teensAndOlder: return "Teens and Older"
		case .adultsOnly: return "Adults Only"
		case .kidsOnly: return "Specifically for Kids"
		}
	}
}

import Vapor

/// Optional indicator of dinner seating team.

public enum DinnerTeam: String, CaseIterable, Codable {
	/// Red Team
	case red
	/// Gold Team
	case gold
	/// SRO
	case sro

	/// `.label` returns consumer-friendly case names.
	var label: String {
		switch self {
		case .red: return "Red Team"
        case .gold: return "Gold Team"
        case .sro: return "Club SRO"
		}
	}
}
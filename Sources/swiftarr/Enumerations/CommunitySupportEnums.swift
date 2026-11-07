import Vapor

/// Where a Community Support report stands. Stored as a plain string column, so the vocabulary is cheap to change.
enum CommunitySupportReportStatus: String, Codable, CaseIterable, Sendable {
	/// Filed, and nobody has looked at it yet.
	case new
	/// Someone on the team is working on it.
	case inProgress
	/// Dealt with.
	case resolved
	/// Filed for the team's information only; the reporter didn't ask for follow-up.
	case infoOnly

	/// Consumer-friendly name.
	var label: String {
		switch self {
		case .new: return "New"
		case .inProgress: return "In Progress"
		case .resolved: return "Resolved"
		case .infoOnly: return "Info Only"
		}
	}

	/// Open reports are the ones that count toward the badge on the Community Support home page entry.
	var isOpen: Bool { self == .new || self == .inProgress }
}

/// What the reporter wants done with their report.
enum CommunitySupportReportIntent: String, Codable, CaseIterable, Sendable {
	/// "I just want you to know about this."
	case infoOnly
	/// "Please follow up."
	case followUp

	/// Consumer-friendly name.
	var label: String {
		switch self {
		case .infoOnly: return "Information only"
		case .followUp: return "Please follow up"
		}
	}
}

/// The kinds of entries in the Community Support action log. Entries are append-only, and record changes--not views.
enum CommunitySupportActionType: String, Codable, CaseIterable, Sendable {
	case reportCreated
	case statusChanged
	case discussionStarted
	case reportsExported

	/// Consumer-friendly name, suitable for showing directly in a client.
	var label: String {
		switch self {
		case .reportCreated: return "Report created"
		case .statusChanged: return "Status changed"
		case .discussionStarted: return "Discussion started"
		case .reportsExported: return "Reports exported"
		}
	}
}

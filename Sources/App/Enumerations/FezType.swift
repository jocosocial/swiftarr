import FluentPostgreSQL

/// The type of `FriendlyFez`.

enum FezType: String, CaseIterable, PostgreSQLRawEnum {
    /// Some type of activity.
    case activity
    /// A dining LFG.
    case dining
    /// A gaming LFG.
    case gaming
    /// A general meetup.
    case meeetup
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
            case .meeetup: return "Meetup"
            case .music: return "Music"
            case .shore: return "Shore"
            default: return "Other"
        }
    }
}

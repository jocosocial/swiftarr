import FluentPostgreSQL

/// The type of `Barrel`.

enum BarrelType: String, PostgreSQLRawEnum, Comparable {
    /// A user's barrel of bookmarked posts.
    case bookmarkedPost
    /// A user's barrel of bookmarked twarrts.
    case bookmarkedTwarrt
    /// A `FriendlyFez` event barrel.
    case friendlyFez
    /// A user's barrel of alert keywords.
    case keywordAlert
    /// A user's barrel of muting keywords.
    case keywordMute
    /// A generic barrel of seamonkeys.
    case seamonkey
    /// A user's barrel of tagged events.
    case taggedEvent
    /// A user's barrel of tagged forums.
    case taggedForum
    /// A user's barrel of blocked seamonkeys.
    case userBlock
    /// A user's barrel of muted seamonkeys.
    case userMute
    /// A generic barrel of strings.
    case userWords
    
    // MARK: Comparable Conformance
    
    /// Provide case values for the sorting order.
    private var sortOrder: Int {
        switch self {
            case .userBlock: return 0
            case .userMute: return 1
            case .keywordAlert: return 2
            case .keywordMute: return 3
            case .userWords: return 10
            default: return 20
        }
    }
    
    /// Required `Equatable`.
    static func ==(lhs: BarrelType, rhs: BarrelType) -> Bool {
        return lhs.sortOrder == rhs.sortOrder
    }
    
    /// Required `Comparable`.
    static func <(lhs: BarrelType, rhs: BarrelType) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }
}

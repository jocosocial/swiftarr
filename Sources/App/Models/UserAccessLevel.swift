import FluentPostgreSQL

/// All API endpoints are protected by a mimimum user access level.
/// This `enum` structure is ordered and should *never* be modified when
/// working with stored production `User` data – bad things will happen.

enum UserAccessLevel: UInt8, PostgreSQLRawEnum {
    /// A user account that has not yet been activated. (read-only, limited)
    case unverified
    /// A user account that has been banned. (read-only, limited)
    case banned
    /// A `.verified` user account that has triggered Moderator review. (read-only)
    case quarantined
    /// A user account that has been activated for full read-write access.
    case verified
    /// An account whose owner is part of the Moderator Team.
    case moderator
    /// An account officially associated with Management, has access to all `.moderator`
    /// and a subset of `.admin` functions (the non-destructive ones).
    case tho
    /// An Administrator account, unrestricted access.
    case admin
}


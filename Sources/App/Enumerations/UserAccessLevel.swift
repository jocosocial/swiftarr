import Vapor
import Fluent

/// All API endpoints are protected by a minimum user access level.
/// This `enum` structure is ordered and should *never* be modified when
/// working with stored production `User` data – bad things will happen.

enum UserAccessLevel: UInt8, Codable {
    /// A user account that has not yet been activated. [read-only, limited]
    case unverified
    /// A user account that has been banned. [read-only, limited]
    case banned
    /// A `.verified` user account that has triggered Moderator review. [read-only]
    case quarantined
    /// A user account that has been activated for full read-write access.
    case verified
    /// A special class of account for registered API clients. [see `ClientController`]
    case client
    /// An account whose owner is part of the Moderator Team.
    case moderator
    /// An account officially associated with Management, has access to all `.moderator`
    /// and a subset of `.admin` functions (the non-destructive ones).
    case tho
    /// An Administrator account, unrestricted access.
    case admin
    
    /// Ensures that the access level of self grants at least the access level given in `level`.
    /// That is, UserAccessLevel.admin.hasAccess(.verified) returns true, while moderator.hasAccess(.admin) returns false.
    func hasAccess(_ level: UserAccessLevel) -> Bool {
    	return self.rawValue >= level.rawValue
    }
}

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
    /// Although this currently uses > to test, the method could be expanded to non-hierarchy access types--and we may need to,
    /// as `Client`s can make calls that `Moderator`s cannot, and vice versa.
    func hasAccess(_ level: UserAccessLevel) -> Bool {
    	return self.rawValue >= level.rawValue
    }
    
// MARK: Capability Queries

    /// Returns TRUE iff this user is allowed to post their own content and edit or delete content they created..
    func canCreateContent() -> Bool {
    	return self.rawValue >= UserAccessLevel.verified.rawValue
    }
    
    /// Returns TRUE if this user is allowed to moderate others' content. This includes editing text, removing images, and 
    /// deleting posts. This capability does not include the ability to moderate users themselves.
    func canEditOthersContent() -> Bool {
    	return self.rawValue >= UserAccessLevel.moderator.rawValue
    }
    
    /// Returns TRUE if this user can change the access level of other users. The access level of Client users cannot be changed,
    /// and only `admin` level users can set other users' access level to equal their own. For example `moderator` users can
    /// change user levels FROM any of [unverified, banned, quarantined, verified] TO any of [unverified, banned, quarantined, verified].
    func canModerateUsers() -> Bool {
    	return self.rawValue >= UserAccessLevel.moderator.rawValue
    }
    
    /// Returns TRUE iff the user is allowed to create forum threads in restricted forums.
    func canCreateRestrictedForums() -> Bool {
    	return hasAccess(.moderator)
    }
}

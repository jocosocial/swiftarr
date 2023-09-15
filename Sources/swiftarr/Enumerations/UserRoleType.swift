import Vapor

/// UserRole is a simple role-based access control mechanism mostly used for elevating 'verified' users to have specific extra access.
/// UserRole is therefore an access model that works in addition to Twitarr's priority access model (see `UserLevel`). With UserLevlels,
/// each increasing access level is a superset of access provided by the previous level. Roles allow multiple users to each extend the `verified` permissions
/// without one of the extensions always being a superset of the other.
///
/// This implementation is not a full RBAC. Instead:
/// 	- Each user may have multiple roles
/// 	- A db object or API call that requires a role to use must test that the requesting user has the proper role.
/// 	- Roles implicitly define permissions; there is no facility to add/remove permissions from roles.
/// 	- There is no role hierarchy. An operation X that allows X_User and X_Manager to access it must test for both roles explicitly.
/// 	- Ideally, a DB object that requires a role to access should only require one role be stored for it.
/// 	- In general, a nil value for a DB object's `requiredRole` should mean no special role is required to access it.
/// 	- Moderators and above should usually have access to role-protected content; without us having to add a bunch of roles to each moderator user.
public enum UserRoleType: String, CaseIterable, Codable, Sendable {
	/// KaraokeManagers have the ability to log song performances in the Karaoke Bar.
	case karaokemanager
	/// Shutternaut Managers can add and remove members from the Shutternauts group. Note: Because of the "no hierarchy" rule, managers are NOT automatically Shutternauts.
	case shutternautmanager
	/// Shutternauts can view, post, and create threads in the Shutternauts forum category.
	case shutternaut

	/// `.label` returns consumer-friendly case names.
	var label: String {
		switch self {
		case .karaokemanager: return "Karaoke Manager"
		case .shutternautmanager: return "Shutternaut Manager"
		case .shutternaut: return "Shutternaut"
		}
	}

	/// This gives us a bit more control than `init(rawValue:)`. Since the strings for AccessControl are part of the API (specifically, they're URL query values),
	/// they should be somewhat abstracted from internal representation. This fn provides lazy abstraction, making it easy for API strings to  get re-mapped to enum values, in the future.
	/// URL Parameters that take an UserRoleType string should use this function to make a `AccessControl` from the input.
	/// I am not overriding `init(rawValue:)` both so that I can call through to that initializer, and because devs have specific ideas about how init(rawValue:) works.
	init(fromAPIString str: String) throws {
		guard let result = UserRoleType(rawValue: str.lowercased()) else {
			throw Abort(.badRequest, reason: "Unknown UserRoleType parameter value.")
		}
		self = result
	}

	/// A failable initializer for turning an optional string into a UserRoleType, if the string equals one of the enum cases.
	init?(fromString str: String?) {
		guard let str = str, let result = UserRoleType(rawValue: str.lowercased()) else {
			return nil
		}
		self = result
	}
}

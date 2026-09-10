import Vapor

/// The visibility of a `FriendlyFez`, controlling whether non-members/non-moderators can view or join it.
enum FezVisibility: String, CaseIterable, Codable {
	/// The default for Seamails (`.open`/`.closed`) and `.personalEvent`. A non-member, non-moderator
	/// GET on the fez 403s.
	case `private`
	/// The default for all LFG types. Non-members can view the fez (but not `.members`) and can search for it.
	case `public`
	/// Only valid on `.privateEvent`. Non-members can view the fez (but not `.members`) via a direct link,
	/// and can self-join, but the event is never listed/searchable.
	case unlisted

	/// The visibility a fez of the given type gets unless explicitly overridden.
	static func defaultVisibility(for fezType: FezType) -> FezVisibility {
		fezType.isLFGType ? .public : .private
	}
}

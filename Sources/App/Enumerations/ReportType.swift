
/// The type of entity being reported in a `Report`.

enum ReportType: String, Codable {
    /// An entire `Forum`.
    case forum
    /// An individual `ForumPost`.
    case forumPost
    /// An individual `Twarrt`.
    case twarrt
    /// A `User`, although it specifically refers to the user's profile fields.
    case user
    /// a `FezPost`
    case fezPost
}

/// Moderation status of a piece of reportable content. 
enum ContentModerationStatus: String, Codable {
	/// The initial state for all content.
	case normal
	/// Auto-quarantine gets set automatically when a certain number of users have reported on content in the 'normal' state. Auto-quarantined content is not visible to non-mods,
	/// instead showing a 'this post/forum quarantined' message.
	case autoQuarantined
	/// Mods can quarantine content to make it hidden from normal users but still in place, visible to mods. Mods may do this as an interim measure while determining a more
	/// permanent status.
	case quarantined
	/// Mods can set this status on content, usually switching from one of the quarantine statuses. Reviewed means the content is deemed 'ok' by mods and is immune to auto-quarantine.
	/// A nom-mod user editing the content will remove modReviewed status (goes to normal).
	case modReviewed
	/// Mods can set this status on content. Locked content is not modifiable by non-mods, but has normal visibility. Locked content is immune to auto-quarantine.
	case locked
}

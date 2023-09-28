import Fluent
import Foundation
import Vapor

/// 	A FriendlyGroup (Group for short) is a multi person chat facilty.
///
/// 	Broadly speaking, Groups may be open or closed, chosen at creation time.
/// 	- Open groups generally have a publicly stated purpose, and may be for an event at a specific time and place. Open groups allow users to join and leave
/// 	the group at any time. Open groups may have posts with images, and can get moderated by mods. There is a search API for finding and joining public groups.
/// 	- Closed groups have a membership set at creation time (by the group creator), and cannot have images in posts. Closed groups are very similar to V2's Seamail facility.
///
/// 	Considered but not yet built are semi-open groups:
///
/// 	- A semi-open group would allow users to join after creation, but either the creator would have to invite new members or perhaps users could join via an invite link.
/// 	Semi-open groups would not be searchable, would not be moderated, could not have images. Importantly, semi-open groups would indicate their semi-open state
/// 	to their members, so that current members would know the membership list could change. New members to a semi-open group would be able to read all past messages.
///
/// 	- See Also: [GroupData](GroupData) the DTO for returning basic data on Groups.
/// 	- See Also: [GroupContentData](GroupContentData) the DTO for creating or editing Groups.
/// 	- See Also: [CreateFriendlyGroupSchema](CreateFriendlyGroupSchema) the Migration for creating the Group table in the database.
final class FriendlyGroup: Model, Searchable {
	static let schema = "friendlygroup"

	// MARK: Properties
	/// Unique ID for this Group.
	@ID(key: .id) var id: UUID?

	/// The type of group; what its purpose is..
	@Field(key: "groupType") var groupType: GroupType

	/// The title of the group.
	@Field(key: "title") var title: String

	/// A longer description of what the group is about? Seems like this info could just go in the first post.
	@Field(key: "info") var info: String

	/// Where the group is happening.
	@OptionalField(key: "location") var location: String?

	/// Moderators can set several statuses on groupPosts that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	/// Start time for the group. Only meaningful for public groups that are organizing an activity.
	@OptionalField(key: "start_time") var startTime: Date?

	/// End  time for the group.
	@OptionalField(key: "end_time") var endTime: Date?

	/// A minimum headcount needed for the group to happen. Clients may want to highlight groups that are below min capacity in order to
	/// encourage users to join.
	@Field(key: "min_capacity") var minCapacity: Int

	/// The max numbert of participants. The first `max_capacity` members of `participantArray`are the current participants; the rest
	/// of the array is the waitlist.
	@Field(key: "max_capacity") var maxCapacity: Int

	/// The number of posts in the group. Should be equal to groupPosts.count. Value is cached here for quick access. When returning this value to a user,
	/// we subtrract the `hiddenCount` from the user's `GroupParticipant` structure. Thus, different users could see differnt counts for the same group.
	@Field(key: "post_count") var postCount: Int

	// TRUE if the group has been cancelled. Currently only the owner may cancel a group. We may implement
	// code to auto-cancel groups that don't meet min-capacity a few minutes before start time. Cancelled
	// groups should probably only be shown to participants, and be left out of searches.
	@Field(key: "cancelled") var cancelled: Bool

	/// An ordered list of participants in the group. Newly joined members are appended to the array, meaning this array stays sorted by join time..
	@Field(key: "participant_array") var participantArray: [UUID]

	// MARK: Relationships
	/// The creator of the group.
	@Parent(key: "owner") var owner: User

	/// The participants in the group. The pivot `GroupParticipant` also maintains the read count for each participant.
	@Siblings(through: GroupParticipant.self, from: \.$group, to: \.$user) var participants: [User]

	/// The posts participants have made in the group.
	@Children(for: \.$group) var groupPosts: [GroupPost]

	/// The child `FriendlyGroupEdit` accountability records of the group.
	@Children(for: \.$group) var edits: [FriendlyGroupEdit]

	// MARK: Record-keeping
	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Initialization
	// Used by Fluent
	init() {}

	/// Initializes a new FriendlyGroup.
	///
	/// - Parameters:
	///   - owner: The ID of the owning entity.
	///   - groupType: The type of group being created.
	///   - title: The title of the Group.
	///   - location: Where the Group is being held.
	///   - startTime: When participants should arrive.
	///   - endTime: Estimated time the group will complete.
	///   - minCapacity: How many people are needed make a quorum.
	///   - maxCapactiy: The max # of people who can attend. Users who join past this number are waitlisted.
	init(
		owner: UUID,
		groupType: GroupType,
		title: String = "",
		info: String = "",
		location: String?,
		startTime: Date?,
		endTime: Date?,
		minCapacity: Int = 0,
		maxCapacity: Int = 0
	) {
		self.$owner.id = owner
		self.groupType = groupType
		self.title = title
		self.info = info
		self.location = location
		self.moderationStatus = .normal
		self.startTime = startTime
		self.endTime = endTime
		self.minCapacity = minCapacity
		self.maxCapacity = maxCapacity
		self.postCount = 0
		self.cancelled = false
	}

	/// Initializes a closed FriendlyGroup, also known as a Chat session.
	init(owner: UUID) {
		self.$owner.id = owner
		self.groupType = .closed
		self.title = ""
		self.info = ""
		self.location = nil
		self.moderationStatus = .normal
		self.minCapacity = 0
		self.maxCapacity = 0
		self.postCount = 0
		self.cancelled = false
	}
}

struct CreateFriendlyGroupSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("friendlygroup")
			.id()
			.field("groupType", .string, .required)
			.field("title", .string, .required)
			.field("info", .string, .required)
			.field("location", .string)
			.field("mod_status", modStatusEnum, .required)
			.field("start_time", .datetime)
			.field("end_time", .datetime)
			.field("min_capacity", .int, .required)
			.field("max_capacity", .int, .required)
			.field("post_count", .int, .required)
			.field("cancelled", .bool, .required)
			.field("participant_array", .array(of: .uuid), .required)
			.field("owner", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("friendlygroup").delete()
	}
}

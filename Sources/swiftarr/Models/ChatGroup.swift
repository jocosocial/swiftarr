import Fluent
import Foundation
import Vapor

/// 	A ChatGroup (ChatGroup for short) is a multi person chat facilty.
///
/// 	Broadly speaking, ChatGroups may be open or closed, chosen at creation time.
/// 	- Open chatgroups generally have a publicly stated purpose, and may be for an event at a specific time and place. Open chatgroups allow users to join and leave
/// 	the chatgroup at any time. Open chatgroups may have posts with images, and can get moderated by mods. There is a search API for finding and joining public chatgroups.
/// 	- Closed chatgroups have a membership set at creation time (by the chatgroup creator), and cannot have images in posts. Closed chatgroups are very similar to V2's Seamail facility.
///
/// 	Considered but not yet built are semi-open chatgroups:
///
/// 	- A semi-open chatgroup would allow users to join after creation, but either the creator would have to invite new members or perhaps users could join via an invite link.
/// 	Semi-open chatgroups would not be searchable, would not be moderated, could not have images. Importantly, semi-open chatgroups would indicate their semi-open state
/// 	to their members, so that current members would know the membership list could change. New members to a semi-open chatgroup would be able to read all past messages.
///
/// 	- See Also: [ChatGroupData](ChatGroupData) the DTO for returning basic data on ChatGroups.
/// 	- See Also: [ChatGroupContentData](ChatGroupContentData) the DTO for creating or editing ChatGroups.
/// 	- See Also: [CreatechatgroupSchema](CreatechatgroupSchema) the Migration for creating the ChatGroup table in the database.
final class ChatGroup: Model, Searchable {
	static let schema = "chatgroup"

	// MARK: Properties
	/// Unique ID for this ChatGroup.
	@ID(key: .id) var id: UUID?

	/// The type of chatgroup; what its purpose is..
	@Field(key: "chatGroupType") var chatGroupType: ChatGroupType

	/// The title of the chatgroup.
	@Field(key: "title") var title: String

	/// A longer description of what the chatgroup is about? Seems like this info could just go in the first post.
	@Field(key: "info") var info: String

	/// Where the chatgroup is happening.
	@OptionalField(key: "location") var location: String?

	/// Moderators can set several statuses on ChatGroupPosts that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	/// Start time for the chatgroup. Only meaningful for public chatgroups that are organizing an activity.
	@OptionalField(key: "start_time") var startTime: Date?

	/// End  time for the chatgroup.
	@OptionalField(key: "end_time") var endTime: Date?

	/// A minimum headcount needed for the chatgroup to happen. Clients may want to highlight chatgroups that are below min capacity in order to
	/// encourage users to join.
	@Field(key: "min_capacity") var minCapacity: Int

	/// The max numbert of participants. The first `max_capacity` members of `participantArray`are the current participants; the rest
	/// of the array is the waitlist.
	@Field(key: "max_capacity") var maxCapacity: Int

	/// The number of posts in the chatgroup. Should be equal to ChatGroupPosts.count. Value is cached here for quick access. When returning this value to a user,
	/// we subtrract the `hiddenCount` from the user's `ChatGroupParticipant` structure. Thus, different users could see differnt counts for the same chatgroup.
	@Field(key: "post_count") var postCount: Int

	// TRUE if the chatgroup has been cancelled. Currently only the owner may cancel a chatgroup. We may implement
	// code to auto-cancel chatgroups that don't meet min-capacity a few minutes before start time. Cancelled
	// chatgroups should probably only be shown to participants, and be left out of searches.
	@Field(key: "cancelled") var cancelled: Bool

	/// An ordered list of participants in the chatgroup. Newly joined members are appended to the array, meaning this array stays sorted by join time..
	@Field(key: "participant_array") var participantArray: [UUID]

	// MARK: Relationships
	/// The creator of the chatgroup.
	@Parent(key: "owner") var owner: User

	/// The participants in the chatgroup. The pivot `ChatGroupParticipant` also maintains the read count for each participant.
	@Siblings(through: ChatGroupParticipant.self, from: \.$chatGroup, to: \.$user) var participants: [User]

	/// The posts participants have made in the chatgroup.
	@Children(for: \.$chatGroup) var ChatGroupPosts: [ChatGroupPost]

	/// The child `chatgroupEdit` accountability records of the chatgroup.
	@Children(for: \.$chatGroup) var edits: [chatgroupEdit]

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

	/// Initializes a new ChatGroup.
	///
	/// - Parameters:
	///   - owner: The ID of the owning entity.
	///   - chatGroupType: The type of chatgroup being created.
	///   - title: The title of the ChatGroup.
	///   - location: Where the ChatGroup is being held.
	///   - startTime: When participants should arrive.
	///   - endTime: Estimated time the chatgroup will complete.
	///   - minCapacity: How many people are needed make a quorum.
	///   - maxCapactiy: The max # of people who can attend. Users who join past this number are waitlisted.
	init(
		owner: UUID,
		chatGroupType: ChatGroupType,
		title: String = "",
		info: String = "",
		location: String?,
		startTime: Date?,
		endTime: Date?,
		minCapacity: Int = 0,
		maxCapacity: Int = 0
	) {
		self.$owner.id = owner
		self.chatGroupType = chatGroupType
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

	/// Initializes a closed ChatGroup, also known as a Chat session.
	init(owner: UUID) {
		self.$owner.id = owner
		self.chatGroupType = .closed
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

struct CreatechatgroupSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("chatgroup")
			.id()
			.field("chatGroupType", .string, .required)
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
		try await database.schema("chatgroup").delete()
	}
}

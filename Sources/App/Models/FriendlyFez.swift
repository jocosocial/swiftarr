import Vapor
import Foundation
import Fluent

final class FriendlyFez: Model {
	static let schema = "friendlyfez"
	
// MARK: Properties
	/// Unique ID for this Fez.
	@ID(key: .id) var id: UUID?

	/// The type of fez; what its purpose is..
	@Field(key: "fezType") var fezType: FezType

	/// The title of the fez.
	@Field(key: "title") var title: String

	/// A longer description of what the fez is about? Seems like this info could just go in the first post.
	@Field(key: "info") var info: String

	/// Where the fez is happening.
	@Field(key: "location") var location: String?
	
    /// Moderators can set several statuses on fezPosts that modify editability and visibility.
    @Enum(key: "mod_status") var moderationStatus: ContentModerationStatus
        
	/// Start time for the fez. Only meaningful for public fezzes that are organizing an activity.
	@Field(key: "start_time") var startTime: Date?

	/// End  time for the fez.
	@Field(key: "end_time") var endTime: Date?
	
	/// A minimum headcount needed for the fez to happen. Clients may want to highlight fezzes that are below min capacity in order to 
	/// encourage users to join.
	@Field(key: "min_capacity") var minCapacity: Int
	
	/// The max numbert of participants. The first `max_capacity` members of `participantArray`are the current participants; the rest
	/// of the array is the waitlist.
	@Field(key: "max_capacity") var maxCapacity: Int
	
	/// The number of posts in the fez. Should be equal to fezPosts.count. Value is cached here for quick access. When returning this value to a user,
	/// we subtrract the `hiddenCount` from the user's `FezParticipant` structure. Thus, different users could see differnt counts for the same fez.
	@Field(key: "post_count") var postCount: Int

	// TRUE if the fez has been cancelled. Currently only the owner may cancel a fez. We may implement
	// code to auto-cancel fezzes that don't meet min-capacity a few minutes before start time. Cancelled
	// fezzes should probably only be shown to participants, and be left out of searches.
	@Field(key: "cancelled") var cancelled: Bool
  
    /// An ordered list of participants in the fez. Newly joined members are appended to the array, meaning this array stays sorted by join time.. 
    @Field(key: "participant_array") var participantArray: [UUID]

// MARK: Relationships
    /// The creator of the fez.
    @Parent(key: "owner") var owner: User
    
	/// The participants in the fez. The pivot `FezParticipant` also maintains the read count for each participant.
	@Siblings(through: FezParticipant.self, from: \.$fez, to: \.$user) var participants: [User]
	
	/// The posts participants have made in the fez.
	@Children(for: \.$fez) var fezPosts: [FezPost]	
	
    /// The child `FriendlyFezEdit` accountability records of the fez.
    @Children(for: \.$fez) var edits: [FriendlyFezEdit]

// MARK: Record-keeping
    /// Timestamp of the model's creation, set automatically.
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

// MARK: Initialization
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new FriendlyFez.
    ///
    /// - Parameters:
    ///   - owner: The ID of the owning entity.
    ///   - barrelType: The type of information the barrel holds.
    ///   - name: A name for the barrel.
    ///   - modelUUIDs: The IDs of UUID-model barrel contents.
    ///   - userInfo: A dictionary that holds string-type barrel contents.
    init(
        owner: User,
        fezType: FezType,
        title: String = "",
		info: String = "",
		location: String?,
		startTime: Date?,
		endTime: Date?,
		minCapacity: Int = 0,
		maxCapacity: Int
    ) throws {
		self.$owner.id = try owner.requireID()
        self.$owner.value = owner
        self.fezType = fezType
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
        
//		self.$participants.attach(to: owner, on:)
    }
    
    /// Initializes a closed FriendlyFez, also known as a Chat session.
    init(owner: User) throws {
		self.$owner.id = try owner.requireID()
        self.$owner.value = owner
        self.fezType = .closed
        self.title = ""
        self.info = ""
        self.location = nil
        self.moderationStatus = .normal
        self.minCapacity = 0
        self.maxCapacity = 0
        self.postCount = 0
        self.cancelled = false
	}

	static func createClosedFez( owner: User, participants: [User], on db: Database) throws -> EventLoopFuture<FriendlyFez> {
		let newFez = try FriendlyFez(owner: owner)
		var futures: [EventLoopFuture<Void>] = []
		for participant in participants {
			futures.append(newFez.$participants.attach(participant, on: db))
		}
		return futures.flatten(on: db.eventLoop).transform(to: newFez)
	}
}


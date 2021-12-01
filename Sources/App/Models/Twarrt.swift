import Vapor
import Fluent


/**
	An individual post in the Twitarr stream. Posts must contain text content, and may also contain images.
	
	Twarrts are content that can be quarantined or locked by moderators. A quarantined twarrt will have its contents replaced with a quarantine message,
	and will not have any images. A locked twarrt can only be modified by moderators. When edited, twarrts create edit records showing previous state
	for moderation purposes.
	
	V2 of Twitarr (and, actual Twitter) have tweet replies that work as a directed acyclic graph. Any tweet can be created as a reply to an existing tweet,
	a tweet can have multiple direct reply tweets, and a tweet can be both a reply to another tweet and the target of other replies. V3 doesn't work that way.
	A new twarrt replying to a twarrt not already in a Reply Group creates a Reply Group, and **both** the replied--to and reply twarrt have their `replyGroup` 
	set to the ID of the replied-to twarrt. A reply to a twarrt already in a Reply Group gets added to the Reply Group. 
	
	This means that any twarrt that has a non-null replyGroup has a thread can can be retrieved. It also means that replies are one level deep--a reply to a reply
	is not considered differernt than a 2 replies to a single twarrt.
	
	- See Also: [TwarrtData](TwarrtData) the DTO for returning basic data on Twarrts.
	- See Also: [TwarrtDetailData](TwarrtDetailData) the DTO for returning basic data on Twarrts.
	- See Also: [PostData](PostData) the DTO for creating or editing Twarrts.
	- See Also: [CreateTwarrtSchema](CreateTwarrtSchema) the Migration for creating the Twarrts table in the database.
*/
final class Twarrt: Model {
	static let schema = "twarrts"
	
	// MARK: Properties
    
    /// The twarrt's ID.
    @ID(custom: "id") var id: Int?
    
    /// The text content of the twarrt.
    @Field(key: "text") var text: String
    
    /// The filenames of any images for the post.
    @OptionalField(key: "images") var images: [String]?
    
    /// Moderators can set several statuses on twarrts that modify editability and visibility.
    @Enum(key: "mod_status") var moderationStatus: ContentModerationStatus
        
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
	// MARK: Relations
	
    /// The twarrt's author.
    @Parent(key: "author") var author: User

    /// When a twarrt is created as a reply to another twarrt, both twarrts get their `replyGroup` set to the ID of the replied-to twarrt.
    /// When a reply is created and the replied-to twarrt is already in a reply group, the new reply joins the existing reply group.
    @OptionalParent(key: "reply_group") var replyGroup: Twarrt?
    
    /// The child `TwarrtEdit` accountability records of the twarrt.
	@Children(for: \.$twarrt) var edits: [TwarrtEdit]
	
    /// The sibling `User`s who have "liked" the twarrt.
	@Siblings(through: TwarrtLikes.self, from: \.$twarrt, to: \.$user) var likes: [User]
	
	// MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new Twarrt.
    ///
    /// - Parameters:
    ///   - author: The author of the twarrt.
    ///   - text: The text content of the twarrt.
    ///   - image: The filename of any image content of the twarrt.
    ///   - replyTo: The twarrt being replied to, if any.
    init(authorID: UUID, text: String, images: [String]? = nil, replyTo: Twarrt? = nil) throws {
        self.$author.id = authorID
        // We don't do much text manipulation on input, but let's normalize line endings.
        self.text = text.replacingOccurrences(of: "\r\n", with: "\r")
        self.images = images
        if let replyTarget = replyTo {
	        self.$replyGroup.id = replyTarget.$replyGroup.id ?? replyTarget.id
		}
        self.moderationStatus = .normal
    }
}

import Vapor
import Fluent


/// When a `Twarrt` is edited, a `TwarrtEdit` is created and associated with the
/// twarrt.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

final class TwarrtEdit: Model {
	static let schema = "twarrtedits"

    // MARK: Properties
    
    /// The edit's ID.
    @ID(key: .id) var id: UUID?
    
    /// The previous contents of the post.
     /// The previous text of the post.
    @Field(key: "text") var text: String
    
    /// The previous image, if any.
    @Field(key: "image_name") var imageName: String?
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
	// MARK: Relations

    /// The ID of the twarrt that was edited.
    @Parent(key: "twarrt") var twarrt: Twarrt
        
    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new TwarrtEdit.
    ///
    /// - Parameters:
    ///   - twarrt: The Twarrt that was edited.
    ///   - twarrtContent: The previous contents of the Twarrt.
    init(twarrt: Twarrt, twarrtContent: PostContentData) throws {
        self.$twarrt.id = try twarrt.requireID()
        self.$twarrt.value = twarrt
        self.text = twarrtContent.text
        self.imageName = twarrtContent.imageFilename
    }
    
    /// Initializes a new TwarrtEdit.
    ///
    /// - Parameters:
    ///   - twarrt: The Twarrt that was edited.
    ///   - text: The previous text of the Twarrt.
    ///   - image: The previous image of the Twarrt.
    init(twarrt: Twarrt, text: String, imageName: String) throws
    {
        self.$twarrt.id = try twarrt.requireID()
        self.$twarrt.value = twarrt
        self.text = text
        self.imageName = imageName
    }
    
    /// Initializes a new TwarrtEdit with the current contents of a twarrt.. Call on the twarrt BEFORE editing it
	///  to save previous contents.
    ///
    /// - Parameters:
    ///   - twarrt: The Twarrt that will be edited.
    init(twarrt: Twarrt) throws
    {
        self.$twarrt.id = try twarrt.requireID()
        self.$twarrt.value = twarrt
        self.text = twarrt.text
        self.imageName = twarrt.image
    }
}

import Vapor
import Foundation
import Fluent


/// A `Barrel` is typed, named, wrapper for lists. It can also serve as more general purpose
/// storage container for any information that can be expressed with strings.
///
/// - Note: An encodable/decodable true general purpose container is not currently supported
///   natively in Swift. Ideally we would have just a single `.userInfo` of type
///   [AnyHashable: AnyCodable], or at least [String: AnyCodable], instead of the compromise
///   of dual type-limited  properties used here. Perhaps someday... and it wouldn't even
///   break API at all.
///
/// Several properties beg a closer look:
///
/// * `.ownerID` is any model that has a UUID type ID. This will often be a `User`, such as in
///   the case of lists of other users or their lists of muted and alert keywords, but it is
///   also used to associate a list of users with a `SeaMailThread`, as a non-User example.
///
/// * `.barrelType` defines the context of the barrel's data and how it is used. A .userBlock
///   barrel contains the IDs of the users the owner is blocking, and a .keywordMute barrel
///   contains the list of strings that will mute public content for the user.
///
/// * `.name` is a title for the barrel. Any user-owned barrel must have a name, as it is the
///   barrel's identifying reference. "Blocked Users", "Muted Users", "Alert Keywords" and
///   "Muted Keywords" are all predefined, and a user might create lists of other users such
///   as "Favorites" or "Family".
///
/// * `.modelUUIDs` is an array of UUIDs. In a user list, these are the IDs of each user.
///   Any UUID model type can be referenced by this field, as long as there is a .barrelType
///   to provide the context.
///
/// * `.userInfo` is a dictionary of string keys and string array values. Keys "muteWords" and
///   "alertWords" are, respectively, arrays of strings in the .keywordMute and .keywordAlert
///   barrel types. With a supporting .barrelType it can also be used to hold simple key:value
///   string pairs, such as "startTime":["2019-11-21T05:30:00Z"] or "maximumCapacity":["8"].
///   Not pretty, but workable for our purposes.

final class Barrel: Model {
	static let schema = "barrels"
	
    // MARK: Properties
    
    /// The barrel's ID.
    @ID(key: .id) var id: UUID?
    
    /// The ID of the owning entity, which must be a UUID Model.
    @Field(key: "ownerID") var ownerID: UUID
    
    /// The type of information the barrel holds.
    @Field(key: "barrelType") var barrelType: BarrelType
    
    /// The name of the barrel.
    @Field(key: "name") var name: String

    /// The IDs of UUID-model barrel contents.
    @Field(key: "modelUUIDs") var modelUUIDs: [UUID]
    
    /// A dictionary to hold string type barrel contents.
    @Field(key: "userInfo") var userInfo: [String: [String]]
    
    /// Timestamp of the model's creation, set automatically.
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new Barrel.
    ///
    /// - Parameters:
    ///   - ownerID: The ID of the owning entity.
    ///   - barrelType: The type of information the barrel holds.
    ///   - name: A name for the barrel.
    ///   - modelUUIDs: The IDs of UUID-model barrel contents.
    ///   - userInfo: A dictionary that holds string-type barrel contents.
    init(
        ownerID: UUID,
        barrelType: BarrelType,
        name: String = "",
        modelUUIDs: [UUID] = .init(),
        userInfo: [String: [String]] = .init()
    ) {
        self.ownerID = ownerID
        self.barrelType = barrelType
        self.name = name
        self.modelUUIDs = modelUUIDs
        self.userInfo = userInfo
    }
    
    func contains(_ value: UUID) -> Bool {
    	return modelUUIDs.contains(value)
    }
    
    /// Tests if a barrel contains a reference to a model object. Does not check whether the model object is the right
    /// kind for this barrel. Does not throw if the model has no ID; returns false instead.
	func contains<T: Model>(_ model: T) -> Bool where T.IDValue == UUID {
    	if let modelID: UUID = model.id {
    		return modelUUIDs.contains(modelID)
    	}
    	return false
    }
}

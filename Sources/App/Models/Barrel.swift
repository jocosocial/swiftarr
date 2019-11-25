import Vapor
import Foundation
import FluentPostgreSQL

final class Barrel: Codable {
    // MARK: Properties
    
    /// The barrel's ID.
    var id: UUID?
    
    /// The ID of the owning entity, which must be a UUID Model.
    var ownerID: UUID
    
    /// The type of information the barrel holds.
    var barrelType: BarrelType
    
    /// The name of the barrel.
    var name: String

    /// The IDs of UUID-model barrel contents.
    var modelUUIDs: [UUID]
    
    /// A dictionary to hold string type barrel contents.
    var userInfo: [String: [String]]
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?

    // MARK: Initialization
    
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
}

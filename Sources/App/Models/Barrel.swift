import Vapor
import Foundation
import FluentPostgreSQL
import AnyCodable

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
    
    /// A key:value dictionary to hold the barrel contents.
    var userInfo: [String: AnyCodable]
    
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
    ///   - userInfo: A dictionary that holds the barrel's contents.
    init(
        ownerID: UUID,
        barrelType: BarrelType,
        name: String = "",
        userInfo: [String: AnyCodable] = .init()
    ) {
        self.ownerID = ownerID
        self.barrelType = barrelType
        self.name = name
        self.userInfo = userInfo
    }
}

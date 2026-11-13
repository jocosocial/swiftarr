import Vapor
import Fluent
import SQLKit
import PostgresNIO


/// If a model implements this, you can pass a new instance to createOrReturnDebounced and it will
/// try to create it, but if a recent row exists by the same creator with the same idempotency key,
/// it will return the existing one.
protocol Debouncable : Model {
    typealias CreatorKeyPath = KeyPath<Self, ParentProperty<Self, User>>
    static var creatorKeyPath: CreatorKeyPath { get }
    typealias IdempotencyKeyKeyPath = KeyPath<Self, OptionalFieldProperty<Self, UUID>>
    static var idempotencyKeyKeyPath: IdempotencyKeyKeyPath { get }
}

extension Debouncable {
    static var constraint: String { "ext_\(self.schema)_constraint_debounce" }
    var creatorProperty: ParentProperty<Self, User> {
        self[keyPath: Self.creatorKeyPath]
    }
    static var creatorFieldKey: FieldKey { Self().creatorProperty.keys.first! }
    var idempotencyKeyProperty: OptionalFieldProperty<Self, UUID> {
        self[keyPath: Self.idempotencyKeyKeyPath]
    }
    static var idempotencyKeyFieldKey: FieldKey { Self().idempotencyKeyProperty.keys.first! }

    /// Attempts to create the given model instance. If it succeeds, return true.
    /// If it fails because of the idempotency key constraint, set the instance to the existing row from the table and return false.
    /// If it fails for any other reason, rethrow the error.
    /// This has to be a static method because we can't overwrite self within a mutating method.
    static func createOrReturnDebounced(_ model: inout Self, on database: Database) async throws -> Bool {
        do {
            try await model.create(on: database)
            return true
        } catch let error as PSQLError where error.serverInfo?[.sqlState] == "23505" && error.serverInfo?[.constraintName] == Self.constraint {
            
            // Fetch the existing record that caused the collision
            guard let existingRecord = try await Self.query(on: database)
                .filter(Self.creatorKeyPath.appending(path: \.$id) == model.creatorProperty.id)
                .filter(Self.idempotencyKeyKeyPath == model.idempotencyKeyProperty.wrappedValue)
                .first() else {
                // Weird that it wouldn't be there, but what else would we do?
                throw Abort(.conflict, reason: "Debounced \(self.schema).")
            }

            model = existingRecord
            return false
        } catch {
            throw error
        }
    }
}

/// The migration to add the necessary columns and indexes when you make a model Debouncable.
struct AddDebounceConstraint<T: Debouncable> : AsyncMigration {
    var name: String { "AddDebounceConstraint-\(T.schema)" }

    func prepare(on database: Database) async throws {      
        let idem = T.idempotencyKeyFieldKey
        try await database.schema(T.schema)
            .field(idem, .uuid)
            .unique(on: T.creatorFieldKey, idem, name:T.constraint)
            .update()    
    }

    func revert(on database: Database) async throws {
        try await database.schema(T.schema)
            .deleteField(T.idempotencyKeyFieldKey)  // also drops the constraint on it.
            .update()
    }
}
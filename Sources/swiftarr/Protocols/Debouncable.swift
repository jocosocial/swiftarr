import Vapor
import Fluent
import SQLKit
import PostgresNIO

/// A type-erased version of ParentProperty that doesn't include OptionalParentProperty.
protocol AnyRequiredParentProperty<From>: AnyProperty {
    associatedtype From: Model
    var extractedFieldKey: FieldKey? { get }
    func applyFilter(to query: QueryBuilder<From>)
}

extension AnyRequiredParentProperty where Self: AnyDatabaseProperty & AnyQueryAddressableProperty {
    
    var extractedFieldKey: FieldKey? {
        return self.keys.first
    }
    
    func applyFilter(to query: QueryBuilder<From>) {        
        if let queryValue = self.anyQueryableProperty.queryableValue() {
            query.filter(.path(self.queryablePath, schema: From.schema), .equal, queryValue)
        }
    }
}

extension ParentProperty: AnyRequiredParentProperty {
    typealias From = From
}

/// A wrapper around @Field that marks that field as the content we should dedupe against.
@propertyWrapper
public final class ContentFieldProperty<Model: FluentKit.Model, Value: Codable & Sendable> {
    // Wrap standard Fluent field storage underneath
    public var projectedValue: FieldProperty<Model, Value>
    
    public var wrappedValue: Value {
        get { projectedValue.wrappedValue }
        set { projectedValue.wrappedValue = newValue }
    }
    
    public init(key: FieldKey) {
        self.projectedValue = FieldProperty<Model, Value>(key: key)
    }
}

extension Model {
    public typealias ContentField<Value> = ContentFieldProperty<Self, Value>
        where Value: Codable & Sendable
}

extension ContentFieldProperty: Property {
    public var value: Value? {
        get { self.projectedValue.value }
        set { self.projectedValue.value = newValue }
    }
    public var path: [FieldKey] {
        get { self.projectedValue.path }
    }
}

extension ContentFieldProperty: AnyDatabaseProperty {
    public var keys: [FieldKey] { self.projectedValue.keys }
    public func output(from output: any DatabaseOutput) throws {
        try self.projectedValue.output(from: output)
    }
    public func input(to input: any DatabaseInput) {
        self.projectedValue.input(to: input)
    }
}

extension ContentFieldProperty: QueryableProperty { }

extension ContentFieldProperty: AnyCodableProperty {
    public func encode(to encoder: Encoder) throws { try projectedValue.encode(to: encoder) }
    public func decode(from decoder: Decoder) throws { try projectedValue.decode(from: decoder) }
}

extension ContentFieldProperty: QueryAddressableProperty {
    public typealias QueryablePropertyType = FieldProperty<Model, Value>
    public var queryableProperty: FieldProperty<Model, Value> { return self.projectedValue }
}

extension ContentFieldProperty: AnyQueryAddressableProperty {
    public var anyQueryableProperty: any AnyQueryableProperty { self.projectedValue.anyQueryableProperty }
    public var queryablePath: [FieldKey] { self.projectedValue.queryablePath }
}

/// Type erasure for ContentFieldProperty so we don't have to care what its type is,
/// though it's probably String.
protocol AnyContentFieldProperty<From> {
    associatedtype From: Model
    var extractedFieldKey: FieldKey? { get }
    func applyFilter(to query: QueryBuilder<From>)
}

extension ContentFieldProperty: AnyContentFieldProperty {
    typealias From = Model
    var extractedFieldKey: FieldKey? {
        return self.projectedValue.queryablePath.first
    }
    
    func applyFilter(to query: QueryBuilder<From>) {
        
        if let queryValue = self.projectedValue.anyQueryableProperty.queryableValue() {
            
            query.filter(.path(self.projectedValue.queryablePath, schema: From.schema), .equal, queryValue)
        }
    }
}

/// If a model implements this, you can pass a new instance to createOrReturnDebounced and it will
/// try to create it, but if a recent row exists in the same parents with the same content, it will
/// set the input to the existing model via the inout parameter and return false.
protocol Debouncable : Model {
    static var debounceDuration: String { get }
}

extension Debouncable {
    static var debounceDuration: String { "2 minutes" }
    static var debounceUntilKey: FieldKey { "debounce_until" }
    static var trigger: String { "ext_\(self.schema)_trigger_debounce" }
    static var triggerFunction: String { "set_\(self.schema)_debounce_time" }
    static var constraint: String { "ext_\(self.schema)_constraint_debounce" }

    /// The field key of the created at column--don't assume it's created_at, even though it usually is.
    static var createdAtColumnKey: FieldKey {
        Self().properties.compactMap {
            $0 as? TimestampProperty<Self, DefaultTimestampFormat>
        }.first { $0.trigger == .create }!.keys.first! 
    }

    /// Returns all static FieldKeys belonging strictly to non-optional @Parent properties
    static var parentFieldKeys: [FieldKey] {
        let dummyInstance = Self()
        return dummyInstance.properties.compactMap { property in
            let parentProperty = property as? any AnyRequiredParentProperty<Self>
            return parentProperty?.extractedFieldKey
        }
    }
    
    /// Returns all static FieldKeys belonging strictly to @ContentField properties
    static var contentFieldKeys: [FieldKey] {
        let dummyInstance = Self()
        let result = dummyInstance.properties.compactMap { property in
            let contentProperty = property as? any AnyContentFieldProperty<Self>
            return contentProperty?.extractedFieldKey
        }
        if result.count == 0 {
            // Safety assertion if developer forgets to tag a field
            fatalError("Model \(Self.schema) must annotate at least one field with @ContentField to support debouncing.")
        }
        return result
    }

    /// Attempts to create the given model instance. If it succeeds, return true.
    /// If it fails because of the debounce constraint, set the instance to the existing row from the table and return false.
    /// If it fails for any other reason, rethrow the error.
    /// This has to be a static method because we can't overwrite self within a mutating method.
    static func createOrReturnDebounced(_ model: inout Self, on database: Database) async throws -> Bool {
        do {
            try await model.create(on: database)
            return true
        } catch let error as PSQLError where error.serverInfo?[.sqlState] == "23P01" && error.serverInfo?[.constraintName] == Self.constraint {
            let query = Self.query(on: database)            
            for property in model.properties {// Apply required parent filter if it matches
                if let requiredParent = property as? any AnyRequiredParentProperty<Self> {
                    requiredParent.applyFilter(to: query)
                }
                if let contentField = property as? any AnyContentFieldProperty<Self> {
                    contentField.applyFilter(to:query)
                }
            }
            
            // Fetch the existing record that caused the collision
            guard let existingRecord = try await query
                .sort(createdAtColumnKey, .descending)
                .first()
            else {
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

/// The migration to add the necessary columns, triggers, and indexes when you make a model Debouncable.
struct AddDebounceConstraint<T: Debouncable> : AsyncMigration {
    var name: String { "AddDebounceConstraint-\(T.schema)" }

    func prepare(on database: Database) async throws {        
        try await database.transaction { tx in
            let txSql = tx as! SQLDatabase
            
            try await txSql.raw("CREATE EXTENSION IF NOT EXISTS btree_gist;").run()
            try await txSql.raw("CREATE EXTENSION IF NOT EXISTS pgcrypto;").run()
            try await txSql.raw("ALTER TABLE \(unsafeRaw: T.schema) ADD COLUMN IF NOT EXISTS \(unsafeRaw: T.debounceUntilKey.description) TIMESTAMPTZ;").run()

            // Trigger to set debounce_until automatically.
            // By doing this instead of a stored generated always column,
            // we could null it out to shrink the index if we needed to.
            try await txSql.raw("""
                CREATE OR REPLACE FUNCTION \(unsafeRaw: T.triggerFunction)()
                RETURNS TRIGGER AS $$
                BEGIN
                    NEW.\(unsafeRaw: T.debounceUntilKey.description) := NEW.\(unsafeRaw: T.createdAtColumnKey.description) + INTERVAL '\(unsafeRaw: T.debounceDuration)';
                    RETURN NEW;
                END;
                $$ LANGUAGE plpgsql;
            """).run()

            try await txSql.raw("DROP TRIGGER IF EXISTS \(unsafeRaw: T.trigger) ON \(unsafeRaw: T.schema);").run()
            try await txSql.raw("""
                CREATE TRIGGER \(unsafeRaw: T.trigger)
                BEFORE INSERT ON \(unsafeRaw: T.schema)
                FOR EACH ROW
                EXECUTE FUNCTION \(unsafeRaw: T.triggerFunction)();
            """).run()
                
            // Build the compound exclusion string dynamically
            let gistFieldsSql = (
                T.parentFieldKeys.map { "\($0) WITH =" } +
                T.contentFieldKeys.map { "digest(\($0), 'sha256') WITH =" }).joined(separator: ", ")
            
            // Add constraint.
            try await txSql.raw("""
                ALTER TABLE \(unsafeRaw: T.schema) ADD CONSTRAINT \(unsafeRaw: T.constraint) EXCLUDE USING gist (
                    \(unsafeRaw: gistFieldsSql),
                    tstzrange(\(unsafeRaw: T.createdAtColumnKey.description), \(unsafeRaw: T.debounceUntilKey.description)) WITH &&
                ) WHERE (\(unsafeRaw: T.debounceUntilKey.description) IS NOT NULL);
            """).run()
        }
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("ALTER TABLE \(unsafeRaw: T.schema) DROP CONSTRAINT IF EXISTS \(unsafeRaw: T.constraint);").run()
        try await sql.raw("DROP TRIGGER IF EXISTS \(unsafeRaw: T.trigger) ON \(unsafeRaw: T.schema);").run()
        try await sql.raw("DROP FUNCTION IF EXISTS \(unsafeRaw: T.triggerFunction)();").run()
        try await sql.raw("ALTER TABLE \(unsafeRaw: T.schema) DROP COLUMN IF EXISTS \(unsafeRaw: T.debounceUntilKey.description);").run()
    }
}
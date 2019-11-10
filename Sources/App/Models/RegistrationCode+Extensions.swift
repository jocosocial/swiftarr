import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension RegistrationCode: PostgreSQLUUIDModel {}

// model can be passed as HTTP body data
extension RegistrationCode: Content {}

// MARK: - Custom Migration

extension RegistrationCode: Migration {
    /// Required by `Migration` protocol. Creates the table, with unique constraint on `.code`.
    ///
    /// - Parameter connection: A connection to the database, provided automatically.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            builder in
            try addProperties(to: builder)
            // registration code must be unique
            builder.unique(on: \.code)
        }
    }
}

// MARK: - Timestamping Conformance

extension RegistrationCode {
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
}

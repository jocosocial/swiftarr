import Fluent

import Vapor

/// A related set of Puzzles.

final class Hunt: Model, @unchecked Sendable {
	static let schema = "hunt"

	// MARK: Properties

	/// The hunt's ID.
	@ID(key: .id) var id: UUID?

	/// The title of the hunt.
	@Field(key: "title") var title: String

	/// A description of the hunt to convince people to join.
	@Field(key: "description") var description: String

	// MARK: Relations

	/// The child `Puzzle`s within the hunt.
	@Children(for: \.$hunt) var puzzles: [Puzzle]

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new Hunt.
	///
	/// - Parameters:
	///   - creator: The creator of this hunt
	///   - title: The title for the hunt.
	///   - description: A description of this hunt
	init(title: String, description: String) throws {
		self.title = title
		self.description = description
	}
}

struct CreateHuntSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("hunt")
			.id()
			.field("title", .string, .required)
			.field("description", .string, .required)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("hunt").delete()
	}
}

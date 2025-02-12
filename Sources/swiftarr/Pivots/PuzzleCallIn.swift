import Fluent

import Vapor

final class PuzzleCallIn: Model, @unchecked Sendable {
	static let schema = "puzzle+callin"
  
	// MARK: Properties

	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	@Field(key: "raw_submission") var rawSubmission: String

	@Field(key: "normalized_submission") var normalizedSubmission: String

	@Enum(key: "result") var result: CallInResult

	// MARK: Relationships

	/// The associated `User` who called in the possible answer
	@Parent(key: "user") var user: User

	/// The `Puzzle` the user attempted to solve.
	@Parent(key: "puzzle") var puzzle: Puzzle

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new `HuntSolver` pivot.
	///
	/// - Parameters:
	///   - user: The associated `User` model.
	///   - hunt: The associated `Hunt` model.
	init(_ user: User, _ puzzle: Puzzle, _ submission: String, _ result: CallInResult) throws {
		self.$user.id = try user.requireID()
		self.$user.value = user
		self.$puzzle.id = try puzzle.requireID()
		self.$puzzle.value = puzzle
		self.rawSubmission = submission
		self.normalizedSubmission = submission.normalizePuzzleAnswer()
		self.result = result;
	}

	init(_ userID: UUID, _ puzzle: Puzzle, _ submission: String, _ result: CallInResult) throws {
		self.$user.id = userID
		self.$puzzle.id = try puzzle.requireID()
		self.$puzzle.value = puzzle
		self.$puzzle.value = puzzle
		self.rawSubmission = submission
		self.normalizedSubmission = submission.normalizePuzzleAnswer()
		self.result = result;
	}
}

struct CreatePuzzleCallInSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
    let callInResult = try await database.enum("call_in_result").read()
		try await database.schema("puzzle+callin")
				.id()
				.unique(on: "user", "puzzle", "normalized_submission")
				.field("created_at", .datetime)
				.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
				.field("puzzle", .uuid, .required, .references("puzzle", "id", onDelete: .cascade))
				.field("raw_submission", .string, .required)
				.field("normalized_submission", .string, .required)
				.field("result", callInResult, .required)
				.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("puzzle+callin").delete()
	}
}

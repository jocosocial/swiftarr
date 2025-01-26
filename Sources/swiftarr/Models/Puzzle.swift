import Fluent

import Vapor

/// A Puzzle is a member of a hunt which has an answer. It may also have hints
/// which are shown but not stored if

final class Puzzle: Model, @unchecked Sendable {
	static let schema = "puzzle"

	// MARK: Properties

	/// The puzzle's ID.
	@ID(key: .id) var id: UUID?

	/// The title of the puzzle.
	@Field(key: "title") var title: String

	/// The body of the puzzle.
	@Field(key: "body") var body: String

	/// The answer to the puzzle.
	@Field(key: "answer") var answer: String

	/// Strings that are not the answer, but which yield a helpful response.
	/// required, but can be empty.
	@Field(key: "hints") var hints: [String: String]

	/// The time at which the puzzle unlocks.
	/// If unset, treated as the dawn of time.
	@OptionalField(key: "unlock_time") var unlockTime: Date?

	// MARK: Relations

	/// The Hunt to which the puzzle belongs.
	@Parent(key: "hunt") var hunt: Hunt

	/// Attempts to answer the puzzle.
	/// But you'll probably never load them in this direction.
	@Children(for: \.$puzzle) var callIns: [PuzzleCallIn]

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new Hunt.
	///
	/// - Parameters:
	///   - hunt: The hunt the puzzle belongs to
	///   - title: The title for the puzzle.
	///   - answer: The answer for the puzzle.
	///   - hints: a dictionary of hints
	init(
		hunt: Hunt,
		title: String,
		body: String,
		answer: String,
		hints: [String: String],
		unlockTime: Date?
	) throws {
		self.$hunt.id = try hunt.requireID()
		self.$hunt.value = hunt
		self.title = title
		self.body = body
		self.answer = answer
		self.hints = [:]
		self.hints.reserveCapacity(hints.count)
		for (key, response) in hints {
			self.hints[key.normalizePuzzleAnswer()] = response
		}
		self.unlockTime = unlockTime
	}
}

struct CreatePuzzleSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("puzzle")
			.id()
			.field("title", .string, .required)
			.field("body", .string, .required)
			.field("answer", .string, .required)
			.field("hints", .dictionary(of: .string), .required)
			.field("hunt", .uuid, .required, .references("hunt", "id", onDelete: .cascade))
			.field("unlock_time", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("puzzle").delete()
	}
}

extension String {

	/// Converts a string to the form we will use for puzzle answer comparison.
	/// We don't store answers normalized because when they are correct we will show
	/// them in their original form. We do store hint keys like this so we can do a
	/// dictionary lookup.
	func normalizePuzzleAnswer() -> String {
		return self.uppercased().filter { !$0.isWhitespace }
	}
}

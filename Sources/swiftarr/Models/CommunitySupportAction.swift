import Fluent
import Foundation
import Vapor

/// One entry in the Community Support log. The log is append-only--there are no update or delete routes--and serves as both each
/// report's timeline (filter by report) and the team-wide audit log (unfiltered). Only changes are logged, never views.
final class CommunitySupportAction: Model, @unchecked Sendable {
	static let schema = "community_support_action"

	// MARK: Properties

	@ID(key: .id) var id: UUID?

	/// What happened. Stored as a string.
	@Field(key: "action_type") var actionType: CommunitySupportActionType

	/// For `.statusChanged`, the status before and after.
	@OptionalField(key: "old_status") var oldStatus: CommunitySupportReportStatus?
	@OptionalField(key: "new_status") var newStatus: CommunitySupportReportStatus?

	/// The text of a note, or empty for actions that aren't notes.
	@Field(key: "note") var note: String

	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The team member who did it.
	@Parent(key: "actor") var actor: User

	/// The report it was done to. Nil for team-wide entries, like a CSV export.
	@OptionalParent(key: "report_id") var report: CommunitySupportReport?

	// MARK: Initialization

	// Used by Fluent
	init() {}

	init(
		actor: UUID,
		report: UUID?,
		type: CommunitySupportActionType,
		oldStatus: CommunitySupportReportStatus? = nil,
		newStatus: CommunitySupportReportStatus? = nil,
		note: String = ""
	) {
		self.$actor.id = actor
		self.$report.id = report
		self.actionType = type
		self.oldStatus = oldStatus
		self.newStatus = newStatus
		self.note = note
	}
}

struct CreateCommunitySupportActionSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("community_support_action")
			.id()
			.field("action_type", .string, .required)
			.field("old_status", .string)
			.field("new_status", .string)
			.field("note", .string, .required)
			.field("created_at", .datetime)
			.field("actor", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("report_id", .uuid, .references("community_support_report", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("community_support_action").delete()
	}
}

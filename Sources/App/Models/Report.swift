import Fluent
import Foundation
import Vapor

/// Twit-arr moderation relies in part on user-submitted reports of content and/or behavior
/// which does not conform to community standards. A `Report` can be submitted for Moderator
/// review on any of: an individual `Twarrt` or `ForumPost`, an entire `Forum`, a `FezPost`,
/// or a `User` (such as for general behavioral pattern, or their profile contents).
///
/// The `.submitterID` is always the user's primary user ID. An individual post can only be
/// reported once per primary user. There is no per user restriction on the number of reports
/// of a particular `Forum` or `User`.
///
/// The `.reportedID` field is a string value, because the entity being reported may have
/// either a UUID or an integer based ID, which is determined via the `.reportType`.
///
/// The lifecycle flow of `Report`s is:
///	- Created by submitter
/// - Viewed by a moderator in a list of open reports
/// - Moderator takes the report (handledBy is set to the moderator's UUID). Other mods should be able to see the report is being handled.
/// - Moderator modifies content, quarantines content, warns user, bans user, or takes some other action.
/// - Moderator fills in actionTaken field and closes the report.

final class Report: Model {
	static let schema = "report"

	// MARK: Properties

	/// The report's ID.
	@ID(key: .id) var id: UUID?

	/// The type of entity reported.
	@Field(key: "reportType") var reportType: ReportType

	/// The ID of the entity reported. Could resolve to an Int or a UUID, depending on the value of`reportType`.
	@Field(key: "reportedID") var reportedID: String

	/// An optional message from the submitter.
	@Field(key: "submitterMessage") var submitterMessage: String

	/// Set to a new UUID() when a Moderator starts handling one or more reports. Any mod actions the mod takes until these reports are closed
	/// get tagged with this UUID. Reports may be closed without ever setting an action group.
	@OptionalField(key: "action_group") var actionGroup: UUID?

	/// The status of the report.
	@Field(key: "isClosed") var isClosed: Bool

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	// MARK: Relations

	/// The `User` submitting the report.
	@Parent(key: "author") var submitter: User

	/// The `User` whose content is being reported.
	@Parent(key: "reportedUser") var reportedUser: User

	/// The  moderator-level`User`handling the report. Nil until a moderator starts handling the report.
	@OptionalParent(key: "handled_by") var handledBy: User?

	// MARK: Initializaton

	// Used by Fluent
	init() {}

	/// Initializes a new Report.
	///
	/// - Parameters:
	///   - reportType: The type of entity reported.
	///   - reportedID: The ID of the entity reported.
	///   - submitter: The user submitting the report.
	///   - submitterMessage: An optional message from the submitter.
	init<T: Reportable>(reportedContent: T, submitter: User, submitterMessage: String = "") throws {
		self.reportType = reportedContent.reportType
		self.reportedID = try reportedContent.reportableContentID()
		self.$reportedUser.id = reportedContent.authorUUID
		self.$submitter.id = try submitter.requireID()
		self.$submitter.value = submitter
		self.submitterMessage = submitterMessage
		self.isClosed = false
	}
}

struct CreateReportSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("report")
			.id()
			.field("reportType", .string, .required)
			.field("reportedID", .string, .required)
			.field("submitterMessage", .string, .required)
			.field("action_group", .uuid)
			.field("isClosed", .bool, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("author", .uuid, .required, .references("user", "id"))
			.field("reportedUser", .uuid, .required, .references("user", "id"))
			.field("handled_by", .uuid, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("report").delete()
	}
}

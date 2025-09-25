import Fluent
import Foundation
import Vapor

/// A feedback report from a Shadow Event Host. 
/// 
/// THO asks those who host shadow events to fill out a feedback form after their event to tell THO how their event went.
/// This is the db model that stores that data.
/// 
/// - See Also: [EventFeedbackData](EventFeedbackData) the POST data containg the web form contents
/// - See Also: [EventFeedbackReport](EventFeedbackReport) feedback data returned by several API calls 
/// 
final class EventFeedback: Model, @unchecked Sendable {
	static let schema = "event_feedback"

	// MARK: Properties

	/// The ID for this feedback response.
	@ID(key: .id) var id: UUID?
	
	/// Name of the person who authored the feedback
	@Field(key: "responder_name") var responderName: String

	/// Title of the event that the feedback is referring to. Often sourced from the linked Event itself.
	@Field(key: "event_name") var eventName: String

	/// Location of the event that the feedback is referring to.
	@Field(key: "event_location") var eventLocation: String

	/// Start time of the event that the feedback is referring to.
	@Field(key: "event_start_time") var eventStartTime: Date

	/// The respondent's estimate of the event attendance. Could be a range, or "about 60, idk" so field is a string.
	@Field(key: "attendance") var attendance: String
	
	/// User's answer to the "How did it go?" feedback question.
	@Field(key: "recap") var recapField: String
	
	/// User's answer to the "Any issues?" feedback question.
	@Field(key: "issues") var issuesField: String
	
	/// For those able to view feedback reports. TRUE marks this report as containing something that needs to be dealt with.
	/// The flag is global; not per-user like 'favorite' flags. Not intended to be a full task-management system.
	@Field(key: "actionable") var actionable: Bool
	
	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, except for changes to the 'actionable' field. NOT set automatically.
	@Timestamp(key: "updated_at", on: .none) var updatedAt: Date?

	// MARK: Relations

	/// The author of the feedback
	@Parent(key: "author") var author: User

	/// The event the feedback refers to; optional as future versions may not require linking to an event on the public schedule
	@OptionalParent(key: "event_id") var event: Event?

	// MARK: Initialization

	// Used by Fluent
	init() {}
	
	// Although the Event contains fields for event name, location, and start time, we use the values from the form, for reasons.
	// Same idea with author and authorName (although author.realName is optional)	
	init(event: Event, author: UserCacheData, feedback: EventFeedbackData) throws {
		try update(event: event, author: author, feedback: feedback)
	}
	
	// Although the Event contains fields for event name, location, and start time, we use the values from the form, for reasons.
	// Same idea with author and authorName (although author.realName is optional)	
	func update(event: Event, author: UserCacheData, feedback: EventFeedbackData) throws {
		self.$event.id = try event.requireID()
		self.$author.id = author.userID
		self.responderName = feedback.hostName
		self.eventName = feedback.eventTitle
		self.eventLocation = feedback.eventLocation
		self.eventStartTime = feedback.eventTime
		self.attendance = feedback.attendance
		self.recapField = feedback.recapString
		self.issuesField = feedback.issuesString
		if !self.$id.exists {
			self.actionable = false
		}
		self.updatedAt = Date()
	}
}

struct CreateEventFeedbackSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("event_feedback")
			.id()
			.field("responder_name", .string, .required)
			.field("event_name", .string, .required)
			.field("event_location", .string, .required)
			.field("event_start_time", .datetime, .required)
			.field("attendance", .string, .required)
			.field("recap", .string, .required)
			.field("issues", .string, .required)
			.field("actionable", .bool, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("author", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("event_id", .uuid, .references("event", "id", onDelete: .setNull))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("event_feedback").delete()
	}

}

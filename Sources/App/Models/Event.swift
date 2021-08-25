import Foundation
import Vapor
import Fluent


/**
	 An `Event` on the official schedule, imported from sched.com's `.ics` format.
	 
	 - See Also: [EventData](EventData) the DTO for returning info on Events.
	 - See Also: [CreateEventSchema](CreateEventSchema) the Migration for creating the Event table in the database.
	 - See Also: [EventType](EventType)
*/
final class Event: Model {
	static let schema = "events"
	
	// MARK: Properties
    
    /// The event's ID.
    @ID(key: .id) var id: UUID?
    
    /// The event's official identifier. (sched.com "UID")
    @Field(key: "uid") var uid: String
    
    /// The start time of the event. (sched.com "DTSTART")
    @Field(key: "startTime") var startTime: Date
    
    /// The end time of the event. (sched.com "DTEND")
    @Field(key: "endTime") var endTime: Date
    
    /// The title of the event. (sched.com "SUMMARY")
    @Field(key: "title") var title: String
    
    /// A description of the event. (sched.com "DESCRIPTION")
    @Field(key: "info") var info: String
    
    /// The location of the event. (sched.com "LOCATION")
    @Field(key: "location") var location: String
    
    /// The type of event. (sched.com "CATEGORIES")
    @Field(key: "eventType") var eventType: EventType
    
    /// Timestamp of the model's creation, set automatically.
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
 	// MARK: Relations

    /// The ID of a forum associated with the event. I believe we want the forum to be the parent of the event
    /// so the forum can keep existing even if the event is deleted.
    @OptionalParent(key: "forum_id") var forum: Forum?
    
	// MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new Event.
    ///
    /// - Parameters:
    ///   - startTime: The start time of the event.
    ///   - endTime: The end time of the event.
    ///   - title: The title of the event.
    ///   - description: A description of the event.
    ///   - location: The location of the event.
    ///   - eventType: The designated type of event.
    ///   - uid: The event's sched.com identifier.
    init(
        startTime: Date,
        endTime: Date,
        title: String,
        description: String,
        location: String,
        eventType: EventType,
        uid: String
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.info = description
        self.location = location
        self.eventType = eventType
        self.uid = uid
        self.$forum.id = nil
        self.$forum.value = nil
    }
}

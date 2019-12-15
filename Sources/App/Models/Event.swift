import Foundation
import Vapor
import FluentPostgreSQL

/// An `Event` on the official schedule, imported from sched.com's `.ics` format.

final class Event: Codable {
    // MARK: Properties
    
    /// The event's ID.
    var id: UUID?
    
    /// The start time of the event. (sched.com "DTSTART")
    var startTime: Date
    
    /// The end time of the event. (sched.com "DTEND")
    var endTime: Date
    
    /// The title of the event. (sched.com "SUMMARY")
    var title: String
    
    /// A description of the event. (sched.com "DESCRIPTION")
    var info: String
    
    /// The location of the event. (sched.com "LOCATION")
    var location: String
    
    /// The type of event. (sched.com "CATEGORIES")
    var eventType: EventType
    
    /// The event's official identifier. (sched.com "UID")
    var uid: String
    
    /// The ID of a forum associated with the event.
    var forumID: UUID?
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?
    
    // MARK: Initialization
    
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
        self.forumID = nil
    }
}

import Foundation
import Vapor
import FluentPostgreSQL

/// Twit-arr moderation relies in part on user-submitted reports of content and/or behavior
/// which does not conform to community standards. A `Report` can be submitted for Moderator
/// review on any of: an individual `Twarrt` or `ForumPost`, an entire `Forum`, or a `User`
/// (such as for general behavioral pattern, or their profile contents).
///
/// The `.reportedID` field is a string value, because the entity being reported may have
/// either a UUID or an integer based ID, which is determined via the `.reportType`.

struct Report: Codable {
    // MARK: Properties
    
    /// The report's ID.
    var id: UUID?
    
    /// The type of entity reported.
    var reportType: ReportType
    
    /// The ID of the entity reported.
    var reportedID: String
    
    /// The ID of the `User` submitting the report.
    var submitterID: UUID
    
    /// An optional message from the submitter.
    var submitterMessage: String?
    
    /// The status of the report.
    var isClosed: Bool
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    // MARK: Initializaton
    
    /// Initializes a new Report.
    ///
    /// - Parameters:
    ///   - reportType: The type of entity reported.
    ///   - reportedID: The ID of the entity reported.
    ///   - submitterID: The ID of the user submitting the report.
    ///   - submitterMessage: An optional message from the submitter.
    init(
        reportType: ReportType,
        reportedID: String,
        submitterID: UUID,
        submitterMessage: String? = nil
    ) {
        self.reportType = reportType
        self.reportedID = reportedID
        self.submitterID = submitterID
        self.submitterMessage = submitterMessage
        self.isClosed = false
    }
}

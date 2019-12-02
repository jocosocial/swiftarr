import Foundation
import Vapor
import FluentPostgreSQL

/// Parser for a sched.com `.ics` file, based on https://jococruise2019.sched.com export.

final class EventParser {
    
    /// A `DateFormatter` for converting sched.com's non-standard date strings to a `Date`.
    static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return dateFormatter
    }()
    
    /// Parses an array of raw sched.com `.ics` strings to an `Event` array.
    ///
    /// - Parameters:
    ///   - icsArray: Array of strings from a sched.com `.ics` export.
    ///   - connection: The connection to a database.
    /// - Returns: `[Event]` containing the events.
    static func parse(_ icsArray: [String], on connection: PostgreSQLConnection) -> Future<[Event]> {
        var events: [Event] = []
        var eventComponents: [String] = []
        var inEvent: Bool = false
        var isComplete: Bool = false
        
        for element in icsArray {
            switch element {
                case "BEGIN:VEVENT":
                    inEvent = true
                    eventComponents = []
                    continue
                case "END:VEVENT":
                    inEvent = false
                    isComplete = true
                    continue
                default:
                    break
            }
            // nothing of interest
            if !inEvent && !isComplete { continue }
            // components ready to process
            if isComplete {
                isComplete = false
                guard let event = makeEvent(from: eventComponents) else {
                    continue
                }
                events.append(event)
            }
            // else still gathering components
            eventComponents.append(element)
        }
        return connection.future(events)
    }
    
    /// Creates an `Event` from an array of the raw lines appearing between `BEGIN:VEVENT` and
    /// `END:VEVENT` lines in a sched.com `.ics` file. Escape characters that may appear in
    /// "SUMMARY", "DESPRIPTION" and "LOCATION" values are stripped.
    ///
    /// - Parameter components: `[String]` containing the lines to be processed.
    /// - Returns: `Event` if the date strings could be parsed, else `nil`.
    static func makeEvent(from components: [String]) -> Event? {
        var startTime: Date? = nil
        var endTime: Date? = nil
        var title: String = ""
        var description: String = ""
        var location: String = ""
        var eventType: EventType = .general
        var uid: String = ""
        
        for component in components {
            let pair = component.split(separator: ":", maxSplits: 1)
            let (key, value) = (String(pair[0]), String(pair[1]))
            switch key {
                case "DTSTART":
                    startTime = dateFormatter.date(from: value)
                case "DTEND":
                    endTime = dateFormatter.date(from: value)
                case "SUMMARY":
                    title = value.replacingOccurrences(of: "\\,", with: ",")
                case "DESCRIPTION":
                    description = value.replacingOccurrences(of: "\\,", with: ",")
                case "LOCATION":
                    location = value.replacingOccurrences(of: "\\,", with: ",")
                case "CATEGORIES":
                    switch value.trimmingCharacters(in: .whitespaces) {
                        case "GAMING":
                            eventType = .gaming
                        case "LIVE PODCAST":
                            eventType = .livePodcast
                        case "MAIN CONCERT":
                            eventType = .mainConcert
                        case "OFFICE HOURS":
                            eventType = .officeHours
                        case "PARTY":
                            eventType = .party
                        case "Q&A / PANEL":
                            eventType = .qaPanel
                        case "READING / PERFORMANCE":
                            eventType = .readingPerformance
                        case "SHADOW CRUISE":
                            eventType = .shadow
                        case "SIGNING":
                            eventType = .signing
                        case "WORKSHOP":
                            eventType = .workshop
                        default:
                            eventType = .general
                }
                case "UID":
                    uid = value
                default:
                    continue
            }
        }
        guard let start = startTime, let end = endTime else {
            print("event uid \(uid) dates could not be parsed")
            return nil
        }
        return Event(
            startTime: start,
            endTime: end,
            title: title,
            description: description,
            location: location,
            eventType: eventType,
            uid: uid
        )
    }
}

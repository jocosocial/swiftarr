import Foundation
import Vapor
import Fluent


/// Parser for a sched.com `.ics` file, based on https://jococruise2019.sched.com export.

final class EventParser {
    
    /// A `DateFormatter` for converting sched.com's non-standard date strings to a `Date`.
    let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        // FIXME: still need to figure out how to serve up dates
        // -18000/-14400 seconds is EST/EDT
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dateFormatter
    }()
    
    /// Parses an array of raw sched.com `.ics` strings to an `Event` array.
    ///
    /// - Parameters:
    ///   - icsArray: Array of strings from a sched.com `.ics` export.
    ///   - connection: The connection to a database.
    /// - Returns: `[Event]` containing the events.
    func parse(_ dataString: String) -> [Event] {
		let icsArray = dataString.components(separatedBy: .newlines)
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
        return events
    }
    
    /// Creates an `Event` from an array of the raw lines appearing between `BEGIN:VEVENT` and
    /// `END:VEVENT` lines in a sched.com `.ics` file. Escape characters that may appear in
    /// "SUMMARY", "DESCRIPTION" and "LOCATION" values are stripped.
    ///
    /// - Parameter components: `[String]` containing the lines to be processed.
    /// - Returns: `Event` if the date strings could be parsed, else `nil`.
    func makeEvent(from components: [String]) -> Event? {
        var startTime: Date? = nil
        var endTime: Date? = nil
        var title: String = ""
        var description: String = ""
        var location: String = ""
        var eventType: EventType = .general
        var uid: String = ""
        
        for component in components {
            // stray newlines make empty elements
            guard !component.isEmpty else {
                continue
            }
            let pair = component.split(separator: ":", maxSplits: 1)
            var (key, value): (String, String)
            // account for empty fields
            if pair.count == 2 {
                (key, value) = (String(pair[0]), String(pair[1]))
            } else {
                (key, value) = (String(pair[0]), "")
            }
            // strip escaped nonsense
            value = value.replacingOccurrences(of: "&amp;", with: "&")
            value = value.replacingOccurrences(of: "\\", with: "")
            switch key {
                case "DTSTART":
                    startTime = dateFormatter.date(from: value)
                case "DTEND":
                    endTime = dateFormatter.date(from: value)
                case "SUMMARY":
                    title = value
                case "DESCRIPTION":
                    description = value
                case "LOCATION":
                    location = value
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

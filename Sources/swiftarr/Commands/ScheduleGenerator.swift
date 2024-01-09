import Foundation
import Vapor

func generateSchedule(startDate: Date, length: Int) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    
    // Function to generate a random UID
    func generateUID() -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in characters.randomElement()! })
    }
    
    // Print BEGIN:VCALENDAR only once before the first event
    let calHeaderString = """
BEGIN:VCALENDAR
VERSION:2.0
X-WR-CALNAME:JoCo Cruise Generated Schedule
X-WR-CALDESC:Event Calendar
METHOD:PUBLISH
CALSCALE:GREGORIAN
PRODID:-//Sched.com JoCo Cruise Generated Schedule//EN
X-WR-TIMEZONE:UTC
"""
    print(calHeaderString)
    
    for day in 0..<length {
        // Calculate date for the current day
        guard let currentDay = Calendar.current.date(byAdding: .day, value: day, to: startDate) else {
            fatalError("Error in date calculation.")
        }
        
        // Generate hourly events between 10AM and 4PM
        for hour in 10..<17 {
            let startTime = String(format: "%02d:00", hour)
            let endTime = String(format: "%02d:00", hour + 1)
            let summary = "Day \(day + 1) at \(hour)00"
            let description = "Event for Day \(day + 1) at \(hour)00"
            
            printEvent(date: currentDay, startTime: startTime, endTime: endTime, summary: summary, description: description, location: "", categories: "", uid: generateUID())
        }

        // Red Team Dinner
        printEvent(date: currentDay, startTime: "17:00", endTime: "19:00", summary: "Red Team Dinner", description: "Dinner for Red Team", location: "Dining Room", categories: "", uid: generateUID())

        // Gold Team Show
        printEvent(date: currentDay, startTime: "17:00", endTime: "19:00", summary: "Gold Team Show", description: "Show for Gold Team", location: "Main Stage", categories: "MAIN CONCERT", uid: generateUID())

        // Gold Team Dinner
        printEvent(date: currentDay, startTime: "19:30", endTime: "21:30", summary: "Gold Team Dinner", description: "Dinner for Gold Team", location: "Dining Room", categories: "", uid: generateUID())

        // Red Team Show
        printEvent(date: currentDay, startTime: "19:30", endTime: "21:30", summary: "Red Team Show", description: "Show for Red Team", location: "Main Stage", categories: "MAIN CONCERT", uid: generateUID())

        // Morning Announcements
        printEvent(date: currentDay, startTime: "10:00", endTime: "10:15", summary: "Morning Announcements", description: "Daily morning announcements", location: "", categories: "", uid: generateUID())

        // Happy Hour
        printEvent(date: currentDay, startTime: "16:00", endTime: "17:00", summary: "Happy Hour", description: "Happy Hour at Ocean Bar", location: "Ocean Bar", categories: "", uid: generateUID())
    }
    
    // Print END:VCALENDAR only once after the last event
    print("END:VCALENDAR")
}

// Function to print events in ICS format
func printEvent(date: Date, startTime: String, endTime: String, summary: String, description: String, location: String, categories: String, uid: String) {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

    let dtstamp = dateFormatter.string(from: Date())
    let dtstart = dateFormatter.string(from: date.addingTimeInterval(TimeInterval(startTime.prefix(2))! * 3600 + TimeInterval(startTime.suffix(2))! * 60))
    let dtend = dateFormatter.string(from: date.addingTimeInterval(TimeInterval(endTime.prefix(2))! * 3600 + TimeInterval(endTime.suffix(2))! * 60))

    let icsString = """
BEGIN:VEVENT
DTSTAMP:\(dtstamp)
DTSTART:\(dtstart)
DTEND:\(dtend)
SUMMARY:\(summary)
DESCRIPTION:\(description)
CATEGORIES:\(categories)
LOCATION:\(location)
SEQUENCE:0
UID:\(uid)
URL:https://twitarr.com/\(uid)
END:VEVENT
"""
    print(icsString)
}

struct GenerateScheduleCommand: AsyncCommand {
    struct Signature: CommandSignature { }

    var help: String {
"""
Generates a dummy schedule based on the currently configured cruise start date and length. \
Intended to help craft test data during a non-standard sailing (like if you want to test \
what's going to happen right NowTM).
"""
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        generateSchedule(startDate: Settings.shared.cruiseStartDate(), length: Settings.shared.cruiseLengthInDays)
    }
}
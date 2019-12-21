import Foundation
import Vapor

extension RouteCollection {
    
    /// Transforms a string that might represent a date (either a `Double` or an ISO 8601
    /// representation) into a `Date`, if possible.
    ///
    /// - Note: The representation is expected to be either a string literal `Double`, or a
    ///   string in UTC `yyyy-MM-dd'T'HH:mm:ssZ` format.
    ///
    /// - Parameter string: The string to be transformed.
    /// - Returns: A `Date` if the conversion was successful, otherwise `nil`.
    static func dateFromParameter(string: String) -> Date? {
        var date: Date?
        if let timeInterval = TimeInterval(string) {
            date = Date(timeIntervalSince1970: timeInterval)
        } else {
            if #available(OSX 10.12, *) {
                if let dateFromISO8601 = ISO8601DateFormatter().date(from: string) {
                    date = dateFromISO8601
                }
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                if let dateFromDateFormatter = dateFormatter.date(from: string) {
                    date = dateFromDateFormatter
                }
            }
        }
        return date
    }
}

extension CharacterSet {
    /// Defines a character set containing characters other than alphanumerics that are allowed
    /// in a username.
    static var usernameSeparators: CharacterSet {
        var separatorChars: CharacterSet = .init()
        separatorChars.insert(charactersIn: "-.+_")
        return separatorChars
    }
}

extension CharacterSet {
    /// Defines a character set containing characters that might delineate hashtags or
    /// usernames within text content.
    static var contentSeparators: CharacterSet {
        var separatorChars: CharacterSet = .init()
        separatorChars.insert(charactersIn: ".,;:!?")
        return separatorChars
    }
}

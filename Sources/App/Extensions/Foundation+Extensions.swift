import Foundation

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

@available(OSX 10.13, *)
extension ISO8601DateFormatter {
    convenience init(_ formatOptions: Options, timeZone: TimeZone? = TimeZone(secondsFromGMT: 0)) {
        self.init()
        self.formatOptions = formatOptions
        self.timeZone = timeZone
    }
}

@available(OSX 10.13, *)
extension Formatter {
    static let iso8601ms = ISO8601DateFormatter([.withInternetDateTime, .withFractionalSeconds])
}

@available(OSX 10.13, *)
extension Date {
    var iso8601ms: String {
        return Formatter.iso8601ms.string(from: self)
    }
}

@available(OSX 10.13, *)
extension String {
    var iso8601ms: Date? {
        return Formatter.iso8601ms.date(from: self)
    }
}

@available(OSX 10.13, *)
extension JSONDecoder.DateDecodingStrategy {
    static let iso8601ms = custom {
        let container = try $0.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = Formatter.iso8601ms.date(from: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "invalid format: " + string)
        }
        return date
    }
}

@available(OSX 10.13, *)
extension JSONEncoder.DateEncodingStrategy {
    static let iso8601ms = custom {
        var container = $1.singleValueContainer()
        try container.encode(Formatter.iso8601ms.string(from: $0))
    }
}

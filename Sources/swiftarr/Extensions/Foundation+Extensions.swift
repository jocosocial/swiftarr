import Foundation
import Redis

let usernameSeparatorString: String = "-.+_"
extension CharacterSet {
	/// Defines a character set containing characters other than alphanumerics that are allowed
	/// in a username. However, these characters cannot be at the start or end of a username.
	static var usernameSeparators: CharacterSet {
		var separatorChars: CharacterSet = .init()
		separatorChars.insert(charactersIn: usernameSeparatorString)
		return separatorChars
	}

	static var validUsernameChars: CharacterSet {
		var usernameChars: CharacterSet = .init()
		usernameChars.insert(charactersIn: usernameSeparatorString)
		usernameChars.formUnion(.alphanumerics)
		return usernameChars
	}

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
	/// Convenience initializer that defaults to UTC.
	///
	/// - Parameters:
	///   - formatOptions: `ISO8601DateFormater.Options` array to pass to the initialization.
	///   - timeZone: The time zone for representations, defaults to UTC.
	/// - Returns: An initialized `ISO8601DateFormatter`.
	convenience init(_ formatOptions: Options, timeZone: TimeZone? = TimeZone(identifier: "GMT")) {
		self.init()
		self.formatOptions = formatOptions
		self.timeZone = timeZone
	}
}

@available(OSX 10.13, *)
extension Formatter {
	/// Abstract helper for formatter initialization.
	static let iso8601ms = ISO8601DateFormatter([.withInternetDateTime, .withFractionalSeconds])
}

@available(OSX 10.13, *)
extension Date {
	/// Returns an iso8601 string representation with milliseconds.
	var iso8601ms: String {
		return Formatter.iso8601ms.string(from: self)
	}
}

@available(OSX 10.13, *)
extension String {
	/// Returns a `Date?` from an iso8601 string representation with milliseconds.
	var iso8601ms: Date? {
		return Formatter.iso8601ms.date(from: self)
	}
}

@available(OSX 10.13, *)
extension JSONDecoder.DateDecodingStrategy {
	/// Custom decoding strategy for iso8601 strings with milliseconds.
	static let iso8601ms = custom {
		let container = try $0.singleValueContainer()
		let string = try container.decode(String.self)
		guard let date = Formatter.iso8601ms.date(from: string) else {
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "invalid format: " + string
			)
		}
		return date
	}
}

@available(OSX 10.13, *)
extension JSONEncoder.DateEncodingStrategy {
	/// Custom encoding strategy for iso8601 strings with milliseconds.
	static let iso8601ms = custom {
		var container = $1.singleValueContainer()
		try container.encode(Formatter.iso8601ms.string(from: $0))
	}
}

extension Bool: @retroactive RESPValueConvertible {
	public init?(fromRESP value: RESPValue) {
		self = value.int != 0
	}

	public func convertedToRESPValue() -> RESPValue {
		return RESPValue(from: self == true ? 1 : 0)
	}
}

extension UUID: @retroactive RESPValueConvertible {
	public init?(fromRESP value: RESPValue) {
		self.init(uuidString: value.string!)
	}

	/// Creates a `RESPValue` representation of the conforming type's value.
	public func convertedToRESPValue() -> RESPValue {
		return RESPValue(from: self.uuidString)
	}

}

// Why oh why doesn't foundation already have this? This lets you do
// 15.clamped(to: 0...5), for example. An open range variant of this is problematic,
// best not to do it.
extension Comparable {
	func clamped(to limits: ClosedRange<Self>) -> Self {
		return max(limits.lowerBound, min(self, limits.upperBound))
	}
}

// Another thing Foundation ought to have. String(substring) requires a non-optional substring.
// let x: String? = substring?.string -- uses chaining to allow an optional substring to be converted into an optional String.
extension Substring {
	var string: String {
		String(self)
	}
}

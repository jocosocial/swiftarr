import Foundation
import Vapor

/// Names of clients that consume the Swiftarr client API. Used in the `DisabledFeature` struct.
/// Clients: Be sure to anticipate server values not listed here. 
enum SwiftarrClientApp: String, Content, CaseIterable {
	/// The website, but NOT the API layer
	case swiftarr
	
	/// Client apps that consume the Swiftarr API					
	case cruisemonkey
	case rainbowmonkey
	case kraken

	/// A feature disabled for `all` will be turned off at the API layer , meaning that calls to that area of the API will return errors. Clients should still attempt
	/// to use disabledFeatures to indicate the cause, rather than just displaying HTTP status errors.
	case all
	
	/// For clients use. Clients need to be prepared for additional values to be added serverside. Those new values get decoded as 'unknown'.
	case unknown
	
	/// When creating ourselves from a decoder, return .unknown for cases we're not prepared to handle.
	public init(from decoder: Decoder) throws {
		guard let rawValue = try? decoder.singleValueContainer().decode(String.self) else {
			self = .unknown
			return
		}
		self = .init(rawValue: rawValue) ?? .unknown
	}
}

/// Functional areas of the Swiftarr API. Used in the `DisabledFeature` struct.
/// Clients: Be sure to anticipate server values not listed here. 
enum SwiftarrFeature: String, Content, CaseIterable {
	case tweets
	case forums
	case seamail
	case schedule
	case friendlyfez
	case karaoke
	case gameslist
	case images
	case users
	case all
	
	/// For clients use. Clients need to be prepared for additional values to be added serverside. Those new values get decoded as 'unknown'.
	case unknown
	
	/// When creating ourselves from a decoder, return .unknown for cases we're not prepared to handle.
	public init(from decoder: Decoder) throws {
		guard let rawValue = try? decoder.singleValueContainer().decode(String.self) else {
			self = .unknown
			return
		}
		self = .init(rawValue: rawValue) ?? .unknown
	}
}


import Foundation
import Vapor

/// Names of clients that consume the Swiftarr client API. Used in the `SettingsAppFeaturePair` struct.
/// Clients: Be sure to anticipate server values not listed here.
public enum SwiftarrClientApp: String, Content, CaseIterable {
	/// The website, but NOT the API layer
	case swiftarr

	/// Client apps that consume the Swiftarr API
	case cruisemonkey
	case rainbowmonkey
	case kraken
	case tricordarr
	case tacobarr

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

/// Functional areas of the Swiftarr API. Used in the `SettingsAppFeaturePair` struct.
/// Clients: Be sure to anticipate server values not listed here.
public enum SwiftarrFeature: String, Content, CaseIterable {
	case tweets  // Tweet stream; perma-disabled
	case forums
	case seamail  // Chat. Includes group chats and 'open' chats that allow membership changes after creation
	case schedule
	case friendlyfez  // Looking For Group.
	case karaoke  // DB of songs available on Karaoke machine
	case microkaraoke  // Builds karaoke videos from people recording short song snippets on their phone.
	case gameslist  // DB of games available in gaming area
	case images  // Routes that retrieve user-uploaded images (/api/v3/image/**)
	case users  // User profile view/edit; block/mute mgmt, alertword/muteword mgmt, user role mgmt
	case phone  // User-to-user VOIP, voice data passes through server
	case directphone  // Also User-to-user VOIP, voice data goes directly phone to phone.
	case photostream  // Photos taken on the ship. Web UI cannot have photo upload, for THO reasons.
	case performers  // Official and Shadow performers; gallery, bio pages, links inside Event cells.
	case personalevents  // Personal event schedule

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

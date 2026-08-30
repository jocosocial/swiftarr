import Foundation
import VCard

/// Builds a vCard 3.0 string from a `User` profile for contact sharing.
///
/// Only land-based fields are included (name, email, home city, Discord, bio, photo).
/// Cruise-specific fields such as cabin number and dinner team are omitted.
final class VCardHelper {

	/// Serializes a vCard 3.0 string for `user`.
	///
	/// When `includeDetails` is false, only identity (username) is emitted — used for quarantined
	/// profiles and banned requesters. Empty optional fields are omitted. Cruise-specific fields
	/// (cabin number, dinner team, profile greeting) are never included.
	///
	/// Support for 4.0 which includes `PRONOUNS` seems to be limited in clients.
	/// I only looked at the MacOS Contacts app and it didn't bother reading it.
	///
	/// - Parameters:
	///   - user: The profile to export. Must have an ID.
	///   - includeDetails: If false, only username/UID/PRODID/REV are emitted.
	///   - photoData: Optional thumbnail bytes to embed as a `PHOTO;ENCODING=b` property.
	///   - photoFileExtension: File extension of `photoData` (e.g. `"jpg"`, `"png"`), used for `TYPE`.
	/// - Returns: A CRLF-delimited vCard 3.0 document.
	/// - Throws: If `user` has no ID.
	static func buildVCard(
		from user: User,
		includeDetails: Bool,
		photoData: Data? = nil,
		photoFileExtension: String? = nil
	) throws -> String {
		let userID = try user.requireID()
		let formattedName: String
		if includeDetails, let displayName = nonEmpty(user.displayName) {
			formattedName = displayName
		}
		else {
			formattedName = user.username
		}

		let (givenName, familyName) = structuredName(
			realName: includeDetails ? nonEmpty(user.realName) : nil,
			formattedName: formattedName
		)

		var builder = VCardBuilder(formattedName: formattedName, version: .v3_0)
			.nickname(user.username)
			.uid("urn:uuid:\(userID.uuidString)")
			.name(familyName: familyName, givenName: givenName)

		if includeDetails {
			if let email = nonEmpty(user.email) {
				builder = builder.email(email)
			}
			if let homeLocation = nonEmpty(user.homeLocation) {
				builder = builder.address(VCardAddressBuilder().locality(homeLocation).build())
			}
			if let note = noteText(from: user) {
				builder = builder.note(note)
			}
		}

		var vcard = builder.build()
		vcard.productId = "-//Twitarr//EN"
		vcard.revision = user.profileUpdatedAt

		if includeDetails, let discord = nonEmpty(user.discordUsername) {
			vcard.instantMessaging = ["Discord:\(discord)"]
		}

		if includeDetails, let photoData, !photoData.isEmpty {
			let type = photoType(fromFileExtension: photoFileExtension)
			vcard.properties.append(
				VProperty(
					name: VCardPropertyName.photo,
					value: photoData.base64EncodedString(),
					parameters: [
						VCardParameterName.encoding: "b",
						VCardParameterName.type: type,
					]
				)
			)
		}

		let options = VCardSerializer.SerializationOptions(
			lineLength: 75,
			sortProperties: true,
			includeOptionalProperties: true,
			validateBeforeSerializing: false,
			version: .v3_0
		)
		return try VCardSerializer(options: options).serialize(vcard)
	}

	/// Maps an image file extension to a vCard 3.0 `PHOTO` TYPE parameter.
	///
	/// - Parameter ext: A file extension such as `"jpg"` or `"png"`. Case-insensitive.
	/// - Returns: `"PNG"`, `"GIF"`, or `"JPEG"` (the default for unknown/nil extensions).
	static func photoType(fromFileExtension ext: String?) -> String {
		switch ext?.lowercased() {
		case "png": return "PNG"
		case "gif": return "GIF"
		default: return "JPEG"
		}
	}

	/// Returns `value` if it is non-nil and non-empty; otherwise `nil`.
	///
	/// - Parameter value: An optional string from a profile field.
	/// - Returns: The original string, or `nil` if missing or empty.
	private static func nonEmpty(_ value: String?) -> String? {
		guard let value, !value.isEmpty else { return nil }
		return value
	}

	/// Builds the vCard `NOTE` body from pronouns and the user's about text.
	///
	/// - Parameter user: The profile whose `preferredPronoun` and `about` fields to combine.
	/// - Returns: A note string (pronouns first, then about, separated by a newline), or `nil`
	///   if both fields are empty.
	private static func noteText(from user: User) -> String? {
		var parts: [String] = []
		if let pronoun = nonEmpty(user.preferredPronoun) {
			parts.append("Pronouns: \(pronoun)")
		}
		if let about = nonEmpty(user.about) {
			parts.append(about)
		}
		guard !parts.isEmpty else { return nil }
		return parts.joined(separator: "\n")
	}

	/// Splits a freeform real name into given/family parts for the vCard `N` property.
	///
	/// Uses the last space as the family-name boundary (e.g. `"Jane Doe"` → given `"Jane"`,
	/// family `"Doe"`). A single-token name, or a missing `realName`, is treated as given name only.
	///
	/// - Parameters:
	///   - realName: The user's `realName` field, or `nil` when details are hidden / unset.
	///   - formattedName: Fallback given name when `realName` is nil (display name or username).
	/// - Returns: A `(given, family)` pair. `family` is `nil` when it cannot be determined.
	private static func structuredName(realName: String?, formattedName: String) -> (given: String, family: String?) {
		guard let realName else {
			return (formattedName, nil)
		}
		if let space = realName.lastIndex(of: " "), space != realName.startIndex {
			let given = String(realName[..<space])
			let family = String(realName[realName.index(after: space)...])
			if !given.isEmpty, !family.isEmpty {
				return (given, family)
			}
		}
		return (realName, nil)
	}
}

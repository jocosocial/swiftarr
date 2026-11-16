import Foundation
import Vapor

/// Shared custom emoji metadata for website and API clients.
struct CustomEmojiData: Content {
	let reaction: String
	let name: String
	let imageURL: String
	/// Secret emoji render like any other, but clients must leave them out of pickers and emoji lists.
	let secret: Bool
}

/// Builds custom emoji metadata from the registry used to format posts.
///
/// This is the only definition of custom emoji: clients hold no list of their own, so the catalog
/// includes the secret ones too. Otherwise a client could not render a secret emoji someone typed.
enum ReactionEmojiCatalog {
	private static let labels = ["hottub": "hot tub", "joco": "Joco", "wangwang": "Wang Wang", "mbta": "MBTA"]
	static let custom =
		AddJocomojiTag.jocomoji.map { entry($0, secret: false) }
		+ AddJocomojiTag.secretJocomoji.map { entry($0, secret: true) }

	private static func entry(_ name: String, secret: Bool) -> CustomEmojiData {
		CustomEmojiData(reaction: ":\(name):", name: labels[name] ?? name.replacingOccurrences(of: "-", with: " "),
			imageURL: "/img/emoji/small/\(name).png", secret: secret)
	}
}

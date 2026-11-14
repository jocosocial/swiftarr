import Foundation
import Vapor

/// Shared custom emoji metadata for website and API clients.
struct CustomEmojiData: Content {
	let reaction: String
	let name: String
	let imageURL: String
}

/// Builds custom emoji metadata from the registry used to format posts.
enum ReactionEmojiCatalog {
	private static let labels = ["hottub": "hot tub", "joco": "Joco", "wangwang": "Wang Wang"]
	static let custom = AddJocomojiTag.jocomoji.map { name in
		CustomEmojiData(reaction: ":\(name):", name: labels[name] ?? name.replacingOccurrences(of: "-", with: " "),
			imageURL: "/img/emoji/small/\(name).png")
	}
}

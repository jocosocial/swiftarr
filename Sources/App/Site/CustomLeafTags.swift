//
//  CustomLeafTags.swift
//  App
//
//  Created by Chall Fry on 4/21/21.
//

import Vapor
import Leaf
import Foundation

/// This tag should output-sanitize all string values in self, replacing existing values.
/// For each string, it should encode the chars &<>"'/ into their HTML entities, preventing them from being interpreted as HTML
/// commands when Leaf inserts them into HTML Element contexts. For inserting into other contexts, other sanitizing should be done.
/// See https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
///
/// Usage: #elem(String) -> String
//struct ElementSanitizerTag: LeafTag {
//	static func sanitize(_ str: String) -> String {
//		var string = str
//		// This isn't ~optimized~, but I think it optimizes for the case where no changes need to be made to the string.
//		for ch in string.indices.reversed() {
//			switch string[ch] {
//			case "&": string.replaceSubrange(ch..<string.index(after:ch), with: "&amp;")
//			case "<": string.replaceSubrange(ch..<string.index(after:ch), with: "&lt;")
//			case ">": string.replaceSubrange(ch..<string.index(after:ch), with: "&gt;")
//			case "'": string.replaceSubrange(ch..<string.index(after:ch), with: "&#x27;")
//			case "\"": string.replaceSubrange(ch..<string.index(after:ch), with: "&quot;")
//			case "/": string.replaceSubrange(ch..<string.index(after:ch), with: "&#x2F;")
//			default: continue
//			}
//		}
//		
//        return string
//	}
//
//    func render(_ ctx: LeafContext) throws -> LeafData {
//        try ctx.requireParameterCount(1)
//		guard let string = ctx.parameters[0].string else {
//			return LeafData.string("")
//		}
//		return LeafData.string(ElementSanitizerTag.sanitize(string))
//    }
//}

/// Runs the element sanitizer on the given string, and then converts Jocomoji (specific string tags with the form :tag:)
/// into inline images. Generally, use this tag for user text that isn't posts.
///
/// Usage: #addJocomoji(String) -> String
struct AddJocomojiTag: UnsafeUnescapedLeafTag {
	static let jocomoji = [ "buffet", "die-ship", "die", "fez", "hottub", "joco", "pirate", "ship-front",
			"ship", "towel-monkey", "tropical-drink", "zombie" ]
			
	static func process(_ str: String) -> String {
		var string = str
		for emojiTag in AddJocomojiTag.jocomoji {
			string = string.replacingOccurrences(of: ":\(emojiTag):", with: "<img src=\"/img/emoji/small/\(emojiTag).png\" width=18 height=18>")
		}
		return string
	}

    func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(1)
		guard var string = ctx.parameters[0].string else {
			return LeafData.string("")
		}
		
		// Sanitize first to remove any existing tags. Also ensure the inline <img> tags we're about to add don't get nuked
		string = AddJocomojiTag.process(string.htmlEscaped())
		
		// Also convert newlines to HTML breaks.
		string = string.replacingOccurrences(of: "\r", with: "<br>")
		
		return LeafData.string(string)
	}
}

/// Runs the element sanitizer on the given string, converts Jocomoji (specific string tags with the form :tag:)
/// into inline images, and then converts substrings of the forum "@username"  and "#hashtag" into links.
///
/// Usage: #formatTwarrtText(String) -> String
/// Usage: #formatPostText(String) -> String
/// Usage: #formatFezText(String) -> String
/// Usage: #formatSeamailText(String) -> String
struct FormatPostTextTag: UnsafeUnescapedLeafTag {
	static var nameRefStartCharacterSet: CharacterSet {
		var x = CharacterSet()
		x.insert("@")
		return x
	}

    func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard var string = ctx.parameters[0].string else {
			return LeafData.string("")
		}
		
		// Sanitize, then add jocomoji.
		string = AddJocomojiTag.process(string.htmlEscaped())
		
		var words = string.split(separator: " ", omittingEmptySubsequences: false)
		words = words.map {
			if $0.hasPrefix("@") && $0.count <= 50 && $0.count >= 3 {
				let scalars = $0.unicodeScalars
				let firstValidUsernameIndex = scalars.index(scalars.startIndex, offsetBy: 1)
				var firstNonUsernameIndex = firstValidUsernameIndex
				// Move forward to the last char that's valid in a username
				while firstNonUsernameIndex < scalars.endIndex, CharacterSet.validUsernameChars.contains(scalars[firstNonUsernameIndex]) {
					scalars.formIndex(after: &firstNonUsernameIndex)		
				}
				// Separator chars can't be at the end. Move backward until we get a non-separator. This check fixes posts with 
				// constructions like "Hello, @admin." where the period ends a sentence. 
				while firstNonUsernameIndex > firstValidUsernameIndex, 
						CharacterSet.usernameSeparators.contains(scalars[scalars.index(before: firstNonUsernameIndex)]) {
					scalars.formIndex(before: &firstNonUsernameIndex)		
				}
				// After trimming, username must be >=2 chars, plus the @ sign makes 3.
				if scalars.distance(from: scalars.startIndex, to: firstNonUsernameIndex) >= 3,
						let name = String(scalars[firstValidUsernameIndex..<firstNonUsernameIndex])
						.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
					// We could in theory ask UserCache if the username actually exists. But that breaks separation
					// between site and API, and every other method of checking the username is async. Even then, we may not
					// have access to the Request from here.
					let restOfString = String(scalars[firstNonUsernameIndex...])
					return "<a class=\"link-primary\" href=\"/username/\(name)\">@\(name)</a>\(restOfString)"
				}
			}
			else if $0.hasPrefix("#") && $0.count <= 50 && $0.count >= 3 {
				let scalars = $0.unicodeScalars
				let firstValidHashtagIndex = scalars.index(scalars.startIndex, offsetBy: 1)
				var firstNonHashtagIndex = firstValidHashtagIndex
				// Move forward to the last char that's valid in a hashtag
				while firstNonHashtagIndex < scalars.endIndex, CharacterSet.alphanumerics.contains(scalars[firstNonHashtagIndex]) {
					scalars.formIndex(after: &firstNonHashtagIndex)		
				}
				// After trimming, hashtag must be >=2 chars, plus the # sign makes 3.
				if scalars.distance(from: scalars.startIndex, to: firstNonHashtagIndex) >= 3,
						let hashtag = String(scalars[firstValidHashtagIndex..<firstNonHashtagIndex])
						.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
					let restOfString = String(scalars[firstNonHashtagIndex...])
					var searchHref: String
					switch usage {
					case .twarrt: searchHref = "/tweets?hashtag=\(hashtag)"
					case .forumpost: searchHref = "/forumpost/search?hashtag=\(hashtag)"
					case .fez: searchHref = "/tweets?hashtag=\(hashtag)"
					case .seamail: searchHref = "/tweets?hashtag=\(hashtag)"
					}
					return "<a class=\"link-primary\" href=\"\(searchHref)\">#\(hashtag)</a>\(restOfString)"
				}
			}
			return $0
		}
		string = words.joined(separator: " ")
						
		// Also convert newlines to HTML breaks.
		string = string.replacingOccurrences(of: "\r\n", with: "<br>")
		string = string.replacingOccurrences(of: "\r", with: "<br>")
		string = string.replacingOccurrences(of: "\n", with: "<br>")
		
		return LeafData.string(string)
    }
    
    enum Usage {
    	case twarrt
    	case forumpost
    	case fez
    	case seamail
    }
    let usage: Usage
    init(_ forUsage: Usage) {
    	usage = forUsage
    }
}

/// Turns a Date string into a relative date string. Argument is a ISO8601 formatted Date, or what JSON encoding 
/// does to Date values. Output is a string giving a relative time in the past (from now) indicating the approximate time of the Date.
///
///	Output is constrained to a single element. e.g: "3 hours ago", "1 day ago", "5 minutes ago"
///
/// Usage in Leaf templates: #relativeTime(dateValue) -> String
struct RelativeTimeTag: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(1)
		guard let dateStr = ctx.parameters[0].string, let ti = TimeInterval(dateStr) else {
			return LeafData.string("")
		}
		let date = Date(timeIntervalSince1970: ti)
		if date.timeIntervalSinceNow > -1.0 {
			return "a second ago"
		}
		
		// If the date is Date.distantPast
		let daySecs = 60 * 60 * 24
		if date.timeIntervalSinceNow < Double(0 - daySecs * 365 * 100) {
			return ""
		}
		
		let hour = 60.0 * 60.0
		let day = hour * 24.0
		let month = day * 30.0
		let year = day * 365.0
		let interval = Date().timeIntervalSince(date)
		
		// Initially I'd just used DateComponentsFormatter to produce human-readable relative time strings. 
		// However, swift-corelibs-foundation doesn't support DateComponentsFormatter as yet, which means Linux builds fail.
		switch interval {
			case 0..<1: return "just now"
			case 1..<60: let secs = Int(interval); return LeafData.string("\(secs) second\(secs == 1 ? "" : "s") ago")
			case 60..<hour: let mins = Int(interval / 60.0); return LeafData.string("\(mins) minute\(mins == 1 ? "" : "s") ago")
			case hour..<day: let hours = Int(interval / hour); return LeafData.string("\(hours) hour\(hours == 1 ? "" : "s") ago")
			case day..<month: let days = Int(interval / day); return LeafData.string("\(days) day\(days == 1 ? "" : "s") ago")
			case month..<year: let months = Int(interval / month); return LeafData.string("\(months) month\(months == 1 ? "" : "s") ago")
			case year..<year * 10: let years = Int(interval / year); return LeafData.string("\(years) year\(years == 1 ? "" : "s") ago")
			default: return "some time ago"
		}
	}
}

/// Returns a string descibing when an event is taking place. Shows both the start and end time.
/// 
/// Usage in Leaf templates:: #eventTime(startTime, endTime) -> String
struct EventTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(2)
		guard let startTimeDouble = ctx.parameters[0].double, let endTimeDouble = ctx.parameters[1].double else {
            throw "Leaf: Unable to convert parameter to double for date"
		}

		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.timeZone = TimeZone.autoupdatingCurrent
		var timeString = dateFormatter.string(from: Date(timeIntervalSince1970: startTimeDouble))
		dateFormatter.dateStyle = .none
		timeString.append(" - \(dateFormatter.string(from: Date(timeIntervalSince1970: endTimeDouble)))")
		return LeafData.string(timeString)
	}
}

/// Turns a Date into a indexed day of the cruise, with embarkation day being day 0. Used to get the day on which an event happens.
/// This code counts ''days' as starting/ending at 3AM instead of midnight, as there are often after-midnight events but rarely 3AM events.
///
/// Usage: #cruiseDayIndex(date)  returns 0...8
struct CruiseDayIndexTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(1)
		guard let startTimeDouble = ctx.parameters[0].double else {
            throw "Leaf: Unable to convert parameter to double for date"
		}
		let difference = Date(timeIntervalSince1970: startTimeDouble).timeIntervalSince(Settings.shared.cruiseStartDate) - 3600 * 3
		let dayIndex = String(Int(floor(difference / (3600.0 * 24.0))))
		return LeafData.string(dayIndex)
	}
}

/// Inserts an <img> tag for the given user's avatar image. Presents a default image if the user doesn't have an image.
/// Note: If we implement identicons at the API level, users will always have images, and the 'generic user' image here is just a fallback.
///
/// First parameter is the UserHeader, second optional parameter is the size of the <img> to produce. This tag will select the best size image to reference
/// based on the size of  the image tag it is being placed in. Only produces square image views.
///
/// Usage: #avatar(userHeader), #avatar(userHeader, 800)
struct AvatarTag: UnsafeUnescapedLeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
		var imgSize = 40
		if ctx.parameters.count > 1, let tempSize = ctx.parameters[1].int {
			imgSize = tempSize
		}
		guard ctx.parameters.count >= 1, let userHeader = ctx.parameters[0].dictionary,
				let userID = userHeader["userID"]?.string else {
			throw "Leaf: avatarTag tag unable to get user header."
		}
		let imgLoadSize = imgSize > 100 ? "full" : "thumb"
		var imagePath = "/api/v3/image/user/identicon/\(userID)"
		if let customImage = userHeader["userImage"]?.string {
			imagePath = "/api/v3/image/\(imgLoadSize)/\(customImage)"
		}
		return LeafData.string("<img src=\"\(imagePath)\" width=\(imgSize) height=\(imgSize) alt=\"Avatar\">")
	}
}

/// Inserts an <a> tag with the given user's display name and username, linking to the user's profile page. As an UnsafeUnescaped tag, needs to
/// sanitize user-provided text itself.
///
/// Usage: #userByline(userHeader)
/// Or: #userByline(userHeader, "css-class") to style the link
/// Or: #userByline(userHeader, "short") to display a shorter link (only the username, no displayname). 
/// Or: #userByline(userHeader, "nolink") to display the username and displayname, without a link
struct UserBylineTag: UnsafeUnescapedLeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count >= 1, let userHeader = ctx.parameters[0].dictionary,
			  let userID = userHeader["userID"]?.string,
			  let username = userHeader["username"]?.string?.htmlEscaped() else {
			throw "Leaf: userByline tag unable to get user header."
		}
		var styling = ""
		if ctx.parameters.count >= 2, let newStyle = ctx.parameters[1].string {
			styling = newStyle
		}
		if styling == "nolink" {
			let displayName = userHeader["displayName"]?.string?.htmlEscaped() ?? ""
			return LeafData.string("<b>\(displayName)</b> @\(username)")
		} else if styling != "short", let displayName = userHeader["displayName"]?.string?.htmlEscaped() {
			return LeafData.string("<a class=\"\(styling)\" href=\"/user/\(userID)\"><b>\(displayName)</b> @\(username)</a>")
		}
		else {
			return LeafData.string("<a class=\"\(styling)\" href=\"/user/\(userID)\">@\(username)</a>")
		}
	}
}

/// Prints a float with 2 decimal precision e.g. "5.76". Used by game ratings and game complexity.
///
/// Usage: #gameRating(float)
struct GameRatingTag: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count == 1, let value = ctx.parameters[0].double else {
			throw "Leaf: gameRating tag unable to get float value."
		}
		let str = String(format: "%.2f", value)
		return LeafData.string(str)
	}
}


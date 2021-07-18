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
struct ElementSanitizerTag: LeafTag {
	static func sanitize(_ str: String) -> String {
		var string = str
		// This isn't ~optimized~, but I think it optimizes for the case where no changes need to be made to the string.
		for ch in string.indices.reversed() {
			switch string[ch] {
			case "&": string.replaceSubrange(ch..<string.index(after:ch), with: "&amp;")
			case "<": string.replaceSubrange(ch..<string.index(after:ch), with: "&lt;")
			case ">": string.replaceSubrange(ch..<string.index(after:ch), with: "&gt;")
			case "'": string.replaceSubrange(ch..<string.index(after:ch), with: "&#x27;")
			case "\"": string.replaceSubrange(ch..<string.index(after:ch), with: "&quot;")
			case "/": string.replaceSubrange(ch..<string.index(after:ch), with: "&#x2F;")
			default: continue
			}
		}
		
        return string
	}

    func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(1)
		guard let string = ctx.parameters[0].string else {
			return LeafData.string("")
		}
		return LeafData.string(ElementSanitizerTag.sanitize(string))
    }
}

/// Runs the element sanitizer on the given string, and then converts Jocomoji (specific string tags with the form :tag:)
/// into inline images.
///
/// Usage: #addJocomoji(String) -> String
struct AddJocomojiTag: LeafTag {
	static let jocomoji = [ "buffet", "die-ship", "die", "fez", "hottub", "joco", "pirate", "ship-front",
			"ship", "towel-monkey", "tropical-drink", "zombie" ]

    func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(1)
		guard var string = ctx.parameters[0].string else {
			return LeafData.string("")
		}
		
		// Sanitize first to remove any existing tags. Also ensure the inline <img> tags we're about to add don't get nuked
		string = ElementSanitizerTag.sanitize(string)
		for emojiTag in AddJocomojiTag.jocomoji {
			string = string.replacingOccurrences(of: ":\(emojiTag):", with: "<img src=\"/img/emoji/small/\(emojiTag).png\" width=18 height=18>")
		}
		
		// Also convert newlines to HTML breaks.
		string = string.replacingOccurrences(of: "\r", with: "<br>")
		
		return LeafData.string(string)
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
		let month = day * 31.0
		
		// Fix for a really annoying DateFormatter bug. For successive allowedUnits A, B, and C, if the interval
		// is > 1B - .5A but < 1B, DateFormatter will return "0 C" instead of "1 B". 
		var interval = Date().timeIntervalSince(date)
		switch interval {
		case (hour - 30.0)...hour: interval = hour			// = 1hr for everything above 59.5 minutes
		case (day - hour / 2)...day: interval = day			// = 1day for everything above 23.5 hours
		case (month - day / 2)...month: interval = month	// = 1mo for everything above 30.5 days
		default: break
		}
		
		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .full
		formatter.maximumUnitCount = 1
	//	formatter.allowsFractionalUnits = true
		formatter.allowedUnits = [.second, .minute, .hour, .day, .month, .year]
		if let relativeTimeStr = formatter.string(from: interval) {
			let resultStr = relativeTimeStr + " ago"
			return LeafData.string(resultStr)
		}
		return "some time ago"
	}
}

/// Returns a string descibing when an event is taking place. Shows both the start and end time.
/// Usage in Leaf templates:: #eventTime(startTime, endTime) -> String
struct EventTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
        try ctx.requireParameterCount(2)
		guard let startTimeDouble = ctx.parameters[0].double, let endTimeDouble = ctx.parameters[1].double else {
            throw "Unable to convert parameter to double for date"
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

/// Inserts an <img> tag for the given user's avatar image. Presents a default image if the user doesn't have an image.
/// Note: If we implement identicons at the API level, users will always have images, and the 'generic user' image here is just a fallback.
///
/// First parameter is the file name of the image, second optional parameter is the size of the <img> to produce. This tag will select the best size image to reference
/// based on the size of  the image tag it is being placed in. Only produces square image views.
///
/// Useage: #avatar(imageFilename), #avatar(imageFilename, 800)
struct AvatarTag: LeafTag {
    func render(_ ctx: LeafContext) throws -> LeafData {
		var imgSize = 40
		if ctx.parameters.count > 1, let tempSize = ctx.parameters[1].int {
			imgSize = tempSize
		}
    	var imagePath = "/img/NoAvatarUser.png"
		if ctx.parameters.count > 0, let userImageString = ctx.parameters[0].string {
			let imgLoadSize = imgSize > 100 ? "full" : "thumb"
			imagePath = "/api/v3/image/\(imgLoadSize)/\(userImageString)"	
		}
		return LeafData.string("<img src=\"\(imagePath)\" width=\(imgSize) height=\(imgSize) alt=\"Avatar\">")
	}
}

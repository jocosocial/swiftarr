//
//  CustomLeafTags.swift
//  App
//
//  Created by Chall Fry on 4/21/21.
//

import Vapor
import Leaf
import Foundation

// This tag should output-sanitize all string values in self, replacing existing values.
// For each string, it should encode the chars &<>"'/ into their HTML entities, preventing them from being interpreted as HTML
// commands when Leaf inserts them into HTML Element contexts. For inserting into other contexts, other sanitizing should be done.
// See https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
//
// Usage: elem(String) -> String
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
			string = string.replacingOccurrences(of: ":\(emojiTag):", with: "<img src=\"img/emoji/small/\(emojiTag).png\" width=18 height=18>")
		}
		
		// Also convert newlines to HTML breaks.
		string = string.replacingOccurrences(of: "\r", with: "<br>")
		
		return LeafData.string(string)
	}
}

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
		if date.timeIntervalSinceNow < Double(0 - 60 * 60 * 24 * 365 * 100) {
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


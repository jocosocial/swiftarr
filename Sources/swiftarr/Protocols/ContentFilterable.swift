import Redis
import Vapor

/// A `Protocol` used to provide convenience functions for Models that return content that is filterable.
/// Adopting the protocol requires implmenting `contentTextStrings()` which returns an array of 'content'
/// strings that should be scanned in a filter operation.
protocol ContentFilterable {
	func contentTextStrings() -> [String]
}

extension ContentFilterable {

	/// Checks if a `ContentFilterable` contains any of the provided array of muting strings, returning true if it does
	///
	/// - Parameters:
	///   - mutewords: The list of strings on which to filter the post.
	/// - Returns: TRUE if the post contains a muting string.
	func containsMutewords(using mutewords: [String]) -> Bool {
		let contentStrings = self.contentTextStrings()
		for word in mutewords {
			for string in contentStrings {
				if string.range(of: word, options: .caseInsensitive) != nil {
					return true
				}
			}
		}
		return false
	}

	/// Checks if a `ContentFilterable` contains any of the provided array of strings, returning
	/// `nil` if it does, else returning `self`. Returns `self` if the array of search strings is empty or `nil`.
	///
	/// - Parameters:
	///   - words: The list of strings on which to filter the post.
	/// - Returns: The provided object, or `nil` if the object's text fields contain a string.
	func filterOutStrings(using words: [String]?) -> Self? {
		let contentStrings = self.contentTextStrings()
		if let mutewords = words {
			for word in mutewords {
				for string in contentStrings {
					if string.range(of: word, options: .caseInsensitive) != nil {
						return nil
					}
				}
			}
		}
		return self
	}

	/// Returns (removes, adds) which are (importantly!) disjoint sets of usernames @mentioned in the
	/// reciever or in the editedString. Used to update mention counts for mentioned users.
	/// A user @mentioned multiple times in the same ContentFilterable only counts once.
	func getMentionsDiffs(editedString: String?, isCreate: Bool) -> (Set<String>, Set<String>) {
		var oldMentions = Set<String>()
		var newMentions = Set<String>()
		self.contentTextStrings()
			.forEach {
				oldMentions.formUnion(Self.getMentionsSet(for: $0))
			}
		if let editedStr = editedString {
			newMentions = Self.getMentionsSet(for: editedStr)
		}
		let subtracts = oldMentions.subtracting(newMentions)
		let adds = newMentions.subtracting(oldMentions)
		if isCreate {
			return (adds, subtracts)
		}
		else {
			return (subtracts, adds)
		}
	}

	func getAlertwordDiffs(editedString: String?, isCreate: Bool) -> (Set<String>, Set<String>) {
		var oldAlertWords = Set<String>()
		var newAlertWords = Set<String>()
		self.contentTextStrings()
			.forEach {
				oldAlertWords.formUnion(Self.buildCleanWordsArray($0))
			}
		if let editedStr = editedString {
			newAlertWords = Self.buildCleanWordsArray(editedStr)
		}
		let subtracts = oldAlertWords.subtracting(newAlertWords)
		let adds = newAlertWords.subtracting(oldAlertWords)
		if isCreate {
			return (adds, subtracts)
		}
		else {
			return (subtracts, adds)
		}
	}

	/// Retuns all discovered hashtags in all text strings of the content.
	func getHashtags() -> Set<String> {
		var hashtags: Set<String> = Set()
		self.contentTextStrings()
			.forEach { string in
				let words = string.split(separator: " ", omittingEmptySubsequences: true)
				for word in words {
					if !word.hasPrefix("#") || word.count < 3 || word.count >= 50 {
						continue
					}
					let scalars = word.unicodeScalars
					let firstValidHashtagIndex = scalars.index(scalars.startIndex, offsetBy: 1)
					var firstNonHashtagIndex = firstValidHashtagIndex
					// Move forward to the last char that's valid in a hashtag
					while firstNonHashtagIndex < scalars.endIndex,
						CharacterSet.alphanumerics.contains(scalars[firstNonHashtagIndex])
					{
						scalars.formIndex(after: &firstNonHashtagIndex)
					}
					// After trimming, hashtag must be >=2 chars, plus the # sign makes 3.
					if scalars.distance(from: scalars.startIndex, to: firstNonHashtagIndex) >= 3 {
						let hashtag = String(scalars[firstValidHashtagIndex..<firstNonHashtagIndex])
						hashtags.insert(hashtag)
					}
				}
			}
		return hashtags
	}

	static func buildCleanWordsArray(_ str: String) -> Set<String> {
		let words = Set(
			str.lowercased().filter { $0.isLetter || $0.isWhitespace }.split(separator: " ").map { String($0) }
		)
		return words
	}

	/// Returns a set of possible usernames found as @mentions in the given string.
	/// Does not check whether the @mentions are valid users.
	/// The regex looks for:
	///	- Start-of-string or whitespace,
	/// - '@'
	/// - 2...50 characters that are in the set of valid Username chars
	///	- Trailing separator characters are excluded from the mention (such as ending with punctuation)
	/// - A non-Username char or end-of-string.
	/// ChatGPT turned this from a mega string processing nightmare into an unreadable regex!
	/// "Software"
	///
	/// Example: "@heidi likes @sam" -> ["heidi", "sam"]
	///
	static func getMentionsSet(for string: String) -> Set<String> {
		let pattern = "(?<!\\S)@([A-Za-z0-9]+(?:[-.+_][A-Za-z0-9]+)*)"
		do {
			let regex = try NSRegularExpression(pattern: pattern, options: [])
			let matches = regex.matches(in: string, options: [], range: NSRange(location: 0, length: string.utf16.count))

			let usernames = matches.compactMap { match -> String? in
				let range = Range(match.range(at: 1), in: string)
				return range.map { String(string[$0]) }
			}.filter { $0.count >= 2 && $0.count <= 50 }
			return Set(usernames)
		} catch {
			return []
		}
	}

	/// Fluent queries can filter for strings in text fields, but @mentions require more specific filtering.
	/// This fn tests that the given username is @mentioned in the receiver's content. It's specifically looking
	/// for cases where one name is a substring of another.
	///
	/// Example: both @John and @John.Doe are users. Simple string search returns @John.Doe results in a search
	/// for @John.
	///
	/// Also, if a user is @mentioned at the end of a sentence, the period is a valid username char, but is not
	/// valid at the end of a username (must have a following alphanumeric).
	///
	/// - Parameter username: String of the username (including @) that we are attempting to match for.
	/// - Returns: A ContentFilterable (such as ForumPost or FezPost) if the username is found, else nil.
	///
	/// @TODO consider: https://www.swiftbysundell.com/articles/string-parsing-in-swift/
	///
	func filterForMention(of username: String) -> Self? {
		for contentString in contentTextStrings() {
			var searchRange: Range<String.Index> = contentString.startIndex..<contentString.endIndex
			while !searchRange.isEmpty,
				let foundRange = contentString.range(of: username, options: [.caseInsensitive], range: searchRange)
			{
				searchRange = foundRange.upperBound..<contentString.endIndex
				var pastNameIndex = foundRange.upperBound
				// This case checks if we matched the username at the end of the contentString.
				// Heads up the .endIndex is "past-the-end" and so pastNameIndex can be too, leading
				// to fun String index out of bounds exceptions. Since we've reset the searchRange
				// to the remaining contentString (which in this case should be "") we can offer
				// additional confirmation that we are at the end.
				// Example: "End of line @John"
				if pastNameIndex >= contentString.endIndex && contentString[searchRange] == "" {
					return self
				}
				while pastNameIndex < contentString.endIndex {
					// This case looks to see if the character after the foundRange string is not a valid username character.
					// It shouldn't be, indicating the conclusion of a mention and we should probably be responding that the
					// match was successful.
					// Example: "@John whats up", the pastNameindex character is the " " after "@John".
					if !CharacterSet.validUsernameChars.contains(contentString.unicodeScalars[pastNameIndex]) {
						return self
					}
					// Deal with usernames that are substrings of another.
					// Example: "@Johnothon whats up", the pastNameIndex character is the "o" after "@John" in "@Johnothon".
					// If the contentString contains a username with a seperator (such as "@John.Doe") this code skips ahead
					// to the contentString.formIndex() below which moves the pastNameIndex one character forward. In this example
					// that would be the "D" in "@John.Doe". We then loop again but looking at that "D" which triggers this case
					// via that next loop through. We break here because we have something resembling a match but need more
					// information before considering returning success.
					if CharacterSet.alphanumerics.contains(contentString.unicodeScalars[pastNameIndex]) {
						break
					}
					// This case covers when the mention is at the end of a post sentence that ends in a period.
					// .formIndex() implicitly updates the given index value, which at end of post means it should
					// be a ".".
					// Example: "This is with a dot @John."
					contentString.formIndex(after: &pastNameIndex)
					if pastNameIndex == contentString.endIndex {
						return self
					}
				}
			}
		}
		return nil
	}
}

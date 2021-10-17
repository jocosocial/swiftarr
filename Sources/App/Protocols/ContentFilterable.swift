import Vapor
import Redis

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
		self.contentTextStrings().forEach {
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
		self.contentTextStrings().forEach {
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
    
	static func buildCleanWordsArray(_ str: String) -> Set<String> {
		let words = Set(str.lowercased().filter { $0.isLetter || $0.isWhitespace }.split(separator: " ").map { String($0) })
		return words
	}

    /// Returns a set of possible usernames found as @mentions in the given string. Does not check whether the @mentions are valid users.
    /// The algorithm could probably reduced to a somewhat complicated regex, but here's what it looks for:
	///	- Start-of-string or whitespace,
	/// - '@'
	/// - 2...50 characters that are in the set of valid Username chars
	/// 	- The last char in the above string cannot be in the set of username separator chars
	/// - A non-Username char or end-of-string.
    static func getMentionsSet(for string: String) -> Set<String> {
		let words = string.split(separator: " ", omittingEmptySubsequences: true)
		let userMentions: [String] = words.compactMap {
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
				if scalars.distance(from: scalars.startIndex, to: firstNonUsernameIndex) >= 3 {
					let name = String(scalars[firstValidUsernameIndex..<firstNonUsernameIndex])
					return name
				}
			}
			return nil
		}
		let mentionSet = Set(userMentions)
		return mentionSet
    }
    
    /// Fluent queries can filter for strings in text fields, but @mentions require more specific filtering.
    /// This fn tests that the given username is @mentioned in the receiver's content. It's specifically looking for cases where one name is a substring of another.
	/// Example: both @John and @John.Doe are users. Simple string search returns @John.Doe results in a search for @John.
	/// Also, if a user is @mentioned at the end of a sentence, the period is a valid username char, but is not valid at the end of a username (must have a following alphanumeric).
    func filterForMention(of username: String) -> Self? {
		for contentString in contentTextStrings() {
			var searchRange: Range<String.Index> = contentString.startIndex..<contentString.endIndex
			while !searchRange.isEmpty, let foundRange = contentString.range(of: username, options: [.caseInsensitive], range: searchRange) { 
				searchRange = foundRange.upperBound..<contentString.endIndex
				var pastNameIndex = foundRange.upperBound
				while pastNameIndex < contentString.endIndex {
					if !CharacterSet.validUsernameChars.contains(contentString.unicodeScalars[pastNameIndex]) {
						return self
					}
					if CharacterSet.alphanumerics.contains(contentString.unicodeScalars[pastNameIndex]) {
						break
					}
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

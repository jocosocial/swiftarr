import Vapor
import Fluent

// MARK: - Functions

// events can be bookmarked
extension Event: UserBookmarkable {
    /// The barrel type for `Event` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .taggedEvent
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// events can be filtered by creator
extension Event: ContentFilterable {

    /// Checks if a `Event` contains any of the provided array of muting strings, returning true if it does
    ///
    /// - Parameters:
    ///   - mutewords: The list of strings on which to filter the post.
    /// - Returns: TRUE if the post contains a muting string.
    func containsMutewords(using mutewords: [String]) -> Bool {
        for word in mutewords {
            if self.title.range(of: word, options: .caseInsensitive) != nil ||
            		self.info.range(of: word, options: .caseInsensitive) != nil ||
            		self.location.range(of: word, options: .caseInsensitive) != nil {
                return true
            }
        }
        return false
    }
    
    /// Checks if a `Event` contains any of the provided array of muting strings, returning
    /// either the original twarrt or `nil` if there is a match.
    ///
    /// - Parameters:
    ///   - post: The `Event` to filter.
    ///   - mutewords: The list of strings on which to filter the post.
    ///   - req: The incoming `Request` on whose event loop this needs to run.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func filterMutewords(using mutewords: [String]?) -> Event? {
        if let mutewords = mutewords {
			for word in mutewords {
				if self.title.range(of: word, options: .caseInsensitive) != nil ||
						self.info.range(of: word, options: .caseInsensitive) != nil ||
						self.location.range(of: word, options: .caseInsensitive) != nil {
					return nil
				}
			}
		}
        return self
    }

}

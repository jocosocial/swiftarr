import Vapor
import Fluent

// MARK: - Functions

extension Event {
    /// Converts an `Event` model to a version omitting data that is of no interest to a user.
    func convertToData(withFavorited tagged: Bool) throws -> EventData {
        return try EventData(
            eventID: self.requireID(),
            title: self.title,
            description: self.info,
            startTime: self.startTime,
            endTime: self.endTime,
            location: self.location,
            eventType: self.eventType.label,
            forum: self.$forum.id,
            isFavorite: tagged
        )
    }
}

extension EventLoopFuture where Value: Event {
    /// Converts a `Future<Event>` to a `Future<EventData>`. This extension provides the
    /// convenience of simply using `event.convertToData()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData(withFavorited tagged: Bool) throws -> EventLoopFuture<EventData> {
        return self.flatMapThrowing {
            (event) in
            return try event.convertToData(withFavorited: tagged)
        }
    }
}

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

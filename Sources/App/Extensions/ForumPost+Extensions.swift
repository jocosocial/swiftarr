import Vapor
import Fluent

// MARK: - Functions

// posts can be bookmarked
extension ForumPost: UserBookmarkable {
    /// The barrel type for `ForumPost` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .bookmarkedPost
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// posts can be filtered by author and content
extension ForumPost: ContentFilterable {
    /// Checks if a `ForumPost` contains any of the provided array of muting strings, returning true if it does
    ///
    /// - Parameters:
    ///   - mutewords: The list of strings on which to filter the post.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func containsMutewords(using mutewords: [String]) -> Bool {
        for word in mutewords {
            if self.text.range(of: word, options: .caseInsensitive) != nil {
                return true
            }
        }
        return false
    }
    
    /// Checks if a `Twarrt` contains any of the provided array of muting strings, returning
    /// either the original twarrt or `nil` if there is a match.
    ///
    /// - Parameters:
    ///   - post: The `Event` to filter.
    ///   - mutewords: The list of strings on which to filter the post.
    ///   - req: The incoming `Request` on whose event loop this needs to run.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func filterMutewords(using mutewords: [String]?) -> ForumPost? {
        if let mutewords = mutewords {
			for word in mutewords {
				if self.text.range(of: word, options: .caseInsensitive) != nil {
					return nil
				}
			}
		}
        return self
    }
    
}

extension ForumPost: Reportable {
    /// The barrel type for `ForumPost` bookmarking.
	var reportType: ReportType {
        return .forumPost
    }
    
	func checkAutoQuarantine(reportCount: Int, on req: Request) -> EventLoopFuture<Void> {
		// quarantine if threshold is met
		if reportCount >= Settings.shared.postAutoQuarantineThreshold && !self.isReviewed {
			self.isQuarantined = true
			return self.save(on: req.db)
		}
		return req.eventLoop.future()
	}
}

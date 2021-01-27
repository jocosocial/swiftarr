import Vapor
import Fluent

// MARK: - Functions

extension ForumPost {
    /// Converts an `ForumPost` model to a version omitting data that not for public
    /// consumption.
    func convertToData(bookmarked: Bool, userLike: LikeType?, likeCount: Int) throws -> PostData {
        return try PostData(
            postID: self.requireID(),
            createdAt: self.createdAt ?? Date(),
            authorID: self.author.requireID(),
            text: self.isQuarantined ? "This post is under moderator review." : self.text,
            image: self.isQuarantined ? "" : self.image,
            isBookmarked: bookmarked,
            userLike: userLike,
            likeCount: likeCount
        )
    }
}

extension EventLoopFuture where Value: ForumPost {
    /// Converts a `Future<ForumPost>` to a `Future<PostData>`. This extension provides
    /// the convenience of simply using `post.convertToData()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData(bookmarked: Bool, userLike: LikeType?, likeCount: Int) -> EventLoopFuture<PostData> {
        return self.flatMapThrowing {
            (forumPost) in
            return try forumPost.convertToData(
                bookmarked: bookmarked,
                userLike: userLike,
                likeCount: likeCount
            )
        }
    }
}

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

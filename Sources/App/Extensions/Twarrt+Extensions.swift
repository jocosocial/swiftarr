import Vapor
import Fluent

// MARK: - Functions

extension Twarrt {
    /// Converts a `Twarrt` model to a version omitting data that is not for public consumption.
    func convertToData(author: UserHeader, bookmarked: Bool, userLike: LikeType?, likeCount: Int) throws -> TwarrtData {
        return try TwarrtData(
            twarrtID: self.requireID(),
            createdAt: self.createdAt ?? Date(),
            author: author,
            text: self.isQuarantined ? "This twarrt is under moderator review." : self.text,
            image: self.isQuarantined ? "" : self.image,
            replyToID: self.replyTo?.requireID(),
            isBookmarked: bookmarked,
            userLike: userLike,
            likeCount: likeCount
        )
    }
}

//extension EventLoopFuture where Value: Twarrt {
//    /// Converts a `EventLoopFuture<Twarrt>` to a `EventLoopFuture<TwarrtData>`. This extension provides
//    /// the convenience of simply using `twarrt.convertToData()` and allowing the compiler to
//    /// choose the appropriate version for the context.
//    func convertToData(bookmarked: Bool, userLike: LikeType?, likeCount: Int) -> EventLoopFuture<TwarrtData> {
//        return self.flatMapThrowing { (twarrt) in
//            return try twarrt.convertToData(
//                bookmarked: bookmarked,
//                userLike: userLike,
//                likeCount: likeCount
//            )
//        }
//    }
//}

// twarrts can be filtered by author and content
extension Twarrt: ContentFilterable {
    /// Checks if a `Twarrt` contains any of the provided array of muting strings, returning true if it does
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
    func filterMutewords(using mutewords: [String]?) -> Twarrt? {
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

// twarrts can be bookmarked
extension Twarrt: UserBookmarkable {
    /// The barrel type for `Twarrt` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .bookmarkedTwarrt
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// twarrts can be reported
extension Twarrt: Reportable {
    /// The barrel type for `ForumPost` bookmarking.
	var reportType: ReportType {
        return .twarrt
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

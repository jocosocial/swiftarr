import Vapor

extension PostContentData {
	func effectiveAuthor(actualAuthor: UserCacheData, on req: Request) -> UserCacheData {
		if actualAuthor.accessLevel.hasAccess(.moderator) {
			if postAsModerator, let modUser = req.userCache.getUser(username: "moderator") {
				return modUser
			}
			if postAsTwitarrTeam, let ttUser = req.userCache.getUser(username: "TwitarrTeam") {
				return ttUser
			}
		}
		return actualAuthor
	}
}

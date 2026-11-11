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
		// Authorization here is a role, not an access level (TwitarrTeam and above also qualify, as they can read the shared mailbox).
		if postAsCommunitySupport, actualAuthor.canAccessCommunitySupport,
			let csUser = PrivilegedUser.CommunitySupport.cachedUser(on: req)
		{
			return csUser
		}
		return actualAuthor
	}
}

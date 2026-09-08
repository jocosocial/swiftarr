import Vapor

/// Content-specific authorization rules for the reusable posting-as path.
enum AuthorableContentType {
	case announcement
}

/// Types that may author content as a privileged account via postAsUser.
protocol Authorable {
	/// Privileged username to author as, or nil/"self"/the caller's own username for the caller.
	var postAsUser: String? { get }

	/// Resolves the author for this request, enforcing the rules for the content type.
	func effectiveAuthor(on req: Request, for content: AuthorableContentType) throws -> UserCacheData
}

extension Authorable {
	func effectiveAuthor(on req: Request, for content: AuthorableContentType) throws -> UserCacheData {
		let caller = try req.auth.require(UserCacheData.self)
		guard let raw = postAsUser?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
			raw.caseInsensitiveCompare("self") != .orderedSame,
			raw.caseInsensitiveCompare(caller.username) != .orderedSame
		else { return caller }
		guard let target = PrivilegedUser(fromQueryParam: raw) else {
			throw Abort(.forbidden, reason: "Cannot post as '" + raw + "'.")
		}
		guard target.canPostAs(from: caller.accessLevel, for: content) else {
			throw Abort(.forbidden, reason: "Your account cannot post as @" + target.rawValue + ".")
		}
		guard let user = req.userCache.getUser(username: target.rawValue) else {
			throw Abort(.internalServerError, reason: "Cannot post as @" + target.rawValue + ".")
		}
		return user
	}
}

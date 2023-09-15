import Fluent
import Vapor

// MARK: - Functions

extension User {

	/// Returns a list of IDs of all accounts associated with the `User`. If user is a primary
	/// account (has no `.parentID`) it returns itself plus any sub-accounts. If user is a
	/// sub-account, it determines its parent, then returns the parent and all sub-accounts.
	///
	/// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on
	///   which the query must be run.
	/// - Returns: `[UUID]` containing all the user's associated IDs.
	func allAccountIDs(on db: Database) async throws -> [UUID] {
		let parID = try self.$parent.id ?? self.requireID()
		let users = try await User.query(on: db)
			.group(.or) { (or) in
				or.filter(\.$id == parID)
				or.filter(\.$parent.$id == parID)
			}
			.all()
		return try users.map { try $0.requireID() }
	}

	/// Returns an array of `User` whose first element is the primary account and the remaining elements
	/// are sub-accounts of the primary account.
	///
	/// - Parameter db: The incoming request `Container`, which provides the `EventLoop` on
	///   which the query must be run.
	/// - Returns: `[User]`
	func allAccounts(on db: Database) async throws -> [User] {
		let parentUser = (try await self.$parent.id == nil ? self : User.find(self.$parent.id, on: db)) ?? self
		let subAccounts = try await User.query(on: db).filter(\.$parent.$id == parentUser.requireID()).all()
		return [parentUser] + subAccounts
	}

	/// Returns the parent `User` of the user sending the request. If the requesting user has
	/// no parent, the user itself is returned.
	///
	/// - Parameter req: The incoming request `Container`, which provides reference to the
	///   sending user.
	func parentAccount(on req: Request) async throws -> User {
		if self.$parent.id == nil {
			return self
		}
		try await self.$parent.load(on: req.db)
		guard let parent = self.parent else {
			throw Abort(.internalServerError, reason: "parent not found")
		}
		return parent
	}

	/// Returns the ID of the parent account of the receiver. If the receiver has no parent, the receiver's ID is returned.
	///
	func parentAccountID() throws -> UUID {
		return try self.$parent.id ?? self.requireID()
	}

	func buildUserSearchString() {
		var builder = [String]()
		builder.append(displayName ?? "")
		builder.append(builder[0].isEmpty ? "@\(username)" : "(@\(username))")
		if let realName = realName {
			builder.append("- \(realName)")
		}
		userSearch = builder.joined(separator: " ").trimmingCharacters(in: .whitespaces)
		profileUpdatedAt = Date()
	}

	/// Ensures that either the receiver can edit/delete other users' content (that is, they're a moderator), or that
	/// they authored the content they're trying to modify/delete themselves, and still have rights to edit
	/// their own content (that is, they aren't banned/quarantined).
	func guardCanCreateContent(customErrorString: String = "user cannot modify this content") throws {
		if let quarantineEndDate = tempQuarantineUntil {
			guard Date() > quarantineEndDate else {
				throw Abort(.forbidden, reason: "User is temporarily quarantined; \(customErrorString)")
			}
		}
		guard accessLevel.canCreateContent() else {
			throw Abort(.forbidden, reason: customErrorString)
		}
	}

	/// Ensures that either the receiver can edit/delete other users' content (that is, they're a moderator), or that
	/// they authored the content they're trying to modify/delete themselves, and still have rights to edit
	/// their own content (that is, they aren't banned/quarantined).
	func guardCanModifyContent<T: Reportable>(
		_ content: T,
		customErrorString: String = "user cannot modify this content"
	) throws {
		if let quarantineEndDate = tempQuarantineUntil {
			guard Date() > quarantineEndDate else {
				throw Abort(.forbidden, reason: "User is temporarily quarantined and cannot modify content.")
			}
		}
		let userIsContentCreator = try requireID() == content.authorUUID
		guard
			accessLevel.canEditOthersContent()
				|| (userIsContentCreator && accessLevel.canCreateContent()
					&& (content.moderationStatus == .normal || content.moderationStatus == .modReviewed))
		else {
			throw Abort(.forbidden, reason: customErrorString)
		}
		// If a mod reviews some content, and then the user edits their own content, it's no longer moderator reviewed.
		// This code assumes the content is going to get saved by caller.
		if userIsContentCreator && content.moderationStatus == .modReviewed {
			content.moderationStatus = .normal
		}
	}

	/// The receiver is the user performing the edit. `ofUser` may be nil if the reciever is editing their own profile. If it's a moderator editing another user's profile,
	/// remember that the receiver is the moderator, and the user whose profile is being edited is the ofUser parameter.
	///
	/// This fn is very similar to `guardCanModifyContent()`; it's a separate function because profile editing is  likely to have different access requirements.
	/// In particular we're likely to let unverified users edit their profile.
	func guardCanEditProfile(ofUser profileOwner: User? = nil, customErrorString: String = "User cannot edit profile")
		throws
	{
		if let quarantineEndDate = tempQuarantineUntil {
			guard Date() > quarantineEndDate else {
				throw Abort(.forbidden, reason: "User is temporarily quarantined and cannot modify content.")
			}
		}
		let profileBeingEdited = profileOwner ?? self
		let editingOwnProfile = try profileOwner == nil || requireID() == profileOwner?.requireID()
		guard
			accessLevel.canEditOthersContent()
				|| (editingOwnProfile && accessLevel.canCreateContent()
					&& (profileBeingEdited.moderationStatus == .normal
						|| profileBeingEdited.moderationStatus == .modReviewed))
		else {
			throw Abort(.forbidden, reason: customErrorString)
		}
	}
}

/// Technically, you're not reporting the User themselves, you're reporting on their profile. Either the avatar image or profile images
/// have a code of conduct problem.
extension User: Reportable {

	/// The report type for `User` reports.
	var reportType: ReportType { .userProfile }

	var authorUUID: UUID { id ?? UUID() }

	var autoQuarantineThreshold: Int { Settings.shared.userAutoQuarantineThreshold }
}

import Fluent
import Redis
import Vapor

/// A `Protocol` for complex ChatGroup interactions.
/// One could consider this a `Helper` if it weren't for the limitation that Structs cannot inherit
/// from other Structs.
protocol ChatGroupProtocol: APIRouteCollection {
	/// This page intentionally left blank.
}

extension ChatGroupProtocol {
	// Helper function to easily construct and send a seamail from someone to a set of someones.
	// This was mostly lifted from the ChatGroupController and simplified since there are no HTTP requests/responses
	// to worry about (other than needing one for certain operations). I made it its own function in this protocol
	// in case there are future cases where we want to send generated messages directly to accounts. The API
	// already presents all of this functionality to consumers but it's difficult to consume the API from the API.
	// I thought about having it return (chatgroup, post) but in my use case since I'm throwing them away I'm disinclined
	// to do that. Maybe later.
	func sendSimpleSeamail(_ req: Request, fromUserID: UUID, toUserIDs: [UUID], subject: String, initialMessage: String)
		async throws
	{
		// Build the ChatGroup.
		let chatgroup = ChatGroup(
			owner: fromUserID,
			chatGroupType: ChatGroupType.closed,
			title: subject,
			info: "",
			location: nil,
			startTime: nil,
			endTime: nil,
			minCapacity: 0,
			maxCapacity: 0
		)
		let initialUsers = [fromUserID] + toUserIDs
		chatgroup.participantArray = initialUsers
		chatgroup.postCount += 1
		try await chatgroup.save(on: req.db)

		// We need the real User objects to do the appropriate pivoting.
		// There is some voodoo here that magically makes everything work under the hood.
		let actualUsers = try await User.query(on: req.db).filter(\.$id ~~ initialUsers).all()
		try await chatgroup.$participants.attach(
			actualUsers,
			on: req.db,
			{
				$0.readCount = 0
				$0.hiddenCount = 0
			}
		)

		// Build the Post in the ChatGroup.
		let post = try ChatGroupPost(chatgroup: chatgroup, authorID: fromUserID, text: initialMessage, image: nil)
		try await post.save(on: req.db)

		// Generate appropriate notifications.
		let infoStr = "@\(fromUserID) wrote, \"\(post.text)\""
		try await addNotifications(users: initialUsers, type: chatgroup.notificationType(), info: infoStr, on: req)
	}
}

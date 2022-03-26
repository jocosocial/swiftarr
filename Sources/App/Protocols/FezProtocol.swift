import Vapor
import Redis
import Fluent

protocol FezProtocol: APIRouteCollection {
	/// This page intentionally left blank.
}

extension FezProtocol {
	func sendSimpleSeamail(_ req: Request, fromUserID: UUID, toUserIDs: [UUID], subject: String, initialMessage: String) async throws -> (FriendlyFez, FezPost) {
        let fez = FriendlyFez(owner: fromUserID, fezType: FezType.closed, title: subject, info: "",
				location: nil, startTime: nil, endTime: nil,
				minCapacity: 0, maxCapacity: 0)
        let initialUsers = [fromUserID] + toUserIDs
        fez.participantArray = initialUsers
        fez.postCount += 1
        let actualUsers = try await User.query(on: req.db).filter(\.$id ~~ initialUsers).all()
        try await fez.save(on: req.db)
        try await fez.$participants.attach(actualUsers, on: req.db, { $0.readCount = 0; $0.hiddenCount = 0 })
        let post = try FezPost(fez: fez, authorID: fromUserID, text: initialMessage, image: nil)
        try await post.save(on: req.db)
        let infoStr = "@\(fromUserID) wrote, \"\(post.text)\""
        try addNotifications(users: initialUsers, type: fez.notificationType(), info: infoStr, on: req)

		return (fez, post)
	}
}
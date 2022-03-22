import Vapor
import Redis

protocol FezProtocol {
	/// This page intentionally left blank.
}

extension FezProtocol {
    // MembersOnlyData is only filled in if:
	//	* The user is a member of the fez (pivot is not nil) OR
	//  * The user is a moderator and the fez is not private
	// 
	// Pivot should always be nil if the current user is not a member of the fez.
	// To read the 'moderator' or 'twitarrteam' seamail, verify the requestor has access and call this fn with
	// the effective user's account.
	func buildFezData(from fez: FriendlyFez, with pivot: FezParticipant? = nil, posts: [FezPostData]? = nil, 
			for cacheUser: UserCacheData, on req: Request) throws -> FezData {
		let userBlocks = cacheUser.getBlocks()
		// init return struct
		let ownerHeader = try req.userCache.getHeader(fez.$owner.id)
		var fezData : FezData = try FezData(fez: fez, owner: ownerHeader)
		if pivot != nil || (cacheUser.accessLevel.hasAccess(.moderator) && fez.fezType != .closed) {
			let allParticipantHeaders = req.userCache.getHeaders(fez.participantArray)

			// masquerade blocked users
			let valids = allParticipantHeaders.map { (member: UserHeader) -> UserHeader in
				if userBlocks.contains(member.userID) {
					return UserHeader.Blocked
				}
				return member
			}
			// populate fezData's participant list and waiting list
			var participants: [UserHeader]
			var waitingList: [UserHeader]
			if valids.count > fez.maxCapacity && fez.maxCapacity > 0 {
				participants = Array(valids[valids.startIndex..<fez.maxCapacity])
				waitingList = Array(valids[fez.maxCapacity..<valids.endIndex])
			}
			else {
				participants = valids
				waitingList = []
			}
			fezData.members = FezData.MembersOnlyData(participants: participants, waitingList: waitingList, 
					postCount: fez.postCount - (pivot?.hiddenCount ?? 0), readCount: pivot?.readCount ?? 0, posts: posts)
		}
		return fezData
	}
}
import Fluent
import Vapor

/// Fetches reactions in batches and assembles grouped responses consistently for every post view.
enum PostReactionBuilder {
	/// Builds forum reactions with a single query regardless of the number of posts.
	static func forum(postIDs: [Int], on req: Request) async throws -> [Int: [ReactionData]] {
		guard !postIDs.isEmpty else { return [:] }
		let rows = try await ForumPostReaction.query(on: req.db).filter(\.$post.$id ~~ postIDs)
			.sort(\.$createdAt, .ascending).sort(\.$groupOrder, .ascending).all()
		return grouped(rows.map { ($0.$post.id, $0.emoji, $0.$user.id) }, on: req)
	}

	/// Builds LFG, Seamail, and private-event reactions with a single query.
	static func fez(postIDs: [Int], on req: Request) async throws -> [Int: [ReactionData]] {
		guard !postIDs.isEmpty else { return [:] }
		let rows = try await FezPostReaction.query(on: req.db).filter(\.$post.$id ~~ postIDs)
			.sort(\.$createdAt, .ascending).sort(\.$groupOrder, .ascending).all()
		return grouped(rows.map { ($0.$post.id, $0.emoji, $0.$user.id) }, on: req)
	}

	/// Preserves the database's chip order while collecting contributor headers by post and emoji.
	private static func grouped(_ rows: [(postID: Int, emoji: String, userID: UUID)], on req: Request) -> [Int: [ReactionData]] {
		var users = [Int: [String: [UUID]]]()
		var order = [Int: [String]]()
		for row in rows {
			if users[row.postID]?[row.emoji] == nil {
				order[row.postID, default: []].append(row.emoji)
			}
			users[row.postID, default: [:]][row.emoji, default: []].append(row.userID)
		}
		return Dictionary(uniqueKeysWithValues: order.map { postID, emojis in
			(postID, emojis.map { ReactionData(reaction: $0, users: req.userCache.getHeaders(users[postID]?[$0] ?? [])) })
		})
	}
}

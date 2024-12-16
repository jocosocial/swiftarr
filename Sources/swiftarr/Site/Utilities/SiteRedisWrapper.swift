import Foundation
@preconcurrency import Redis
import Vapor

/// Extends Request.Redis for Site
///
/// Most of the Redis extensions are in the API-level RedisWrapper file, but some usage of Redis is specific to the Site code.
/// This file takes Redis primitives and 'wraps' them in methods that describe the operation what we're actually doing.
extension Request.Redis {
	// MARK: Sessions
	// Redis key "sessions-<userID>" stores a hash of all the session IDs attached to that user. The fields in this
	// hash aren't the sessions themselves--they're just a way to track all the places where a particular user logged in.
	func storeSessionMarker(_ session: SessionID?, marker: String, forUserID: UUID) async throws {
		if let sessionID = session?.string {
			_ = try await hset(sessionID, to: marker, in: "sessions-\(forUserID)").get()
		}
	}

	// Deletes a session from the key; call this on logout. Note that this doesn't delete the actual session--
	// use req.session.destroy() to do that.
	func clearSessionMarker(_ session: SessionID?, forUserID: UUID) async throws {
		if let sessionID = session?.string {
			_ = try await hdel(sessionID, from: "sessions-\(forUserID)").get()
		}
	}

	// Deletes all session markers by deleting the entire key.
	func clearAllSessionMarkers(forUserID: UUID) async throws {
		_ = try await delete("sessions-\(forUserID)").get()
	}

	// Returns a dictionary of all active user sessions; each session maps a SessionID to a (rough) device descriptor.
	func getUserSessions(_ userID: UUID) async throws -> [String: String] {
		let results = try await hgetall(from: "sessions-\(userID)").get()
		return results.compactMapValues { $0.string }
	}
}

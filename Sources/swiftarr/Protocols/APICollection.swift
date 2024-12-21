import Fluent
import Foundation
import Vapor

// This is a protocol of functions that interact below the hood of the API layer.
// 99% of the time what we want lives in `APIRouteCollection` because that affects
// the HTTP requests. However since we've added `Job` and `ScheduledJob` to the
// application there are times when we need to share some backend processing
// functionality with the API layer. This presents an opportunity to do that.
//
// `Request` is only available within a request context. `Application` can be accessed
// both from within a job and request context. The functions in this protocol should
// either rely on `Application` or a `Database` (that comes from either an `Application`
// or `Request`).
protocol APICollection {}

extension APICollection {
	// Get the next followed event for the user.
	func getNextFollowedEvent(userID: UUID, db: Database) async throws -> Event? {
		let filterDate: Date = Settings.shared.getScheduleReferenceDate(
			Settings.shared.upcomingEventNotificationSetting
		)
		let nextFavoriteEvent = try await Event.query(on: db)
			.filter(\.$startTime > filterDate)
			.sort(\.$startTime, .ascending)
			.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id)
			.filter(EventFavorite.self, \.$user.$id == userID)
			.first()
		return nextFavoriteEvent
	}

	// Calculates the start time of the earliest future followed event. Caches the value in Redis for quick access.
	func storeNextFollowedEvent(userID: UUID, on app: Application) async throws -> (Date, UUID)? {
		let nextFavoriteEvent = try await getNextFollowedEvent(userID: userID, db: app.db)
		guard let event = nextFavoriteEvent, let id = event.id else {
			return nil
		}
		// .addNotifications() has an entire chain of dependencies on Request that are very hard
		// for me to untangle so this copies the logic from inside that function instead.
		// This will "clear" the next Event values of the UserNotificationData if no Events match the
		// query (which is to say there is no next Event). Thought about using subtractNotifications()
		// but this just seems easier for now.
		try await app.redis.setNextEventInUserHash(date: event.startTime, eventID: id, userID: userID)
		return (event.startTime, id)
	}

	// Get the next followed event for the user.
	func getNextAppointment(userID: UUID, db: Database) async throws -> FriendlyFez? {
		let filterDate: Date = Settings.shared.getScheduleReferenceDate(Settings.shared.upcomingLFGNotificationSetting)
		let nextJoinedLFG = try await FriendlyFez.query(on: db)
			.join(FezParticipant.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
			.filter(FezParticipant.self, \.$user.$id == userID)
			.filter(\.$fezType !~ [.open, .closed])
			.filter(\.$startTime != nil)
			.filter(\.$startTime > filterDate)
			.sort(\.$startTime, .ascending)
			.first()
		return nextJoinedLFG
	}

	// Calculates the start time of the earliest future joined LFG. Caches the value in Redis for quick access.
	func storeNextJoinedAppointment(userID: UUID, on app: Application) async throws -> (Date, UUID)? {
		let nextJoinedLFG = try await getNextAppointment(userID: userID, db: app.db)
		guard let lfg = nextJoinedLFG, let id = lfg.id, let startTime = lfg.startTime else {
			return nil
		}
		// .addNotifications() has an entire chain of dependencies on Request that are very hard
		// for me to untangle so this copies the logic from inside that function instead.
		// This will "clear" the next LFG values of the UserNotificationData if no LFGs match the
		// query (which is to say there is no next LFG). Thought about using subtractNotifications()
		// but this just seems easier for now.
		try await app.redis.setNextLFGInUserHash(date: startTime, lfgID: id, userID: userID)
		return (startTime, id)
	}
}

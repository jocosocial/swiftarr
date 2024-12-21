import Foundation
import Vapor
import Fluent

protocol APICollection {}

extension APICollection {
    func getNextFollowedEvent(userID: UUID, db: Database) async throws -> Event? {
		let cruiseStartDate = Settings.shared.cruiseStartDate()
		var filterDate = Date()
		// If the cruise is in the future or more than 10 days in the past, construct a fake date during the cruise week
		let secondsPerDay = 24 * 60 * 60.0
		if cruiseStartDate.timeIntervalSinceNow > 0
			|| cruiseStartDate.timeIntervalSinceNow < 0 - Double(Settings.shared.cruiseLengthInDays) * secondsPerDay
		{
			// This filtering nonsense is whack. There is a way to do .DateComponents() without needing the in: but then you
			// have to specify the Calendar.Components that you want. Since I don't have enough testing around this I'm going
			// to keep pumping the timezone in which lets me bypass that requirement.
			let cal = Settings.shared.getPortCalendar()
			var filterDateComponents = cal.dateComponents(in: Settings.shared.portTimeZone, from: cruiseStartDate)
			let currentDateComponents = cal.dateComponents(in: Settings.shared.portTimeZone, from: Date())
			filterDateComponents.hour = currentDateComponents.hour
			filterDateComponents.minute = currentDateComponents.minute
			filterDateComponents.second = currentDateComponents.second
			filterDate = cal.date(from: filterDateComponents) ?? Date()
			if let currentDayOfWeek = currentDateComponents.weekday {
				let daysToAdd = (7 + currentDayOfWeek - Settings.shared.cruiseStartDayOfWeek) % 7
				if let adjustedDate = cal.date(byAdding: .day, value: daysToAdd, to: filterDate) {
					filterDate = adjustedDate
				}
			}
		}
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
}
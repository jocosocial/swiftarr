import Fluent
import Vapor

/// Computes the differences between the `DailyTheme` table and the theme days found in the `Event` schedule.
///
/// Theme days in the schedule are events whose title begins with "Theme:" (e.g. "Theme: Cosplay Day"). The remainder of the title becomes the
/// theme's title and the event description becomes the theme's info. Themes are matched to events by cruise day.
struct DailyThemeScheduleSync {
	/// Themes that are in the schedule but have no `DailyTheme` for that day.
	var created: [DailyThemeProposedData] = []
	/// Existing `DailyTheme`s whose title or info differ from the schedule, paired with the schedule's values.
	var modified: [(theme: DailyTheme, proposed: DailyThemeProposedData)] = []
	/// Existing `DailyTheme`s for days that have no theme event in the schedule.
	var deleted: [DailyTheme] = []

	static let titlePrefix = "Theme:"

	/// - Parameter cruiseDayOffset: Added to each computed cruise day. Lets a schedule from outside the cruise week be loaded onto arbitrary days for testing.
	static func compute(cruiseDayOffset: Int = 0, on db: Database) async throws -> DailyThemeScheduleSync {
		let events = try await Event.query(on: db)
			.filter(\.$title, .custom("ILIKE"), "\(titlePrefix)%")
			.sort(\.$startTime, .ascending)
			.all()
		let cal = Settings.shared.getPortCalendar()
		let startOfCruise = cal.startOfDay(for: Settings.shared.cruiseStartDate())
		var scheduleThemes = [Int: DailyThemeProposedData]()
		for event in events {
			let title = String(event.title.trimmingCharacters(in: .whitespaces).dropFirst(titlePrefix.count))
				.trimmingCharacters(in: .whitespaces)
			guard !title.isEmpty else {
				continue
			}
			let days = cal.dateComponents([.day], from: startOfCruise, to: cal.startOfDay(for: event.startTime)).day ?? 0
			let day = days + cruiseDayOffset
			// Events are sorted by start time; if a day has several theme events the earliest wins.
			if scheduleThemes[day] == nil {
				scheduleThemes[day] = DailyThemeProposedData(
					title: title,
					info: event.info.trimmingCharacters(in: .whitespacesAndNewlines),
					cruiseDay: day
				)
			}
		}

		var result = DailyThemeScheduleSync()
		let existing = try await DailyTheme.query(on: db).sort(\.$cruiseDay, .ascending).all()
		var existingDays = Set<Int>()
		for theme in existing {
			existingDays.insert(theme.cruiseDay)
			if let proposed = scheduleThemes[theme.cruiseDay] {
				if proposed.title != theme.title || proposed.info != theme.info {
					result.modified.append((theme: theme, proposed: proposed))
				}
			}
			else {
				result.deleted.append(theme)
			}
		}
		result.created = scheduleThemes.values.filter { !existingDays.contains($0.cruiseDay) }
			.sorted { $0.cruiseDay < $1.cruiseDay }
		return result
	}

	func differenceData() throws -> DailyThemeUpdateDifferenceData {
		return DailyThemeUpdateDifferenceData(
			createdThemes: created,
			modifiedThemes: try modified.map {
				DailyThemeModifiedData(existing: try DailyThemeData($0.theme), proposed: $0.proposed)
			},
			deletedThemes: try deleted.map { try DailyThemeData($0) }
		)
	}

	/// Applies the changes to the database. Deletes happen first, then modifications, then creates, so that the unique
	/// `cruise_day` constraint is never violated by the sequence of operations.
	func apply(skipNew: Bool, skipDiff: Bool, skipDelete: Bool, on db: Database) async throws {
		try await db.transaction { transaction in
			if !skipDelete {
				for theme in deleted {
					try await theme.delete(on: transaction)
				}
			}
			if !skipDiff {
				for (theme, proposed) in modified {
					theme.title = proposed.title
					theme.info = proposed.info
					try await theme.save(on: transaction)
				}
			}
			if !skipNew {
				for proposed in created {
					try await DailyTheme(title: proposed.title, info: proposed.info, image: nil, day: proposed.cruiseDay)
						.save(on: transaction)
				}
			}
		}
	}
}

import Fluent
import Testing
import XCTVapor

@testable import swiftarr

class DailyThemeScheduleTests: XCTestCase, SwiftarrBaseTest {
	private var savedComponents: DateComponents!

	override func setUp() {
		super.setUp()
		savedComponents = Settings.shared.cruiseStartDateComponents
		Settings.shared.cruiseStartDateComponents = DateComponents(year: 2026, month: 3, day: 22)
	}

	override func tearDown() {
		Settings.shared.cruiseStartDateComponents = savedComponents
		super.tearDown()
	}

	/// The migrations seed themes and events; start from a clean slate.
	private func clearSeedData(_ app: Application) async throws {
		try await DailyTheme.query(on: app.db).delete()
		try await Event.query(on: app.db).withDeleted().delete(force: true)
	}

	/// Saves an event starting at 10:00 port time on the given cruise day.
	private func addEvent(_ app: Application, title: String, info: String, day: Int) async throws {
		let cal = Settings.shared.getPortCalendar()
		let dayStart = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: Settings.shared.cruiseStartDate()))!
		let start = cal.date(byAdding: .hour, value: 10, to: dayStart)!
		try await Event(
			startTime: start,
			endTime: start.addingTimeInterval(3600),
			title: title,
			description: info,
			location: "Whole Ship",
			eventType: .general,
			uid: UUID().uuidString
		).save(on: app.db)
	}

	func testComputeFindsCreatedModifiedDeleted() async throws {
		try await withApp { app in
			try await clearSeedData(app)
			try await addEvent(app, title: "Theme: Retro Day", info: "Go retro", day: 1)
			try await addEvent(app, title: "theme: Cosplay Day", info: "Dress up", day: 2)
			try await addEvent(app, title: "Not a theme", info: "x", day: 3)
			try await DailyTheme(title: "Cosplay", info: "Old", image: "img.jpg", day: 2).save(on: app.db)
			try await DailyTheme(title: "Stale", info: "Gone", image: nil, day: 5).save(on: app.db)

			let diff = try await DailyThemeScheduleSync.compute(on: app.db).differenceData()
			XCTAssertEqual(diff.createdThemes.map { $0.cruiseDay }, [1])
			XCTAssertEqual(diff.createdThemes.first?.title, "Retro Day")
			XCTAssertEqual(diff.modifiedThemes.count, 1)
			XCTAssertEqual(diff.modifiedThemes.first?.proposed.title, "Cosplay Day")
			XCTAssertEqual(diff.deletedThemes.map { $0.cruiseDay }, [5])
		}
	}

	func testApplyRespectsSkipFlags() async throws {
		try await withApp { app in
			try await clearSeedData(app)
			try await addEvent(app, title: "Theme: Retro Day", info: "Go retro", day: 1)
			try await addEvent(app, title: "Theme: Cosplay Day", info: "Dress up", day: 2)
			try await DailyTheme(title: "Cosplay", info: "Old", image: "img.jpg", day: 2).save(on: app.db)
			try await DailyTheme(title: "Stale", info: "Gone", image: nil, day: 5).save(on: app.db)

			let sync = try await DailyThemeScheduleSync.compute(on: app.db)
			try await sync.apply(skipNew: true, skipDiff: true, skipDelete: true, on: app.db)
			var themes = try await DailyTheme.query(on: app.db).sort(\.$cruiseDay).all()
			XCTAssertEqual(themes.map { $0.cruiseDay }, [2, 5])
			XCTAssertEqual(themes[0].title, "Cosplay")

			try await sync.apply(skipNew: false, skipDiff: false, skipDelete: false, on: app.db)
			themes = try await DailyTheme.query(on: app.db).sort(\.$cruiseDay).all()
			XCTAssertEqual(themes.map { $0.cruiseDay }, [1, 2])
			XCTAssertEqual(themes[1].title, "Cosplay Day")
			XCTAssertEqual(themes[1].image, "img.jpg")
		}
	}

	func testCruiseDayOffsetShiftsDays() async throws {
		try await withApp { app in
			try await clearSeedData(app)
			try await addEvent(app, title: "Theme: Retro Day", info: "Go retro", day: 1)
			let diff = try await DailyThemeScheduleSync.compute(cruiseDayOffset: 200, on: app.db).differenceData()
			XCTAssertEqual(diff.createdThemes.map { $0.cruiseDay }, [201])
		}
	}
}

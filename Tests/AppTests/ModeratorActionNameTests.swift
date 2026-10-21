import XCTest
@testable import swiftarr

class ModeratorActionNameTests: XCTestCase {
	
	// MARK: - ModeratorActionType.visibleName
	
	func testVisibleName_NewAccountManagerActions() {
		XCTAssertEqual(ModeratorActionType.regCodeSearched.visibleName(), "Searched by Registration Code")
		XCTAssertEqual(ModeratorActionType.regCodeViewed.visibleName(), "Viewed Registration Code")
		XCTAssertEqual(ModeratorActionType.accountUnlocked.visibleName(), "Unlocked Account")
	}
	
	func testVisibleName_AllCasesHaveLabels() {
		let all: [ModeratorActionType] = [
			.post, .edit, .delete, .move, .quarantine, .markReviewed, .lock, .unlock, .pin, .unpin,
			.accessLevelUnverified, .accessLevelBanned, .accessLevelQuarantined, .accessLevelVerified,
			.accessLevelModerator, .accessLevelTwitarrTeam, .accessLevelTHO,
			.tempQuarantine, .tempQuarantineCleared,
			.regCodeSearched, .regCodeViewed, .accountUnlocked,
		]
		XCTAssertEqual(Set(all).count, all.count, "test list should cover every ModeratorActionType case")
		for action in all {
			XCTAssertFalse(action.visibleName().trimmingCharacters(in: .whitespaces).isEmpty, "no label for \(action)")
		}
	}
	
	func testVisibleName_DistinctLabels() {
		// Each action should have its own label so log rows don't look identical.
		let all: [ModeratorActionType] = [
			.post, .edit, .delete, .move, .quarantine, .markReviewed, .lock, .unlock, .pin, .unpin,
			.accessLevelUnverified, .accessLevelBanned, .accessLevelQuarantined, .accessLevelVerified,
			.accessLevelModerator, .accessLevelTwitarrTeam, .accessLevelTHO,
			.tempQuarantine, .tempQuarantineCleared,
			.regCodeSearched, .regCodeViewed, .accountUnlocked,
		]
		let names = Set(all.map { $0.visibleName() })
		XCTAssertEqual(names.count, all.count, "labels should be distinct: \(names.sorted())")
	}
	
}
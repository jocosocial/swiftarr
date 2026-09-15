import XCTVapor
@testable import swiftarr

class DisabledFeaturesGroupTests: XCTestCase {

	// MARK: - isFeatureDisabled

	func testIsFeatureDisabled_EmptyGroup_ReturnsFalse() {
		let group = DisabledFeaturesGroup(value: [:])
		XCTAssertFalse(group.isFeatureDisabled(.forums))
		XCTAssertFalse(group.isFeatureDisabled(.forums, inApp: .swiftarr))
	}

	func testIsFeatureDisabled_FeatureDisabledForAllApps_ReturnsTrue() {
		let group = DisabledFeaturesGroup(value: [.all: [.forums]])
		XCTAssertTrue(group.isFeatureDisabled(.forums))
		XCTAssertTrue(group.isFeatureDisabled(.forums, inApp: .swiftarr))
	}

	func testIsFeatureDisabled_AllFeaturesDisabledForAllApps_ReturnsTrue() {
		let group = DisabledFeaturesGroup(value: [.all: [.all]])
		XCTAssertTrue(group.isFeatureDisabled(.forums))
		XCTAssertTrue(group.isFeatureDisabled(.seamail, inApp: .tricordarr))
	}

	func testIsFeatureDisabled_FeatureDisabledForSpecificApp_ReturnsTrueForThatApp() {
		let group = DisabledFeaturesGroup(value: [.swiftarr: [.forums]])
		XCTAssertTrue(group.isFeatureDisabled(.forums, inApp: .swiftarr))
	}

	func testIsFeatureDisabled_FeatureDisabledForSpecificApp_ReturnsFalseForOtherApp() {
		let group = DisabledFeaturesGroup(value: [.swiftarr: [.forums]])
		XCTAssertFalse(group.isFeatureDisabled(.forums, inApp: .tricordarr))
	}

	func testIsFeatureDisabled_FeatureDisabledForApp_ReturnsFalseWhenNoAppGiven() {
		// Per-app disables don't apply when the caller didn't specify which app they're asking about.
		let group = DisabledFeaturesGroup(value: [.swiftarr: [.forums]])
		XCTAssertFalse(group.isFeatureDisabled(.forums))
	}

	func testIsFeatureDisabled_AllFeaturesDisabledForSpecificApp_ReturnsTrueForThatApp() {
		let group = DisabledFeaturesGroup(value: [.swiftarr: [.all]])
		XCTAssertTrue(group.isFeatureDisabled(.forums, inApp: .swiftarr))
		XCTAssertTrue(group.isFeatureDisabled(.seamail, inApp: .swiftarr))
	}

	func testIsFeatureDisabled_DifferentFeatureNotInDisabledList_ReturnsFalse() {
		let group = DisabledFeaturesGroup(value: [.all: [.forums]])
		XCTAssertFalse(group.isFeatureDisabled(.seamail))
	}

	// MARK: - buildDisabledFeatureArray

	func testBuildDisabledFeatureArray_EmptyGroup_ReturnsEmptyArray() {
		let group = DisabledFeaturesGroup(value: [:])
		XCTAssertEqual(group.buildDisabledFeatureArray().count, 0)
	}

	func testBuildDisabledFeatureArray_FlattensAppFeaturePairs() {
		let group = DisabledFeaturesGroup(value: [
			.swiftarr: [.forums, .seamail],
			.tricordarr: [.schedule],
		])
		let array = group.buildDisabledFeatureArray()
		XCTAssertEqual(array.count, 3)
		// Order is non-deterministic since Set iteration order is unspecified — assert as a set.
		let pairs = Set(array.map { "\($0.appName.rawValue):\($0.featureName.rawValue)" })
		XCTAssertEqual(pairs, [
			"swiftarr:forums",
			"swiftarr:seamail",
			"tricordarr:schedule",
		])
	}
}

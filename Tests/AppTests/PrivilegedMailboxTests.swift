import XCTVapor

@testable import swiftarr

class PrivilegedMailboxTests: XCTestCase {

	func testAllIsOrderedTwitarrTeamThenModerator() {
		XCTAssertEqual(PrivilegedMailbox.all.map { $0.user }, [.TwitarrTeam, .moderator])
	}

	func testMatchingQueryParamIsCaseInsensitive() {
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "moderator")?.user, .moderator)
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "MODERATOR")?.user, .moderator)
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "twitarrteam")?.user, .TwitarrTeam)
		XCTAssertEqual(PrivilegedMailbox.matching(queryParam: "TwitarrTeam")?.user, .TwitarrTeam)
	}

	func testMatchingQueryParamReturnsNilForUnknownValue() {
		XCTAssertNil(PrivilegedMailbox.matching(queryParam: "admin"))
		XCTAssertNil(PrivilegedMailbox.matching(queryParam: "javascript:alert(1)"))
		XCTAssertNil(PrivilegedMailbox.matching(queryParam: ""))
	}

	func testModeratorRequirementIsSatisfiedByModeratorAndAbove() {
		let requirement = PrivilegedMailboxRequirement.accessLevel(.moderator)
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .moderator, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .twitarrteam, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .tho, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .admin, roles: []))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .verified, roles: []))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .quarantined, roles: []))
	}

	func testTwitarrTeamRequirementIsNotSatisfiedByPlainModerator() {
		let requirement = PrivilegedMailboxRequirement.accessLevel(.twitarrteam)
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .moderator, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .twitarrteam, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .tho, roles: []))
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .admin, roles: []))
	}

	func testRoleRequirementIsSatisfiedOnlyByMatchingRole() {
		let requirement = PrivilegedMailboxRequirement.role(.accountmanager)
		XCTAssertTrue(requirement.isSatisfied(accessLevel: .verified, roles: [.accountmanager]))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .verified, roles: [.huntmanager]))
		XCTAssertFalse(requirement.isSatisfied(accessLevel: .admin, roles: []))
	}

	func testAccessDeniedReasonsAreUnchanged() {
		XCTAssertEqual(
			PrivilegedMailbox.all.first { $0.user == .moderator }?.accessDeniedReason,
			"Only moderators can access moderator seamail."
		)
		XCTAssertEqual(
			PrivilegedMailbox.all.first { $0.user == .TwitarrTeam }?.accessDeniedReason,
			"Only TwitarrTeam members can access TwitarrTeam seamail."
		)
	}

	func testInboxesMatchExistingMailInboxCases() {
		XCTAssertEqual(PrivilegedMailbox.all.first { $0.user == .moderator }?.inbox, .moderatorSeamail)
		XCTAssertEqual(PrivilegedMailbox.all.first { $0.user == .TwitarrTeam }?.inbox, .twitarrTeamSeamail)
	}
}

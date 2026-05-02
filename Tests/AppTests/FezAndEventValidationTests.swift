import XCTVapor
@testable import swiftarr

// Tests for FezContentData and PersonalEventContentData validation logic.
// FezContentData has interesting branching by fezType plus startTime/endTime
// throw-based 24-hour cap; PersonalEventContentData has a similar 24-hour cap.
class FezAndEventValidationTests: XCTestCase {

	private let decoder = ValidatingJSONDecoder()

	private func validationErrors<T: Decodable>(_ type: T.Type, _ json: String) throws -> [String] {
		let data = json.data(using: .utf8)!
		let result = try decoder.validate(type, from: data)
		return result?.validationFailures.map { $0.errorString } ?? []
	}

	// MARK: - FezContentData base fixture

	private func fezJSON(
		fezType: String = "activity",
		title: String = "Card games",
		info: String = "Looking for cribbage partners",
		location: String? = "Card Room",
		startTime: String? = nil,
		endTime: String? = nil
	) -> String {
		var fields = [
			#""fezType":"\#(fezType)""#,
			#""title":"\#(title)""#,
			#""info":"\#(info)""#,
			#""minCapacity":2"#,
			#""maxCapacity":4"#,
			#""initialUsers":[]"#,
		]
		if let location { fields.append(#""location":"\#(location)""#) }
		if let startTime { fields.append(#""startTime":"\#(startTime)""#) }
		if let endTime { fields.append(#""endTime":"\#(endTime)""#) }
		return "{" + fields.joined(separator: ",") + "}"
	}

	// MARK: - FezContentData — title bounds (always checked)

	func testFez_TitleTooShort() throws {
		let errs = try validationErrors(FezContentData.self, fezJSON(title: "x"))
		XCTAssertTrue(errs.contains("title field has a 2 character minimum"), "errs=\(errs)")
	}

	func testFez_TitleTooLong() throws {
		let title = String(repeating: "a", count: 101)
		let errs = try validationErrors(FezContentData.self, fezJSON(title: title))
		XCTAssertTrue(errs.contains("title field has a 100 character limit"), "errs=\(errs)")
	}

	// MARK: - FezContentData — info/location only validated for non-chat types

	func testFez_OpenChatType_SkipsInfoCheck() throws {
		// 'open' chat type → info not required to be ≥2 chars
		let errs = try validationErrors(FezContentData.self, fezJSON(fezType: "open", info: "x"))
		XCTAssertFalse(errs.contains("info field has a 2 character minimum"), "errs=\(errs)")
	}

	func testFez_ClosedChatType_SkipsInfoCheck() throws {
		let errs = try validationErrors(FezContentData.self, fezJSON(fezType: "closed", info: ""))
		XCTAssertFalse(errs.contains("info field has a 2 character minimum"), "errs=\(errs)")
	}

	func testFez_ActivityType_InfoTooShort() throws {
		let errs = try validationErrors(FezContentData.self, fezJSON(fezType: "activity", info: "x"))
		XCTAssertTrue(errs.contains("info field has a 2 character minimum"), "errs=\(errs)")
	}

	func testFez_ActivityType_LocationTooShort() throws {
		let errs = try validationErrors(FezContentData.self, fezJSON(fezType: "activity", location: "ab"))
		XCTAssertTrue(errs.contains("location field has a 3 character minimum"), "errs=\(errs)")
	}

	func testFez_ActivityType_HappyPath() throws {
		XCTAssertEqual(try validationErrors(FezContentData.self, fezJSON()), [])
	}

	// MARK: - FezContentData — startTime/endTime throw paths

	func testFez_StartTimeWithoutEndTime_Throws() {
		let json = fezJSON(startTime: "2024-03-12T15:00:00.000Z")
		XCTAssertThrowsError(try validationErrors(FezContentData.self, json))
	}

	func testFez_EndMoreThan24HoursAfterStart_Throws() {
		let json = fezJSON(
			startTime: "2024-03-12T15:00:00.000Z",
			endTime: "2024-03-13T16:00:00.000Z" // 25h later
		)
		XCTAssertThrowsError(try validationErrors(FezContentData.self, json))
	}

	func testFez_EndExactly24HoursAfterStart_OK() throws {
		let json = fezJSON(
			startTime: "2024-03-12T15:00:00.000Z",
			endTime: "2024-03-13T15:00:00.000Z" // exactly 24h
		)
		XCTAssertEqual(try validationErrors(FezContentData.self, json), [])
	}

	// MARK: - PersonalEventContentData

	private func eventJSON(
		title: String = "My event",
		startTime: String = "2024-03-12T15:00:00.000Z",
		endTime: String = "2024-03-12T16:00:00.000Z"
	) -> String {
		return #"{"title":"\#(title)","startTime":"\#(startTime)","endTime":"\#(endTime)","participants":[]}"#
	}

	func testPersonalEvent_HappyPath() throws {
		XCTAssertEqual(try validationErrors(PersonalEventContentData.self, eventJSON()), [])
	}

	func testPersonalEvent_TitleTooShort() throws {
		let errs = try validationErrors(PersonalEventContentData.self, eventJSON(title: "x"))
		XCTAssertTrue(errs.contains("title field has a 2 character minimum"), "errs=\(errs)")
	}

	func testPersonalEvent_TitleTooLong() throws {
		let title = String(repeating: "a", count: 101)
		let errs = try validationErrors(PersonalEventContentData.self, eventJSON(title: title))
		XCTAssertTrue(errs.contains("title field has a 100 character limit"), "errs=\(errs)")
	}

	func testPersonalEvent_LongerThan24Hours_Throws() {
		let json = eventJSON(
			startTime: "2024-03-12T15:00:00.000Z",
			endTime: "2024-03-13T16:00:00.000Z"
		)
		XCTAssertThrowsError(try validationErrors(PersonalEventContentData.self, json))
	}

	// MARK: - UserRecoveryData

	private func recoveryJSON(username: String = "skyler", recoveryKey: String = "abc123", newPassword: String = "newpass1") -> String {
		return #"{"username":"\#(username)","recoveryKey":"\#(recoveryKey)","newPassword":"\#(newPassword)"}"#
	}

	func testRecovery_HappyPath() throws {
		XCTAssertEqual(try validationErrors(UserRecoveryData.self, recoveryJSON()), [])
	}

	func testRecovery_RecoveryKeyTooShort() throws {
		let errs = try validationErrors(UserRecoveryData.self, recoveryJSON(recoveryKey: "abc"))
		XCTAssertTrue(errs.contains("password/recovery code has a 6 character minimum"), "errs=\(errs)")
	}

	func testRecovery_NewPasswordTooShort() throws {
		let errs = try validationErrors(UserRecoveryData.self, recoveryJSON(newPassword: "abc"))
		XCTAssertTrue(errs.contains("password has a 6 character minimum length"), "errs=\(errs)")
	}

	func testRecovery_BadUsername_PropagatesUsernameValidations() throws {
		let errs = try validationErrors(UserRecoveryData.self, recoveryJSON(username: "x"))
		XCTAssertTrue(errs.contains("username has a 2 character minimum"), "errs=\(errs)")
	}
}

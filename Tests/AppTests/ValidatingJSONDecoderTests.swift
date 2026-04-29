import XCTVapor
@testable import swiftarr

class ValidatingJSONDecoderTests: XCTestCase {

	// MARK: - Test fixtures

	private struct PlainPayload: Decodable {
		let name: String
		let count: Int
	}

	private struct ValidatedPayload: Decodable, RCFValidatable {
		let name: String
		let count: Int

		func runValidations(using decoder: ValidatingDecoder) throws {
			let tester = try decoder.validator(keyedBy: CodingKeys.self)
			tester.validateStrLen(name, min: 3, max: 10, forKey: .name)
			tester.validate(count >= 0, forKey: .count, or: "count must be non-negative")
		}

		enum CodingKeys: String, CodingKey { case name, count }
	}

	// MARK: - Decode without validation

	func testValidate_NonValidatable_ReturnsNil() throws {
		let json = #"{"name":"foo","count":3}"#.data(using: .utf8)!
		let result = try ValidatingJSONDecoder().validate(PlainPayload.self, from: json)
		XCTAssertNil(result)
	}

	// MARK: - Validatable payload — happy path

	func testValidate_AllRulesPass_ReturnsNil() throws {
		let json = #"{"name":"foo","count":3}"#.data(using: .utf8)!
		let result = try ValidatingJSONDecoder().validate(ValidatedPayload.self, from: json)
		XCTAssertNil(result)
	}

	// MARK: - Validatable payload — failures

	func testValidate_StringTooShort_ReturnsValidationError() throws {
		let json = #"{"name":"a","count":3}"#.data(using: .utf8)!
		let result = try ValidatingJSONDecoder().validate(ValidatedPayload.self, from: json)
		XCTAssertNotNil(result)
		XCTAssertEqual(result?.validationFailures.count, 1)
		XCTAssertEqual(result?.validationFailures.first?.field, "name")
	}

	func testValidate_StringTooLong_ReturnsValidationError() throws {
		let json = #"{"name":"thisIsTooLongAName","count":3}"#.data(using: .utf8)!
		let result = try ValidatingJSONDecoder().validate(ValidatedPayload.self, from: json)
		XCTAssertNotNil(result)
		XCTAssertEqual(result?.validationFailures.first?.field, "name")
	}

	func testValidate_PredicateFails_ReturnsValidationError() throws {
		let json = #"{"name":"foo","count":-5}"#.data(using: .utf8)!
		let result = try ValidatingJSONDecoder().validate(ValidatedPayload.self, from: json)
		XCTAssertNotNil(result)
		XCTAssertEqual(result?.validationFailures.first?.errorString, "count must be non-negative")
	}

	func testValidate_MultipleFailures_AllReported() throws {
		let json = #"{"name":"a","count":-1}"#.data(using: .utf8)!
		let result = try ValidatingJSONDecoder().validate(ValidatedPayload.self, from: json)
		XCTAssertNotNil(result)
		XCTAssertEqual(result?.validationFailures.count, 2)
	}

	// MARK: - Decode failure (not a validation failure)

	func testValidate_MissingRequiredKey_ThrowsDecodeError() {
		let json = #"{"count":3}"#.data(using: .utf8)!
		XCTAssertThrowsError(try ValidatingJSONDecoder().validate(ValidatedPayload.self, from: json)) { error in
			// Swift's JSONDecoder throws DecodingError.keyNotFound here, not a ValidationError —
			// the parser distinguishes "couldn't decode at all" from "decoded but invalid".
			XCTAssertTrue(error is DecodingError, "Expected DecodingError, got \(error)")
		}
	}

	func testValidate_MalformedJSON_ThrowsDecodeError() {
		let json = "{not json}".data(using: .utf8)!
		XCTAssertThrowsError(try ValidatingJSONDecoder().validate(PlainPayload.self, from: json))
	}
}

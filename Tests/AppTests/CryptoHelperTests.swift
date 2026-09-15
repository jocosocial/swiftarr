import XCTVapor
@testable import swiftarr

class CryptoHelperTests: XCTestCase {

	// Known SHA-256 outputs from RFC 6234 / NIST examples.

	func testSHA256_EmptyString() {
		XCTAssertEqual(
			CryptoHelper.sha256Hash(of: ""),
			"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
		)
	}

	func testSHA256_AbcString() {
		XCTAssertEqual(
			CryptoHelper.sha256Hash(of: "abc"),
			"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
		)
	}

	func testSHA256_LongerString() {
		XCTAssertEqual(
			CryptoHelper.sha256Hash(of: "The quick brown fox jumps over the lazy dog"),
			"d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
		)
	}

	func testSHA256_Deterministic() {
		let a = CryptoHelper.sha256Hash(of: "swiftarr")
		let b = CryptoHelper.sha256Hash(of: "swiftarr")
		XCTAssertEqual(a, b)
	}

	func testSHA256_DifferentInputsProduceDifferentHashes() {
		let a = CryptoHelper.sha256Hash(of: "swiftarr")
		let b = CryptoHelper.sha256Hash(of: "Swiftarr")
		XCTAssertNotEqual(a, b)
	}

	func testSHA256_OutputIsLowercaseHex64Chars() {
		let hash = CryptoHelper.sha256Hash(of: "anything")
		XCTAssertEqual(hash.count, 64)
		XCTAssertEqual(hash, hash.lowercased())
		XCTAssertNil(hash.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted))
	}
}

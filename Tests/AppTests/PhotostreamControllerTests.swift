import XCTVapor
import XCTest

@testable import swiftarr

final class PhotostreamControllerTests: XCTestCase {
	func testUploadResponseIncludesCreatedPhotoAndRateLimit() throws {
		let createdAt = Date(timeIntervalSince1970: 1_725_000_000)
		let photo = PhotostreamImageData(
			postID: 42,
			createdAt: createdAt,
			author: UserHeader(
				userID: UUID(uuidString: "A914114F-0B8E-4D86-9FB3-7D8C37F36FB7")!,
				username: "photographer",
				displayName: "Photographer",
				userImage: "avatar.png",
				preferredPronoun: nil
			),
			image: "photostream-42.jpg",
			event: nil,
			location: PhotoStreamBoatLocation.onBoat.rawValue
		)

		let response = try PhotostreamController()
			.makeUploadResponse(
				photo: photo,
				rateLimit: 900
			)

		XCTAssertEqual(response.status, .ok)
		XCTAssertEqual(response.headers.first(name: "Retry-After"), "900.0")
		let content = try response.content.decode(PhotostreamImageData.self)
		XCTAssertEqual(content.postID, 42)
		XCTAssertEqual(content.createdAt, createdAt)
		XCTAssertEqual(content.author.username, "photographer")
		XCTAssertEqual(content.image, "photostream-42.jpg")
		XCTAssertEqual(content.location, PhotoStreamBoatLocation.onBoat.rawValue)
	}
}

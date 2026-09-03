import XCTVapor

@testable import swiftarr

// Tests the Site layer's post form -> PostContentData mapping, driven by multipart bodies shaped the
// way a browser actually submits them. Pure Swift -- no DB or network required.
class MessagePostFormTests: XCTestCase {

	private typealias FormPart = (name: String, filename: String?, body: String)

	// Assembles a multipart/form-data body. A part with a non-nil filename is a file input; a browser
	// submits one of those even when the user picked nothing, as an empty filename and an empty body.
	private func multipartBody(_ parts: [FormPart], boundary: String) -> String {
		var body = ""
		for part in parts {
			body += "--\(boundary)\r\n"
			if let filename = part.filename {
				body += "Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n"
				body += "Content-Type: application/octet-stream\r\n"
			}
			else {
				body += "Content-Disposition: form-data; name=\"\(part.name)\"\r\n"
			}
			body += "\r\n\(part.body)\r\n"
		}
		return body + "--\(boundary)--\r\n"
	}

	private func decodeForm(_ parts: [FormPart]) throws -> MessagePostFormContent {
		let boundary = "----WebKitFormBoundaryswiftarrTest"
		return try FormDataDecoder().decode(
			MessagePostFormContent.self,
			from: multipartBody(parts, boundary: boundary),
			boundary: boundary
		)
	}

	// What the edit form submits for a post that already has one image: the stored filename rides
	// along in the hidden serverPhoto1 field, and localPhoto1 is a file input the user never touched.
	private let editFormWithOneExistingImage: [FormPart] = [
		("postText", nil, "edited text"),
		("localPhoto1", "", ""),
		("serverPhoto1", nil, "existing.jpg"),
		("localPhoto2", "", ""),
		("serverPhoto2", nil, ""),
	]

	func testEditKeepsAnExistingImage() throws {
		let content = try decodeForm(editFormWithOneExistingImage).buildPostContentData()
		XCTAssertEqual(content.images.count, 1)
		XCTAssertEqual(content.images.first?.filename, "existing.jpg")
		// The image has to be nil, not merely empty. processImages checks `image` first and only
		// falls back to `filename` when it is nil, so a zero-byte image here drops the photo.
		XCTAssertNil(content.images.first?.image)
	}

	func testUntouchedFileInputDecodesAsEmptyData() throws {
		// Pins the decoder behavior the test above guards against: the part is present in the body,
		// so an optional Data decodes to empty Data rather than to nil.
		let form = try decodeForm(editFormWithOneExistingImage)
		XCTAssertEqual(form.localPhoto1, Data())
	}

	func testChoosingAPhotoUploadsIt() throws {
		let content = try decodeForm([
			("postText", nil, "first post"),
			("localPhoto1", "photo.jpg", "JPEGBYTES"),
			("serverPhoto1", nil, ""),
		]).buildPostContentData()
		XCTAssertEqual(content.images.count, 1)
		XCTAssertEqual(content.images.first?.image, Data("JPEGBYTES".utf8))
	}

	func testUnusedPhotoSlotsAreDropped() throws {
		let content = try decodeForm([
			("postText", nil, "no photos here"),
			("localPhoto1", "", ""),
			("serverPhoto1", nil, ""),
			("localPhoto2", "", ""),
			("serverPhoto2", nil, ""),
		]).buildPostContentData()
		XCTAssertTrue(content.images.isEmpty, "got \(content.images)")
	}

	private func header(username: String) -> UserHeader {
		UserHeader(
			userID: UUID(),
			username: username,
			displayName: nil,
			userImage: nil,
			preferredPronoun: nil
		)
	}

	private func announcement(authorUsername: String) -> AnnouncementData {
		AnnouncementData(
			id: 1,
			author: header(username: authorUsername),
			text: "body",
			updatedAt: Date(),
			displayUntil: Date().addingTimeInterval(86_400),
			isDeleted: false
		)
	}

	func testCreateAnnouncementPostAsUserIsSelf() {
		XCTAssertEqual(MessagePostContext(forType: .announcement).postAsUser, "self")
	}

	func testEditAnnouncementPostAsUserMatchesPrivilegedAuthor() {
		XCTAssertEqual(
			MessagePostContext(forType: .announcementEdit(announcement(authorUsername: PrivilegedUser.TwitarrTeam.rawValue)))
				.postAsUser,
			PrivilegedUser.TwitarrTeam.rawValue
		)
		XCTAssertEqual(
			MessagePostContext(forType: .announcementEdit(announcement(authorUsername: PrivilegedUser.THO.rawValue)))
				.postAsUser,
			PrivilegedUser.THO.rawValue
		)
		XCTAssertEqual(
			MessagePostContext(forType: .announcementEdit(announcement(authorUsername: PrivilegedUser.admin.rawValue)))
				.postAsUser,
			PrivilegedUser.admin.rawValue
		)
	}

	func testEditAnnouncementPostAsUserIsUnselectedForNormalAuthor() {
		XCTAssertEqual(
			MessagePostContext(forType: .announcementEdit(announcement(authorUsername: "someuser"))).postAsUser,
			""
		)
	}

	func testShowsPostAsRadiosOmitsWhenViewerCannotSeeCurrentAuthor() {
		let ttEdit = MessagePostContext(
			forType: .announcementEdit(announcement(authorUsername: PrivilegedUser.TwitarrTeam.rawValue))
		)
		XCTAssertFalse(ttEdit.showsPostAsRadios(userIsTHO: true, userIsAdmin: false))
		XCTAssertTrue(ttEdit.showsPostAsRadios(userIsTHO: true, userIsAdmin: true))
		XCTAssertTrue(ttEdit.showsPostAsRadios(userIsTHO: false, userIsAdmin: false))

		let thoEdit = MessagePostContext(
			forType: .announcementEdit(announcement(authorUsername: PrivilegedUser.THO.rawValue))
		)
		XCTAssertFalse(thoEdit.showsPostAsRadios(userIsTHO: false, userIsAdmin: false))
		XCTAssertTrue(thoEdit.showsPostAsRadios(userIsTHO: true, userIsAdmin: false))
	}

	func testShowsPostAsRadiosOnCreate() {
		XCTAssertTrue(
			MessagePostContext(forType: .announcement).showsPostAsRadios(userIsTHO: true, userIsAdmin: false)
		)
	}
}

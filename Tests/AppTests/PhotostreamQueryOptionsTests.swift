@testable import swiftarr
import Foundation
import Testing

struct PhotostreamQueryOptionsTests {
	@Test("Photostream query options retain the author filter")
	func byUserFilter() {
		let userID = UUID()

		let options = PhotostreamQueryOptions(byUser: userID)

		#expect(options.byUser == userID)
	}
}

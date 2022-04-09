import Vapor
import Fluent

// MARK: - Functions

// events can be filtered by creator
extension Event: ContentFilterable {

	func contentTextStrings() -> [String] {
		return [self.title, self.info, self.location]
	}
}

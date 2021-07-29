import Vapor
import Fluent

// MARK: - Functions

// events can be bookmarked
extension Event: UserBookmarkable {
    /// The barrel type for `Event` bookmarking.
	var bookmarkBarrelType: BarrelType {
        return .taggedEvent
    }
    
    func bookmarkIDString() throws -> String {
    	return try String(self.requireID())
    }
}

// events can be filtered by creator
extension Event: ContentFilterable {

	func contentTextStrings() -> [String] {
		return [self.title, self.info, self.location]
	}
}

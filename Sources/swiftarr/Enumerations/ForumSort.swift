/// Supported ordering for forum threads within a category.
enum ForumSort: String, Codable {
	/// Newest-created threads first by default.
	case create
	/// Alphabetical thread titles by default.
	case title
	/// Most recently updated threads first by default.
	case update
	/// Event start time, then event title; valid only for event categories.
	case event
}

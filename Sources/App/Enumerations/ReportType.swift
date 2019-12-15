import FluentPostgreSQL

/// The type of entity being reported in a `Report`.

enum ReportType: String, PostgreSQLRawEnum {
    /// An entire `Forum`.
    case forum
    /// An individual `ForumPost`.
    case forumPost
    /// An individual `Twarrt`.
    case twarrt
    /// A `User`.
    case user
}

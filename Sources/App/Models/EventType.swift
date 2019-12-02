import FluentPostgreSQL

/// The type of `Event`.

enum EventType: String, PostgreSQLRawEnum {
    /// A gaming event.
    case gaming
    /// An official but uncategorized event.
    case general
    /// A live podcase event.
    case livePodcast
    /// A main concert event.
    case mainConcert
    /// An office hours event.
    case officeHours
    /// A party event.
    case party
    /// A q&a/panel event.
    case qaPanel
    /// A reading/performance event.
    case readingPerformance
    /// A shadow cruise event.
    case shadow
    /// A signing event.
    case signing
    /// A workshop event.
    case workshop
}

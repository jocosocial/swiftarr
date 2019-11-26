import FluentPostgreSQL

/// The type of `Barrel`.

enum BarrelType: String, PostgreSQLRawEnum {
    /// A user's barrel of alert keywords.
    case keywordAlert
    /// A user's barrel of muting keywords.
    case keywordMute
    /// A generic barrel of seamonkeys.
    case seamonkey
    /// A user's barrel of blocked seamonkeys.
    case userBlock
    /// A user's barrel of muted seamonkeys.
    case userMute
}

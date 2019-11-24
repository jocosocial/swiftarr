import FluentPostgreSQL

/// The type of `Barrel`.

enum BarrelType: String, PostgreSQLRawEnum {
    /// A generic barrel of seamonkeys.
    case seamonkey
    /// A user's barrel of blocked seamonkeys.
    case userBlock
    /// A user's barrel of muted seamonkeys.
    case userMute
    /// A user's barrel of muting keywords.
    case wordMute
}

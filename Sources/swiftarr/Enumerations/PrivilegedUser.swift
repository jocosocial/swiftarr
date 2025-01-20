import Vapor
import Fluent

// Creating this one place to write down the usernames of the privileged
// users that we create. It's hard to remember if the username is "TwitarrTeam",
// "twitarrteam", "Twitarrteam", etc.
enum PrivilegedUser: String, CaseIterable, Codable {
    // Twitarr Team
    case TwitarrTeam
    // Moderator
    case moderator
    // Admin
    case admin
    // THO
    case THO
}

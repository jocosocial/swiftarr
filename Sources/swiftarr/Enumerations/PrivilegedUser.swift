import Vapor
import Fluent

// Creating this one place to write down the usernames of the privileged
// users that we create. It's hard to remember if the username is "TwitarrTeam",
// "twitarrteam", "Twitarrteam", etc. There are a lot of areas of the code that
// will need backfilled with these values.
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

extension PrivilegedUser {
    // Returns the url query parameter comparison version of the usernames.
    // Generally we use .lowercased() for url query param comparison.
    var queryParam: String {
        return self.rawValue.lowercased()
    }
}
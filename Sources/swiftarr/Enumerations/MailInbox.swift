import Foundation
@preconcurrency import Redis

// MARK: Seamails
//
// Each user has up to 4 Redis keys for tracking unread seamail and LFG messages. Each key roughly translates to
// a mailbox. Each key is a hash associating the UUID of a message thread with the # of messages the user hasn't
// read. This means each user with mod privledges has their own counts of the moderator seamails they haven't read.
// This also means that given a seamail thread that has both @moderator and Alice (a mod user) in the thread, Alice
// will have 2 separate unread notifications for this email.
enum MailInbox {
    case seamail
    case moderatorSeamail
    case twitarrTeamSeamail
    case lfgMessages
    case privateEvent

    // MailInboxes that are for users, basically the non-privileged stuff.
    static var userMailInboxes: [MailInbox] {
        [.lfgMessages, .privateEvent, .seamail]
    }
    
    // Does not attempt to match moderator or TwitarrTeam mailboxes. Generally in a group chat you need to notify
    // on the seamail/lfg/pe mailbox for the user themselves and also (if they're a mod/TT) on the mod/TT inbox.
    static func mailboxForChatType(type: FezType) -> MailInbox {
        if type.isLFGType { 
            return .lfgMessages 
        }
        else if type.isPrivateEventType {
            return .privateEvent
        }
        return .seamail
    }
    
    func unreadMailRedisKey(_ userID: UUID) -> RedisKey {
        switch self {
        case .seamail: return RedisKey("UnreadSeamails-\(userID)")
        case .moderatorSeamail: return RedisKey("UnreadModSeamails-\(userID)")
        case .twitarrTeamSeamail: return RedisKey("UnreadTTSeamails-\(userID)")
        case .lfgMessages: return RedisKey("UnreadLFGs-\(userID)")
        case .privateEvent: return RedisKey("UnreadPersonalEvents-\(userID)")
        }
    }
}
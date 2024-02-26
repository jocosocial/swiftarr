import FluentSQL
import Vapor

/// FezPostData, modified to be easier for sockets.
///
/// Fez and Seamail socket clients will receive this message as a JSON string when a user posts in the fez/seamail. Posts made by a user
/// will be reflected back to them via this socket. If a user is logged on from 2 clients and both have open sockets, both clients will see the
/// socket message when the user posts a new message from one of the clients.
/// Each struct contains the UserHeader of the poster instead of the author's UUID; this way clients (okay, the javascript web client) can
/// format the post without additional requests.
///
/// Note: Fezzes have other state changes that don't currently have websocket notifications. Your socket message handler should gracefully
/// handle the possibility that you receive a message that doesn't fit any of the currently documented message structs.
///
/// See:
/// * `WS /api/v3/fez/:fezID/socket`
struct SocketFezPostData: Content {
	/// PostID of the new post
	var postID: Int
	/// User that posted. Should be a current member of the fez; socket should get a `SocketMemberChangeData` adding a new user before any posts by that user.
	/// But, there's a possible race condition where membership could change before the socket is opened. Unless you update FezData after opening the socket, you may
	/// see posts from users that don't appear to be members of the fez.
	var author: UserHeader
	/// The text of this post.
	var text: String
	/// When the post was made.
	var timestamp: Date
	/// An optional image that may be attached to the post.
	var image: String?
	/// HTML fragment for the post, using the Swiftarr Web UI's front end. Fragment is built using the same semantic data available in the other fields in this struct.
	/// Please don't try parsing this to gather data. This field is here so the Javascript can insert HTML that matches what the HTTP endpoints render.
	var html: String?
}

extension SocketFezPostData {
	init(post: FezPostData) {
		self.postID = post.postID
		self.author = post.author
		self.text = post.text
		self.timestamp = post.timestamp
		self.image = post.image
	}

	init(post: FezPost, author: UserHeader) throws {
		self.postID = try post.requireID()
		self.author = author
		self.text = post.text
		self.timestamp = post.createdAt ?? Date()
		self.image = post.image
	}
}

/// Informs Fez WebSocket clients of a change in Fez membership.
///
/// If joined is FALSE, the user has left the fez. Although seamail sockets use the same endpoint (seamail threads are Fezzes internally),
/// this mesage will never be sent to Seamail threads as membership is fixed at creation time.
///
/// Fez socket message handlers will receive this message as a JSON string when a user joins/leaves the fez, or is added/removed by the fez owner.
///
/// See:
/// * `WS /api/v3/fez/:fezID/socket`
struct SocketFezMemberChangeData: Content {
	/// The user that joined/left.
	var user: UserHeader
	/// TRUE if this is a join.
	var joined: Bool
	/// HTML fragment for the action, using the Swiftarr Web UI's front end. Fragment is built using the same semantic data available in the other fields in this struct.
	/// Please don't try parsing this to gather data. This field is here so the Javascript can insert HTML that matches what the HTTP endpoints render.
	var html: String?
}

/// Informs Notification WebSocket clients of a new notification.
///
/// Each notification is delivered as a JSON string, containing a type of announcement and a string appropriate for displaying to the user.
/// The string will be of the form, "User @authorName wrote a forum post that mentioned you."
struct SocketNotificationData: Content {
	enum NotificationTypeData: Content {
		/// A server-wide announcement has just been added.
		case announcement
		/// A participant in a Fez the user is a member of has posted a new message.
		case fezUnreadMsg
		/// A participant in a Seamail thread the user is a member of has posted a new message.
		case seamailUnreadMsg
		/// A user has posted a Twarrt that contains a word this user has set as an alertword.
		case alertwordTwarrt
		/// A user has posted a Forum Post that contains a word this user has set as an alertword.
		case alertwordPost
		/// A user has posted a Twarrt that @mentions this user.
		case twarrtMention
		/// A user has posted a Forum Post that @mentions this user.
		case forumMention
		/// An event the user is following is about to start.
		case followedEventStarting
		/// Someone is trying to call this user via KrakenTalk.
		case incomingPhoneCall
		/// The callee answered the call, possibly on another device.
		case phoneCallAnswered
		/// Caller hung up while phone was rining, or other party ended the call in progress, or callee declined
		case phoneCallEnded
		/// A new or edited forum post that now @mentions @moderator.
		case moderatorForumMention
		/// A new or edited forum post that now @mentions @twitarrteam.
		case twitarrTeamForumMention
		/// An LFG the user has joined is about to start.
		case joinedLFGStarting
	}
	/// The type of event that happened. See `SocketNotificationData.NotificationTypeData` for values.
	var type: NotificationTypeData
	/// A string describing what happened, suitable for adding to a notification alert.
	var info: String
	/// An ID of an Announcement, Fez, Twarrt, ForumPost, or Event.
	var contentID: String
	/// For .incomingPhoneCall notifications, the caller.
	var caller: UserHeader?
	/// For .incomingPhoneCall notification,s the caller's IP addresses. May be nil, in which case the receiver opens a server socket instead.
	var callerAddress: PhoneSocketServerAddress?
}

extension SocketNotificationData {
	init(_ type: NotificationType, info: String, id: String) {
		switch type {
		case .announcement: self.type = .announcement
		case .fezUnreadMsg: self.type = .fezUnreadMsg
		case .seamailUnreadMsg: self.type = .seamailUnreadMsg
		case .alertwordTwarrt: self.type = .alertwordTwarrt
		case .alertwordPost: self.type = .alertwordPost
		case .twarrtMention: self.type = .twarrtMention
		case .forumMention: self.type = .forumMention
		case .moderatorForumMention: self.type = .moderatorForumMention
		case .twitarrTeamForumMention: self.type = .twitarrTeamForumMention
		// nextFollowedEventTime and nextJoinedLFGTime are not a socket event, so is this OK?
		case .nextFollowedEventTime: self.type = .followedEventStarting
		case .followedEventStarting: self.type = .followedEventStarting
		case .nextJoinedLFGTime: self.type = .joinedLFGStarting
		case .joinedLFGStarting: self.type = .joinedLFGStarting
		}
		self.info = info
		self.contentID = id
	}

	// Creates an incoming phone call notification
	init(callID: UUID, caller: UserHeader, callerAddr: PhoneSocketServerAddress?) {
		self.type = .incomingPhoneCall
		self.info = caller.username
		self.contentID = callID.uuidString
		self.caller = caller
		self.callerAddress = callerAddr
	}

	init(forCallEnded: UUID) {
		type = .phoneCallEnded
		contentID = forCallEnded.uuidString
		info = ""
	}

	init(forCallAnswered: UUID) {
		type = .phoneCallAnswered
		contentID = forCallAnswered.uuidString
		info = ""
	}
}

/// Notifies the recipient of a phone call the IP addr of the caller, so the recipient can open a direct-connect WebSocket
/// to the caller (who must have started a WebSocket Server to receive the incoming connection).
struct PhoneSocketServerAddress: Codable {
	var ipV4Addr: String?
	var ipV6Addr: String?
}

/// Sent at the start of a phone call. Used as a handshake.
struct PhoneSocketStartData: Codable {
	var phonecallStartTime: Date = Date()
}

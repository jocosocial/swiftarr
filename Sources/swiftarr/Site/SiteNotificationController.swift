import FluentSQL
import Vapor

/// A single row in the rendered Notification Log page -- `NotificationLogData` plus a precomputed
/// link to the content it refers to, since several notification types have no viewable page for
/// ordinary users (e.g. `announcement`, `microKaraokeSongReady`).
struct NotificationLogRowContext: Encodable {
	var info: String
	var createdAt: Date
	var viewURL: String?

	init(_ entry: NotificationLogData) {
		info = entry.info
		createdAt = entry.createdAt
		viewURL = Self.viewURL(type: entry.type, contentID: entry.contentID)
	}

	/// Maps a notification's type + contentID to the Site-layer URL that shows the content it refers to.
	/// Returns nil for types with no single-item view a regular user can reach (handled in Leaf
	/// -- those rows just show their `info` text without a "View" link).
	static func viewURL(type: SocketNotificationData.NotificationTypeData, contentID: String) -> String? {
		switch type {
		case .addedToSeamail, .seamailUnreadMsg:
			return "/seamail/\(contentID)"
		case .addedToLFG, .fezUnreadMsg, .lfgCanceled, .joinedLFGStarting:
			return "/lfg/\(contentID)"
		case .addedToPrivateEvent, .privateEventUnreadMsg, .privateEventCanceled, .personalEventStarting:
			return "/privateevent/\(contentID)"
		case .followedEventStarting:
			return "/events/\(contentID)"
		case .alertwordTwarrt, .twarrtMention:
			return "/tweets/\(contentID)"
		case .alertwordPost, .forumMention, .moderatorForumMention, .twitarrTeamForumMention:
			return "/forum/containingpost/\(contentID)"
		case .announcement, .microKaraokeSongReady, .incomingPhoneCall, .phoneCallAnswered, .phoneCallEnded:
			return nil
		}
	}
}

struct NotificationLogContext: Encodable {
	var trunk: TrunkContext
	var entries: [NotificationLogRowContext]
	var paginator: PaginatorContext

	init(_ req: Request, log: Paginated<NotificationLogData>) {
		trunk = .init(req, title: "Notification Log", tab: .none)
		entries = log.items.map { NotificationLogRowContext($0) }
		let limit = log.paginator.limit
		paginator = PaginatorContext(log.paginator) { pageIndex in
			"/notifications?start=\(pageIndex * limit)&limit=\(limit)"
		}
	}
}

/// SiteNotificationController handles the web page showing a user's Notification Log -- a history of
/// notifications that were delivered to them, backed by `GET /api/v3/notification/log`.
struct SiteNotificationController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app, feature: .notifications)
		privateRoutes.get("notifications", use: notificationLogPageHandler)
			.destination("your notification log")
	}

	/// `GET /notifications`
	///
	/// Shows a page listing the user's notification history, newest first.
	func notificationLogPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/notification/log")
		let logData = try response.content.decode(Paginated<NotificationLogData>.self)
		let ctx = NotificationLogContext(req, log: logData)
		return try await req.view.render("Notification/notificationLog", ctx)
	}
}

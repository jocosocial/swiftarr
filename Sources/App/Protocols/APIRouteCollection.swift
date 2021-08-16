import Vapor
import Crypto
import FluentSQL

protocol APIRouteCollection {
	var categoryIDParam: PathComponent { get }
	var twarrtIDParam: PathComponent { get }
	var forumIDParam: PathComponent { get }
	var postIDParam: PathComponent { get }
	var fezIDParam: PathComponent { get }
	var fezPostIDParam: PathComponent { get }
	var userIDParam: PathComponent { get }
	var eventIDParam: PathComponent { get }
	var reportIDParam: PathComponent { get }
	var modStateParam: PathComponent { get }
	var announcementIDParam: PathComponent { get }
	var barrelIDParam: PathComponent { get }
	var alertwordParam: PathComponent { get }
	var mutewordParam: PathComponent { get }
	var searchStringParam: PathComponent { get }

	func registerRoutes(_ app: Application) throws
}

extension APIRouteCollection {

	var categoryIDParam: PathComponent { PathComponent(":category_id") }
	var twarrtIDParam: PathComponent { PathComponent(":twarrt_id") }
	var forumIDParam: PathComponent { PathComponent(":forum_id") }
	var postIDParam: PathComponent { PathComponent(":post_id") }
	var fezIDParam: PathComponent { PathComponent(":fez_id") }
	var fezPostIDParam: PathComponent { PathComponent(":fezPost_id") }
	var userIDParam: PathComponent { PathComponent(":user_id") }
	var eventIDParam: PathComponent { PathComponent(":event_id") }
	var reportIDParam: PathComponent { PathComponent(":report_id") }
	var modStateParam: PathComponent { PathComponent(":mod_state") }
	var announcementIDParam: PathComponent { PathComponent(":announcement_id") }
	var barrelIDParam: PathComponent { PathComponent(":barrel_id") }
	var alertwordParam: PathComponent { PathComponent(":alert_word") }
	var mutewordParam: PathComponent { PathComponent(":mute_word") }
	var searchStringParam: PathComponent { PathComponent(":search_string") }
	var dailyThemeIDParam: PathComponent { PathComponent(":daily_theme_id") }
	 
	/// Adds Open Auth to a route. This route can be accessed without a token (while not logged in), but `req.auth.get(User.self)` will still
	/// return a user if one is logged in.
	func addOpenAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([Token.authenticator()])
	}

	/// For routes that require HTTP Basic Auth. Tokens won't work. Generally, this is only for the login route.
	func addBasicAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([User.authenticator(), User.guardMiddleware()])
	}

	/// For routes that require a logged-in user. Applying this auth group to a route will make requests that don't have a valid token fail with a HTTP 401 error.
	func addTokenAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([Token.authenticator(), User.guardMiddleware()])
	}


	
	/// Transforms a string that might represent a date (either a `Double` or an ISO 8601
    /// representation) into a `Date`, if possible.
    ///
    /// - Note: The representation is expected to be either a string literal `Double`, or a
    ///   string in UTC `yyyy-MM-dd'T'HH:mm:ssZ` format.
    ///
    /// - Parameter string: The string to be transformed.
    /// - Returns: A `Date` if the conversion was successful, otherwise `nil`.
    static func dateFromParameter(string: String) -> Date? {
        var date: Date?
        if let timeInterval = TimeInterval(string) {
            date = Date(timeIntervalSince1970: timeInterval)
        } else {
            if #available(OSX 10.13, *) {
                if let msDate = string.iso8601ms {
                    date = msDate
//                if let dateFromISO8601ms = ISO8601DateFormatter().date(from: string) {
//                    date = dateFromISO8601ms
                }
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
//                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                if let dateFromDateFormatter = dateFormatter.date(from: string) {
                    date = dateFromDateFormatter
                }
            }
        }
        return date
    }

}


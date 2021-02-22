import Vapor
import Fluent


// MARK: - BasicAuthenticatable Conformance

extension User: ModelAuthenticatable {
    /// Required username key for HTTP Basic Authorization.
    static let usernameKey = \User.$username
    /// Required password key for HTTP Basic Authorization.
    static let passwordHashKey = \User.$password

	func verify(password: String) throws -> Bool {
		try Bcrypt.verify(password, created: self.password)
	}
}


// MARK: - Functions

extension User {

    /// Returns the `Barrel` of the given thype for the request's `User`, or nil
    /// if none exists.
    ///
    /// - Parameters:
    ///   - user: The user who owns the barrel.
    ///   - req: The incoming `Request`, on whose event loop this must run.
    /// - Returns: `Barrel` of the required type, or `nil`.
    func getBookmarkBarrel(of type: BarrelType, on req: Request) -> EventLoopFuture<Barrel?> {
    	do {
			return try Barrel.query(on: req.db)
				.filter(\.$ownerID, .equal, self.requireID())
				.filter(\.$barrelType, .equal, type)
				.first()
		}
		catch {
			return req.eventLoop.makeFailedFuture(error)
		}
    }
	
    /// Returns whether a bookmarks barrel contains the provided integer ID value.
    ///
    /// - Parameters:
    ///   - value: The Int ID value being queried.
    ///   - req: The incoming `Request`, on whose event loop this must run.
    /// - Returns: `Bool` true if the barrel contains the value, else false.
    func hasBookmarked(_ object: UserBookmarkable, on req: Request) -> EventLoopFuture<Bool> {
    	do {
			return try Barrel.query(on: req.db)
				.filter(\.$ownerID, .equal, self.requireID())
				.filter(\.$barrelType, .equal, object.bookmarkBarrelType)
				.first()
				.flatMapThrowing { (barrel) in
					guard let barrel = barrel else {
						return false 
					}
					return try barrel.userInfo["bookmarks"]?.contains(object.bookmarkIDString()) ?? false
				}
		}
		catch {
			return req.eventLoop.makeFailedFuture(error)
		}
    }
    
    /// Returns a list of IDs of all accounts associated with the `User`. If user is a primary
    /// account (has no `.parentID`) it returns itself plus any sub-accounts. If user is a
    /// sub-account, it determines its parent, then returns the parent and all sub-accounts.
    ///
    /// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on
    ///   which the query must be run.
    /// - Returns: `[UUID]` containing all the user's associated IDs.
    func allAccountIDs(on req: Request) -> EventLoopFuture<[UUID]> {
    	let parID = self.parent?.id ?? self.id
    	guard let parent = parID else {
    		return req.eventLoop.makeSucceededFuture([])
    	}
		return User.query(on: req.db).group(.or) { (or) in
            or.filter(\.$id == parent)
            or.filter(\.$parent.$id == parent)
        }.all()
            .flatMapThrowing { (users) in
                return try users.map { try $0.requireID() }
        	}
    }
        
    /// Returns the parent `User` of the user sending the request. If the requesting user has
    /// no parent, the user itself is returned.
    ///
    /// - Parameter req: The incoming request `Container`, which provides reference to the
    ///   sending user.
    func parentAccount(on req: Request) throws -> EventLoopFuture<User> {
    	if self.$parent.value == nil {
    		return req.eventLoop.makeSucceededFuture(self)
    	}
    	return self.$parent.load(on: req.db).map { self.parent }
				.unwrap(or: Abort(.internalServerError, reason: "parent not found"))
    }
    
    /// Converts a `User` model to a `SeaMonkey` representation.
    func convertToSeaMonkey() throws -> SeaMonkey {
        return try SeaMonkey(
            userID: self.requireID(),
            username: "@\(self.username)")
    }
}

extension EventLoopFuture where Value: User {    
    /// Converts a `Future<User>` to a `Future<SeaMonkey>`. This extension provides the
    /// convenience of simply using `user.convertToSeaMonkey()` and allowing the compiler
    /// to choose the appropriate version for the context.
    func convertToSeaMonkey() throws -> EventLoopFuture<SeaMonkey> {
        return self.flatMapThrowing {
            (user) in
            return try user.convertToSeaMonkey()
        }
    }
}

// users can be reported
extension User: Reportable {
    /// The report type for `User` reports.
	var reportType: ReportType {
        return .user
    }
    
	func checkAutoQuarantine(reportCount: Int, on req: Request) -> EventLoopFuture<Void> {
		// quarantine if threshold is met
		// FIXME: moderator notification
		if reportCount >= Settings.shared.userAutoQuarantineThreshold {
			self.accessLevel = .quarantined
			return self.save(on: req.db)
		}
		return req.eventLoop.future()
	}
}

import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/twitarr/*` route endpoint and handler functions related
/// to the twit-arr stream.

struct TwitarrController: RouteCollection {
    // MARK: RouteCollection Conformance
    
    /// Required. Resisters routes to the incoming router.
    func boot(routes: RoutesBuilder) throws {
        
        // convenience route group for all /api/v3/twitarr endpoints
        let twitarrRoutes = routes.grouped("api", "v3", "twitarr")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthMiddleware = Token.authenticator()
        
        // set protected route groups
        let sharedAuthGroup = twitarrRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = twitarrRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // endpoints available whether logged in or not
        sharedAuthGroup.get("", use: twarrtsHandler)
        sharedAuthGroup.get(":twarrt_id", use: twarrtHandler)
        sharedAuthGroup.get("barrel", ":barrel_id", use: twarrtsBarrelHandler)
        sharedAuthGroup.get("hashtag", ":hashtag", use: twarrtsHashtagHandler)
        sharedAuthGroup.get("search", ":search_string", use: twarrtsSearchHandler)
        sharedAuthGroup.get("user", ":user_id", use: twarrtsUserHandler)
        
        // endpoints only available when logged in
        tokenAuthGroup.post(":twarrt_id", "bookmark", use: bookmarkAddHandler)
        tokenAuthGroup.post(":twarrt_id", "bookmark", "remove", use: bookmarkRemoveHandler)
        tokenAuthGroup.get("bookmarks", use: bookmarksHandler)
        tokenAuthGroup.post("create", use: twarrtCreateHandler)
        tokenAuthGroup.post(":twarrt_id", "delete", use: twarrtDeleteHandler)
        tokenAuthGroup.post(":twarrt_id", "image", use: imageHandler)
        tokenAuthGroup.post(":twarrt_id", "image", "remove", use: imageRemoveHandler)
        tokenAuthGroup.post(":twarrt_id", "laugh", use: twarrtLaughHandler)
        tokenAuthGroup.post(":twarrt_id", "like", use: twarrtLikeHandler)
        tokenAuthGroup.post(":twarrt_id", "love", use: twarrtLoveHandler)
        tokenAuthGroup.get("likes", use: likesHandler)
        tokenAuthGroup.get("mentions", use: mentionsHandler)
        tokenAuthGroup.post(":twarrt_id", "reply", use: replyHandler)
        tokenAuthGroup.post(":twarrt_id", "report", use: twarrtReportHandler)
        tokenAuthGroup.post(":twarrt_id", "unreact", use: twarrtUnreactHandler)
        tokenAuthGroup.post(":twarrt_id", "update", use: twarrtUpdateHandler)
        tokenAuthGroup.get("user", use: userHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/twitarr/barrel/ID`
    ///
    /// Retrieve all `Twarrt`s posted by users in the specified `.seamonkey` type `Barrel`.
    ///
    /// - Note: The barrel does not need to be owned by the requesting user, though all blocks
    ///   and mutes of the requesting user are applied regardless.
    ///
    /// - Requires: A specified `Barrel` of `BarrelType.seamonkey`.
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the barrel is not a barrel of seamonkeys.
    /// - Returns: `[TwarrtData]` containing all twarrts posted by the barrel seamonkeys.
    func twarrtsBarrelHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        // get seamonkey barrel
        return Barrel.findFromParameter("barrel_id", on: req).flatMap { (barrel) in
            // ensure .seamonkey type
            guard barrel.barrelType == .seamonkey else {
                return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "barrel is not a seamonkey barrel"))
            }
            // get filters
            return Twarrt.getCachedFilters(for: user, on: req).flatMap {
                (filters) in
                // get twarrts
                return Twarrt.query(on: req.db)
                    .filter(\.$author.$id ~~ barrel.modelUUIDs)
                    .filter(\.$author.$id !~ filters.blocked)
                    .filter(\.$author.$id !~ filters.muted)
                    .with(\.$author)
                    .sort(\.$createdAt, .descending)
                    .all()
                    .flatMap { twarrts in
                    	return buildTwarrtData(from: twarrts, user: user, on: req, filters: filters,
                    			assumeBookmarked: true)
					}
            }
        }
    }
    
    /// `GET /api/v3/twitarr/ID`
    ///
    /// Retrieve the specfied `Twarrt` with full user `LikeType` data.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the twarrt is not available.
    /// - Returns: `TwarrtDetaildata` containing the specified twarrt.
    func twarrtHandler(_ req: Request) throws -> EventLoopFuture<TwarrtDetailData> {
        let user = try req.auth.require(User.self)
        return Twarrt.findFromParameter("twarrt_id", on: req).addModelID().flatMap { (twarrt, twartID) in
            // we have twarrt, but need to filter
            return Twarrt.getCachedFilters(for: user, on: req).flatMap { (filters) in
				if filters.blocked.contains(twarrt.author.id!) || filters.muted.contains(twarrt.author.id!) ||
						twarrt.containsMutewords(using: filters.mutewords) {
                	return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "twarrt is not available"))
                }
				return user.hasBookmarked(twarrt, on: req).flatMap { (bookmarked) in
					// get likes data
					return TwarrtLikes.query(on: req.db)
						.filter(\.$twarrt.$id == twartID)
						.all()
						.flatMap { (twarrtLikes) in
							// get users
							let likeUsers: [EventLoopFuture<User>] = twarrtLikes.map {
								(twarrtLike) -> EventLoopFuture<User> in
								return User.find(twarrtLike.user.id, on: req.db)
									.unwrap(or: Abort(.internalServerError, reason: "user not found"))
							}
							return likeUsers.flatten(on: req.eventLoop).flatMapThrowing { (users) in
								let seamonkeys = try users.map {
									try $0.convertToSeaMonkey()
								}
								// init return struct
								var twarrtDetailData = try TwarrtDetailData(
									postID: twarrt.requireID(),
									createdAt: twarrt.createdAt ?? Date(),
									authorID: twarrt.author.requireID(),
									text: twarrt.isQuarantined ?
										"This twarrt is under moderator review." : twarrt.text,
									image: twarrt.image,
									replyToID: twarrt.replyTo?.requireID(),
									isBookmarked: bookmarked,
									laughs: [],
									likes: [],
									loves: []
								)
								// sort seamonkeys into like types
								for (index, like) in twarrtLikes.enumerated() {
									switch like.likeType {
										case .laugh:
											twarrtDetailData.laughs.append(seamonkeys[index])
										case .like:
											twarrtDetailData.likes.append(seamonkeys[index])
										case .love:
											twarrtDetailData.loves.append(seamonkeys[index])
										default: continue
									}
								}
								return twarrtDetailData
							}
                        }
                }
            }
        }
    }
    
    /// `GET /api/v3/twitarr`
    ///
    /// Retrieve an array of `Twarrt`s. This query supports several optional query parameters.
    ///
    /// * `?limit=INT` - the maximum number of twarrts to retrieve: 1-200, default is 50
    /// * `?after=ID` - the ID of the twarrt *after* which the retrieval should start (newer)
    /// * `?before=ID` - the ID of the twarrt *before* which the retrieval should start (older)
    /// * `?afterdate=DATE` - the timestamp *after* which the retrieval should start (newer)
    /// * `?beforedate=DATE` - the timestamp *before* which the retrieval should start (older)
    /// * `?from=STRING` - retrieve starting from "first" or "last"
    ///
    /// - Important: All parameters other than `limit` are **mutually exclusive**. If
    ///   additional conflicting parameters are sent, the first one listed in the order above
    ///   takes precedence (probably).
    ///
    /// A query without additional parameters defaults to `?limit=50&from=last`, the 50 most
    /// recent twarrts.
    ///
    /// `DATE` values can be either `TimeInterval` values (Doubles) since epoch, or ISO8601
    /// string representations including milliseconds ("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"). The
    /// numeric value method is recommended.
    ///
    /// - Note: It is *highly* recommended that clients use `after=ID` or `before=ID` where
    ///   possible. `Twarrt` ID's are Int values and thus unambiguous. `DATE` values are
    ///   accurate only within 1 millisecond and are therefore prone to rounding errors. To
    ///   ensure that all twarrts of interest are returned when sending a date based on the
    ///   value found in a twarrt's timestamp, it is recommended that 1 millisecond be added
    ///   (if retrieving older) or subtracted (if retrieving newer) from that value for the
    ///   query. You will almost certainly receive the original anchor twarrt again, but it will
    ///   also ensure that any others possibly created within the same millisecond will not be
    ///   omitted.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if a date parameter was supplied and is in an unknown format.
    /// - Returns: `[TwarrtData]` containing the requested twarrts.
    func twarrtsHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        // get query parameters
        var limit = req.query[Int.self, at: "limit"] ?? 50
        let afterID = req.query[Int.self, at: "after"]
        let beforeID = req.query[Int.self, at: "before"]
        let afterDate = req.query[String.self, at: "afterdate"]
        let beforeDate = req.query[String.self, at: "beforedate"]
        let from = req.query[String.self, at: "from"]?.lowercased() ?? "last"
        // enforce maximum allowed
        if limit > Settings.shared.maximumTwarrts {
            limit = Settings.shared.maximumTwarrts
        }
        // get cached blocks
        return Twarrt.getCachedFilters(for: user, on: req).flatMap { (filters) in
            // get twarrts
            let queryBase = Twarrt.query(on: req.db)
					.filter(\.$author.$id !~ filters.blocked)
					.filter(\.$author.$id !~ filters.muted)
					.range(..<limit)
            var futureTwarrts: QueryBuilder<Twarrt>
            switch (afterID, beforeID, afterDate, beforeDate, from) {
                case (.some(let twarrtID), _, _, _, _):
                    futureTwarrts = queryBase
                        .filter(\.$id > twarrtID)
                        .sort(\.$id, .ascending)
                case (_, .some(let twarrtID), _, _, _):
                    futureTwarrts = queryBase
                        .filter(\.$id < twarrtID)
                        .sort(\.$id, .descending)
                case (_, _, .some(let twarrtDate), _, _):
                    guard let date = TwitarrController.dateFromParameter(string: twarrtDate) else {
                        return req.eventLoop.makeFailedFuture(
                        		Abort(.badRequest, reason: "not a recognized date format"))
                    }
                    print(date.timeIntervalSince1970)
                    futureTwarrts = queryBase
                        .filter(\.$createdAt > date)
                        .sort(\.$createdAt, .ascending)
                case (_, _, _, .some(let twarrtDate), _):
                    guard let date = TwitarrController.dateFromParameter(string: twarrtDate) else {
                        return req.eventLoop.makeFailedFuture(
                        		Abort(.badRequest, reason: "not a recognized date format"))
                    }
                    futureTwarrts = queryBase
                        .filter(\.$createdAt < date)
                        .sort(\.$createdAt, .descending)
                case (_, _, _, _, "first"):
                    futureTwarrts = queryBase
                        .sort(\.$id, .ascending)
                default:
                    futureTwarrts = queryBase
                        .sort(\.$id, .descending)
            }
            return futureTwarrts.all().flatMap { (twarrts) in
                // correct to descending order
                var sortedTwarrts: [Twarrt]
                switch (afterID, beforeID, afterDate, beforeDate, from) {
                    case (.some(afterID), _, _, _, _):
                        sortedTwarrts = twarrts.reversed()
                    case (_, .some(beforeID), _, _, _):
                        sortedTwarrts = twarrts
                    case (_, _, .some(afterDate), _, _):
                        sortedTwarrts = twarrts.reversed()
                    case (_, _, _, .some(beforeDate), _):
                        sortedTwarrts = twarrts
                    case (_, _, _, _, "first"):
                        sortedTwarrts = twarrts.reversed()
                    default:
                        sortedTwarrts = twarrts
                }
                return buildTwarrtData(from: sortedTwarrts, user: user, on: req, filters: filters)
            }
        }
    }
    
    /// `GET /api/v3/twitarr/hashtag/#STRING`
    ///
    /// Retrieve all `Twarrt`s that contain the exact specified hashtag.
    ///
    /// - Note: By "exact" we mean the string cannot be a substring of another hashtag (there
    ///   must be a preceeding space), but the match is not case-sensitive. For example, `#joco`
    ///   will not match `#joco2020` or `#joco#2020`, but will match `#JoCo`. Use the more
    ///   generic `GET /api/v3/twitarr/search/STRING` endpoint with the same `#joco` parameter
    ///   if you want that type of substring matching behavior.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the specified string is not a hashtag.
    /// - Returns: `[TwarrtData]` containing all matching twarrts.
    func twarrtsHashtagHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        guard var hashtag = req.parameters.get("hashtag") else {
            throw Abort(.badRequest, reason: "Missing hashtag parameter.")
        }
        // ensure it's a hashtag
        guard hashtag.hasPrefix("#") else {
            throw Abort(.badRequest, reason: "hashtag parameter must start with '#'")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        hashtag = hashtag.replacingOccurrences(of: "_", with: "\\_")
        hashtag = hashtag.replacingOccurrences(of: "%", with: "\\%")
        hashtag = hashtag.trimmingCharacters(in: .whitespacesAndNewlines)
        // get cached blocks
		return Twarrt.getCachedFilters(for: user, on: req).flatMap { (filters) -> EventLoopFuture<[TwarrtData]> in
            // get twarrts
            return Twarrt.query(on: req.db)
                .filter(\.$author.$id !~ filters.blocked)
                .filter(\.$author.$id !~ filters.muted)
                .filter(\.$text, .custom("ILIKE"), "%\(hashtag)%")
                .sort(\.$id, .descending)
                .all()
				.flatMap { twarrts in
					return buildTwarrtData(from: twarrts, user: user, on: req, filters: filters, 
							matchHashtag: hashtag)
				}
        }
    }
    
    /// `GET /api/v3/twitarr/search/STRING`
    ///
    /// Retrieve all `Twarrt`s that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all matching twarrts.
    func twarrtsSearchHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        guard var search = req.parameters.get("search_string") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // get cached blocks
        return Twarrt.getCachedFilters(for: user, on: req).flatMap { (filters) in
            // get twarrts
            return Twarrt.query(on: req.db)
                .filter(\.$author.$id !~ filters.blocked)
                .filter(\.$author.$id !~ filters.muted)
                .filter(\.$text, .custom("ILIKE"), "%\(search)%")
                .sort(\.$id, .descending)
                .all()
				.flatMap { (twarrts) in
                    return buildTwarrtData(from: twarrts, user: user, on: req, filters: filters)
				}
        }
    }
    
    /// `GET /api/v3/twitarr/user/ID`
    ///
    /// Retrieve all `Twarrt`s posted by the specified `User`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all specified user's twarrts.
    func twarrtsUserHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let requester = try req.auth.require(User.self)
        return User.findFromParameter("user_id", on: req).addModelID().flatMap {
            (user, userID) in
            // get cached blocks
            return Twarrt.getCachedFilters(for: requester, on: req).flatMap {
                (filters) in
                // get twarrts
                return Twarrt.query(on: req.db)
                    .filter(\.$author.$id !~ filters.blocked)
                    .filter(\.$author.$id !~ filters.muted)
                    .filter(\.$author.$id == userID)
                    .sort(\.$id, .descending)
                    .all()
					.flatMap { (twarrts) in
						return buildTwarrtData(from: twarrts, user: user, on: req, filters: filters)
					}
            }
        }
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/twitarr/ID/bookmark`
    ///
    /// Add a bookmark of the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the twarrt is already bookmarked.
    /// - Returns: 201 Created on success.
    func bookmarkAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get twarrt
        return Twarrt.findFromParameter("twarrt_id", on: req).addModelID().flatMap {
            (twarrt, twarrtID) in
            // get user's bookmarkedTwarrt barrel
            return user.getBookmarkBarrel(of:.bookmarkedTwarrt, on: req).flatMap {
                (bookmarkBarrel) in
                // create barrel if needed
                let barrel = bookmarkBarrel ?? Barrel(ownerID: userID, barrelType: .bookmarkedTwarrt)
                // ensure bookmark doesn't exist
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                let twarrtIDStr = String(twarrtID)
                guard !bookmarks.contains(twarrtIDStr) else {
                    return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "twarrt already bookmarked"))
                }
                // add twarrt and return 201
                bookmarks.append(twarrtIDStr)
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel.save(on: req.db).transform(to: .created)
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/bookmark/remove`
    ///
    /// Remove a bookmark of the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the user has not bookmarked any twarrts.
    func bookmarkRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get twarrt
        return Twarrt.findFromParameter("twarrt_id", on: req).addModelID().flatMap {
            (twarrt, twarrtID) in
            // get user's bookmarkedTwarrt barrel
            return user.getBookmarkBarrel(of:.bookmarkedTwarrt, on: req)
            	.unwrap(or: Abort(.badRequest, reason: "user has not bookmarked any twarrts"))
            	.flatMap { (barrel) in
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                // remove twarrt and return 204
                let twarrtID = String(twarrtID)
                if let index = bookmarks.firstIndex(of: twarrtID) {
                    bookmarks.remove(at: index)
                }
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel.save(on: req.db).transform(to: .noContent)
            }
        }
    }
    
    /// `GET /api/v3/twitarr/bookmarks`
    ///
    /// Retrieve all `Twarrt`s the user has bookmarked.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all bookmarked posts.
    func bookmarksHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get bookmarkedTwarrt barrel
        return user.getBookmarkBarrel(of:.bookmarkedTwarrt, on: req).flatMap { (barrel) in
            let bookmarkStrings = barrel?.userInfo["bookmarks"] ?? []
            // convert to IDs
            let bookmarks = bookmarkStrings.compactMap { Int($0) }
            // filter blocks only
            let blocked = req.userCache.getBlocks(userID)
			// get twarrts
			return Twarrt.query(on: req.db)
				.filter(\.$id ~~ bookmarks)
				.filter(\.$author.$id !~ blocked)
				.sort(\.$id, .descending)
				.all()
				.flatMap { (twarrts) in
					return buildTwarrtData(from: twarrts, user: user, on: req, assumeBookmarked: true)
				}
		}
    }
    
    /// `POST /api/v3/twitarr/ID/image`
    ///
    /// Sets the `Twarrt` image to the file uploaded in the HTTP body.
    ///
    /// - Requires: `ImageUploadData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ImageUploadData` containing the filename and image file.
    /// - Throws: 403 error if user does not have permission to modify the twarrt.
    /// - Returns: `TwarrtData` containing the updated image value.
    func imageHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let data = try req.content.decode(ImageUploadData.self)
        // get twarrt
        return Twarrt.findFromParameter("twarrt_id", on: req).addModelID().flatMap { (twarrt, twarrtID) in
            guard twarrt.author.id == userID || user.accessLevel.hasAccess(.moderator) else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot modify twarrt"))
            }
			// get generated filename
			return self.processImage(data: data.image, forType: .twarrt, on: req).throwingFlatMap { (filename) in
				// replace existing image
				if !twarrt.image.isEmpty {
					// archive thumbnail
					DispatchQueue.global(qos: .background).async {
						self.archiveImage(twarrt.image, from: self.imageDir)
					}
					// Save the edit, but don't wait for it to complete
					_ = try TwarrtEdit(twarrt: twarrt).save(on: req.db)
				}
				// update twarrt
				twarrt.image = filename
				return twarrt.save(on: req.db).flatMap { (_) in
					return buildTwarrtData(from: twarrt, user: user, on: req)
				}
			}
		}
    }
    
    /// `POST /api/v3/twitarr/ID/image/remove`
    ///
    /// Remove the image from a `Twarrt`, if there is one. A `TwarrtEdit` record is created
    /// if there was an image to remove.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have permission to modify the twarrt.
    /// - Returns: `TwarrtData` containing the updated image name.
    func imageRemoveHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        return Twarrt.findFromParameter("twarrt_id", on: req).throwingFlatMap { (twarrt) in
            guard twarrt.author.id == userID || user.accessLevel.hasAccess(.moderator) else {
                    throw Abort(.forbidden, reason: "user cannot modify twarrt")
            }
			if !twarrt.image.isEmpty {
				// archive thumbnail
				DispatchQueue.global(qos: .background).async {
					self.archiveImage(twarrt.image, from: self.imageDir)
				}
				// Save the edit
				return try TwarrtEdit(twarrt: twarrt).save(on: req.db).flatMap { (_) in
					// remove image filename from twarrt
					twarrt.image = ""
					return twarrt.save(on: req.db).transform(to: twarrt)
				}
			}
			return req.eventLoop.future(twarrt)
		}.flatMap { (twarrt) in
			return buildTwarrtData(from: twarrt, user: user, on: req)
		}
	}
    
    /// `GET /api/v3/twitarr/likes`
    ///
    /// Retrieve all `Twarrt`s the user has liked.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all liked posts.
    func likesHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        // respect blocks
        let blocked = try req.userCache.getBlocks(user)
		// get liked twarrts
		return user.$twarrtLikes.query(on: req.db)
			.filter(\.$author.$id !~ blocked)
			.all()
			.flatMap { (twarrts) in
				return buildTwarrtData(from: twarrts, user: user, on: req)
		}
    }
    
    /// `GET /api/v3/twitarr/mentions`
    ///
    /// Retrieve all `Twarrt`s whose content mentions the user, in descending timestamp order.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all twarrts containing mentions.
    func mentionsHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        // get query parameters
        let afterID = req.query[Int.self, at: "after"]
        let afterDate = req.query[String.self, at: "afterdate"]
        // respect blocks
        let blocked = try req.userCache.getBlocks(user)

		// get mention twarrts
		var futureTwarrts: EventLoopFuture<[Twarrt]>
		switch (afterID, afterDate) {
			case (.some(let twarrtID), _):
				futureTwarrts = Twarrt.query(on: req.db)
					.filter(\.$author.$id !~ blocked)
					.filter(\.$text, .custom("ILIKE"), "%@\(user.username)%")
					.filter(\.$id > twarrtID)
					.sort(\.$id, .descending)
					.all()
			case (_, .some(let twarrtDate)):
				guard let date = TwitarrController.dateFromParameter(string: twarrtDate) else {
					return req.eventLoop.makeFailedFuture(
						Abort(.badRequest, reason: "not a recognized date format"))
				}
				futureTwarrts = Twarrt.query(on: req.db)
					.filter(\.$author.$id !~ blocked)
					.filter(\.$text, .custom("ILIKE"), "%@\(user.username)%")
					.filter(\.$createdAt > date)
					.sort(\.$createdAt, .descending)
					.all()
			default:
				futureTwarrts = Twarrt.query(on: req.db)
					.filter(\.$author.$id !~ blocked)
					.filter(\.$text, .custom("ILIKE"), "%@\(user.username)%")
					.sort(\.$createdAt, .descending)
					.all()
		}
		return futureTwarrts.flatMap { (twarrts) in
			// get exact username
			let matches = twarrts.compactMap {
				(twarrt) -> Twarrt? in
				let text = twarrt.text.lowercased()
				let words = text.components(separatedBy: .whitespacesAndNewlines + .contentSeparators)
				return words.contains("@\(user.username)") ? twarrt : nil
			}
			// convert to TwarrtData
			return buildTwarrtData(from: matches, user: user, on: req)
		}
    }
    
    /// `POST /api/v3/twitarr/ID/reply`
    ///
    /// Create a `Twarrt` as a reply to an existing twarrt. If the replyTo twarrt is in
    /// quarantine, the post is rejected.
    ///
    /// - Requires: `PostCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCreateData` containing the twarrt's text and optional image.
    /// - Throws: 400 error if the replyTo twarrt is in quarantine.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata.
    func replyHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
		try PostCreateData.validate(content: req)
        let data = try req.content.decode(PostCreateData.self)
        // get replyTo twarrt
        return Twarrt.findFromParameter(":twarrt_id", on: req).flatMap { (replyTo) in
        	do {
				guard !replyTo.isQuarantined else {
					throw Abort(.badRequest, reason: "moderator-bot: twarrt cannot be replied to")
				}
				// process image
				return self.processImage(data: data.imageData, forType: .twarrt, on: req).throwingFlatMap {
					(filename) in
					// create twarrt
					let twarrt = try Twarrt(author: user, text: data.text, image: filename, replyTo: replyTo)
					return twarrt.save(on: req.db).flatMapThrowing { (savedTwarrt) in
						// return as TwarrtData with 201 status
						let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
						let response = Response(status: .created)
						try response.content.encode(try twarrt.convertToData(author: authorHeader, 
								bookmarked: false, userLike: nil, likeCount: 0))
						return response
					}
				}
			}
			catch {
				return req.eventLoop.makeFailedFuture(error)
			}
        }
    }
        
    /// `POST /api/v3/twitarr/create`
    ///
    /// Create a new `Twarrt` in the twitarr stream.
    ///
    /// - Requires: `PostCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCreateData` containing the twarrt's text and optional image.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata.
    func twarrtCreateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
 		try PostCreateData.validate(content: req)
        let data = try req.content.decode(PostCreateData.self)
        // process image
        return self.processImage(data: data.imageData, forType: .twarrt, on: req).throwingFlatMap { (filename) in
            // create twarrt
			let twarrt = try Twarrt(author: user, text: data.text, image: filename)
            return twarrt.save(on: req.db).flatMapThrowing { _ in
                // return as TwarrtData with 201 status
				let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
                let response = Response(status: .created)
                try response.content.encode(
                    try twarrt.convertToData(author: authorHeader, bookmarked: false, userLike: nil, likeCount: 0)
                )
                return response
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/delete`
    ///
    /// Delete the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No COntent on success.
    func twarrtDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        return Twarrt.findFromParameter("twarrt_id", on: req).flatMap {
            (twarrt) in
            guard twarrt.author.id == userID || user.accessLevel.hasAccess(.moderator) else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot delete twarrt"))
            }
            return twarrt.delete(on: req.db).transform(to: .noContent)
        }
    }
    
    /// `POST /api/v3/twitarr/ID/report`
    ///
    /// Create a `Report` regarding the specified `Twarrt`. If the twarrt has reached the report
    /// threshold for auto-quarantining, it is quarantined.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   sent an empty string in the `.message` field.
    ///
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Throws: 400 error if user has already submitted report.
    /// - Returns: 201 Created on success.
    func twarrtReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)
        let parent = try user.parentAccount(on: req)
        let twarrt = Twarrt.findFromParameter("twarrt_id", on: req).addModelID()
        return parent.and(twarrt).throwingFlatMap { (parent, arg1) in
        	let (twarrt, twarrtID) = arg1
			let report = try Report(reportType: .twarrt, reportedID: String(twarrtID),
						submitter: parent, submitterMessage: data.message)
			return twarrt.fileReport(report, on: req)
        }
    }
    
    /// `POST /api/v3/twitarr/ID/laugh`
    ///
    /// Add a "laugh" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtLaughHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
    	return try twarrtReactHandler(req, likeType: .laugh)
    }
    
    /// `POST /api/v3/twitarr/ID/like`
    ///
    /// Add a "like" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
	func twarrtLikeHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
    	return try twarrtReactHandler(req, likeType: .like)
    }

    /// `POST /api/v3/twitarr/ID/love`
    ///
    /// Add a "love" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtLoveHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
    	return try twarrtReactHandler(req, likeType: .love)
    }

    /// Add a  reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
	///  All 3 reaction handlers use this function as they all do the same thing.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
	/// - Parameter likeType: The type of reaction being set.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtReactHandler(_ req: Request, likeType: LikeType) throws -> EventLoopFuture<TwarrtData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get twarrt
        return Twarrt.findFromParameter("twarrt_id", on: req).addModelID().flatMap { (twarrt, twarrtID) in
            guard twarrt.$author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own twarrt"))
            }
			// check for existing like
			return TwarrtLikes.query(on: req.db)
				.filter(\.$user.$id == userID)
				.filter(\.$twarrt.$id == twarrtID)
				.first()
				.throwingFlatMap { (like) in
					let newLike = try like ?? TwarrtLikes(user, twarrt, likeType: .laugh)
					newLike.likeType = likeType
					return newLike.save(on: req.db) .flatMap { (_) in
						return buildTwarrtData(from: twarrt, user: user, on: req)
					}
            }
        }
    }
        
    /// `POST /api/v3/twitarr/ID/unreact`
    ///
    /// Remove a `LikeType` reaction from the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error it there was no existing reaction. 403 error if user is the twarrt's
    ///   creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtUnreactHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get twarrt
        return Twarrt.findFromParameter("twarrt_id", on: req).addModelID().flatMap { (twarrt, twarrtID) in
            guard twarrt.author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own post"))
            }
			// check for existing like
			return TwarrtLikes.query(on: req.db)
				.filter(\.$user.$id == userID)
				.filter(\.$twarrt.$id == twarrtID)
				.first()
				.flatMap { (like) in
					guard like != nil else {
						return req.eventLoop.makeFailedFuture(
								Abort(.badRequest, reason: "user does not have a reaction on the twarrt"))
					}
					// remove pivot
					return twarrt.$likes.detach(user, on: req.db).flatMap { (_) in
						return buildTwarrtData(from: twarrt, user: user, on: req)
					}
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/update`
    ///
    /// Update the specified `Twarrt`.
    ///
    /// - Note: This endpoint only changes the `.text` and `.image` *filename* of the twarrt.
    ///   To change or remove the actual image associated with the twarrt, use
    ///   `POST /api/v3/twitarr/ID/image`  or `POST /api/v3/twitarr/ID/image/remove`.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostContentData` containing the twarrt's text and image filename.
    /// - Throws: 403 error if user is not twarrt owner or has read-only access.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata.
    func twarrtUpdateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		try PostContentData.validate(content: req)
        let data = try req.content.decode(PostContentData.self)
        return Twarrt.findFromParameter("twarrt_id", on: req).flatMap { (twarrt) in
            // ensure user has write access
            guard twarrt.author.id == userID, user.accessLevel.hasAccess(.verified) else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot modify twarrt"))
            }
			// stash current contents
			let twarrtEdit = TwarrtEdit(twarrt: twarrt,
					twarrtContent: PostContentData(text: twarrt.text, image: twarrt.image))
			// update if there are changes
			if twarrt.text != data.text || twarrt.image != data.image {
				twarrt.text = data.text
				twarrt.image = data.image
				return twarrt.save(on: req.db)
					.flatMap { twarrtEdit.save(on: req.db) }
					.transform(to: twarrt)
			}
			return req.eventLoop.future(twarrt)
		}
		.flatMap { (twarrt: Twarrt) in
			return buildTwarrtData(from: twarrt, user: user, on: req).flatMapThrowing { (twarrtData) in
				// return updated twarrt as TwarrtData, with 201 status
				let response = Response(status: .created)
				try response.content.encode(twarrtData)
				return response
			}
		}
    }
    
    /// `GET /api/v3/twitarr/user`
    ///
    /// Retrieve all `Twarrt`s authored by the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all twarrts containing mentions.
    func userHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        // get twarrts
        return user.$twarrts.query(on: req.db)
            .sort(\.$createdAt, .ascending)
            .all()
            .flatMap { (twarrts) in
                // convert to TwarrtData
				return buildTwarrtData(from: twarrts, user: user, on: req)
        	}
    }

}

extension TwitarrController {
	// Builds a TwarrtData from a Twarrt. Somewhat stupidly, uses the array builder to do its work,
	// instead of the other way around.
	func buildTwarrtData(from twarrt: Twarrt, user: User, on req: Request) -> EventLoopFuture<TwarrtData> {
		return buildTwarrtData(from: [twarrt], user: user, on: req)
			.flatMapThrowing { (twarrtData: [TwarrtData]) in
				guard let result = twarrtData.first else {
					throw Abort(.internalServerError, reason: "Twarrt not found.")
				}
				return result
		}
	}

	// Builds an array of TwarrtDatas from an array of Twarrts.
	func buildTwarrtData(from twarrts: [Twarrt], user: User, on req: Request, 
			filters: CachedFilters? = nil, assumeBookmarked: Bool? = nil, matchHashtag: String? = nil) -> EventLoopFuture<[TwarrtData]> {
		do {
			// remove muteword twarrts
			var filteredTwarrts = twarrts
			if let mutewords = filters?.mutewords {
				 filteredTwarrts = twarrts.compactMap { $0.filterMutewords(using: mutewords) }
			}
			
			// get exact hashtag if we're matching on hashtag
			if let hashtag = matchHashtag {
				filteredTwarrts = filteredTwarrts.compactMap { (filteredTwarrt) -> Twarrt? in
					let text = filteredTwarrt.text.lowercased()
					let words = text.components(separatedBy: .whitespacesAndNewlines + .contentSeparators)
					return words.contains(hashtag) ? filteredTwarrt : nil
				}
			}

			// convert to an array TwarrtData futures
			let futures = try filteredTwarrts.map { (twarrt) -> EventLoopFuture<TwarrtData> in
      			let author = try req.userCache.getHeader(twarrt.$author.id)
				let bookmarked = assumeBookmarked == nil ? user.hasBookmarked(twarrt, on: req) :
						req.eventLoop.makeSucceededFuture(assumeBookmarked!)
				let userLike: EventLoopFuture<TwarrtLikes?>
				if try author.userID == user.requireID() {
					// A use cannot like their own content, ergo there's no userLike for a user's own twarrt.
					userLike = req.eventLoop.future(nil)
				}
				else {
					userLike = try TwarrtLikes.query(on: req.db)
						.filter(\.$twarrt.$id == twarrt.requireID())
						.filter(\.$user.$id == user.requireID())
						.first()
				}
				let likeCount = try TwarrtLikes.query(on: req.db)
					.filter(\.$twarrt.$id == twarrt.requireID())
					.count()
				return bookmarked.and(userLike).and(likeCount).flatMapThrowing {
					(arg0, count) in
					let (bookmarked, userLike) = arg0
					return try twarrt.convertToData(author: author, bookmarked: bookmarked, 
							userLike: userLike?.likeType, likeCount: count)
				}
			}
			return futures.flatten(on: req.eventLoop)
		}
		catch {
			return req.eventLoop.makeFailedFuture(error)
		}
	}
	
	
}

// twarrts can contain images
extension TwitarrController: ImageHandler {
    /// The base directory for storing Twarrt images.
    var imageDir: String {
        return "images/twitarr/"
    }
    
    /// The height of Twarrt image thumbnails.
    var thumbnailHeight: Int {
        return 100
    }
}


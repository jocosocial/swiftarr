import Fluent
import Vapor

/// Provides API endpoints for the Quartermaster "have / need" item board.
///
/// Quartermaster is a standalone searchable database of items that cruise guests are offering
/// or looking for, modeled on the Fez/LFG subsystem. All endpoints require a logged-in user
/// (cruise-internal contact info). Creating and editing items requires the standard content guard
/// (blocks banned/quarantined users).
///
/// All routes are gated by the `.quartermaster` feature flag and accept Bearer token auth only.
///
/// Routes registered by this controller:
///
///     GET  /api/v3/quartermaster                    list items (filters: category, search, mine)
///     GET  /api/v3/quartermaster/:quartermaster_id  get a single item
///     POST /api/v3/quartermaster/create             batch-create one or more items
///     POST /api/v3/quartermaster/:id/update         update a single item
///     POST /api/v3/quartermaster/:id/delete         soft-delete an item
///  DELETE  /api/v3/quartermaster/:id               soft-delete an item (REST alias)
///     POST /api/v3/quartermaster/:id/report         report an item to the mod queue
struct QuartermasterController: APIRouteCollection {

	// MARK: - Route Registration

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		let base = app.grouped("api", "v3", "quartermaster")
		let tokenAuth = base.tokenRoutes(feature: .quartermaster)
		tokenAuth.get("", use: listHandler)
		tokenAuth.get(quartermasterIDParam, use: getHandler)
		tokenAuth.post("create", use: createHandler)
		tokenAuth.post(quartermasterIDParam, "update", use: updateHandler)
		tokenAuth.post(quartermasterIDParam, "delete", use: deleteHandler)
		tokenAuth.delete(quartermasterIDParam, use: deleteHandler)
		tokenAuth.post(quartermasterIDParam, "report", use: reportHandler)
	}

	// MARK: - URL Query Struct

	/// URL query parameters accepted by `listHandler`.
	struct QuartermasterURLQueryStruct: Content {
		/// Filter to items in this category. Case-insensitive; `"have"` or `"need"`.
		var category: String?
		/// Full-text search string. Matches item name, description, and location via a tsvector index.
		var search: String?
		/// If `true`, return only items owned by the authenticated user.
		var mine: Bool?
		var start: Int?
		var limit: Int?

		/// Parses the optional `category` string into a `QuartermasterCategory`.
		/// Returns `nil` when the parameter was not supplied; throws 400 on unknown values.
		func getCategory() throws -> QuartermasterCategory? {
			return try category.map { try QuartermasterCategory.fromAPIString($0) }
		}

		var pagination: Pagination {
			Pagination(start: start, limit: limit, maxPageSize: Settings.shared.maximumTwarrts)
		}
	}

	// MARK: - Handlers

	/// `GET /api/v3/quartermaster`
	///
	/// Returns a paginated list of Quartermaster items, sorted by most-recently-modified first.
	/// Items owned by blocked users are excluded from results.
	///
	/// **Query Parameters:**
	/// - `category=have|need` — filter to one category
	/// - `search=<string>` — full-text search across name, description, and location
	/// - `mine=true` — return only the authenticated user's own items
	/// - `start=<n>` / `limit=<n>` — pagination (max size: `Settings.shared.maximumTwarrts`)
	///
	/// - Throws: 400 if `category` is not a recognized value; 401 if unauthenticated.
	/// - Returns: `QuartermasterListData`
	func listHandler(_ req: Request) async throws -> QuartermasterListData {
		let urlQuery = try req.query.decode(QuartermasterURLQueryStruct.self)
		let pagination = urlQuery.pagination
		let cacheUser = try req.auth.require(UserCacheData.self)

		let query = QuartermasterItem.query(on: req.db)
			.filter(\.$owner.$id !~ cacheUser.getBlocks())

		if urlQuery.mine == true {
			query.filter(\.$owner.$id == cacheUser.userID)
		}
		if let cat = try urlQuery.getCategory() {
			query.filter(\.$category == cat)
		}
		if var searchStr = urlQuery.search {
			searchStr = searchStr.escapedForSQLWildcards()
			if !searchStr.isEmpty {
				query.group(.or) { or in
					or.fullTextFilter(\.$itemName, searchStr)
					or.fullTextFilter(\.$itemDescription, searchStr)
					or.fullTextFilter(\.$location, searchStr)
				}
			}
		}

		let total = try await query.copy().count()
		let items = try await query.sort(\.$updatedAt, .descending).range(pagination.range).all()

		let itemDataArray: [QuartermasterData] = try items.map { item in
			let ownerHeader = try req.userCache.getHeader(item.$owner.id)
			let contactHeader = try item.$contactUser.id.map { try req.userCache.getHeader($0) }
			return try QuartermasterData(item: item, owner: ownerHeader, contactUser: contactHeader)
		}
		return QuartermasterListData(
			paginator: Paginator(total: total, start: pagination.start, limit: pagination.limit),
			items: itemDataArray
		)
	}

	/// `GET /api/v3/quartermaster/:quartermaster_id`
	///
	/// Returns the details for a single Quartermaster item.
	///
	/// - Throws: 400 if item not found or owner is blocked; 401 if unauthenticated.
	/// - Returns: `QuartermasterData`
	func getHandler(_ req: Request) async throws -> QuartermasterData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let item = try await findItem(on: req)
		guard !cacheUser.getBlocks().contains(item.$owner.id) else {
			throw Abort(.badRequest, reason: "Item not found.")
		}
		let ownerHeader = try req.userCache.getHeader(item.$owner.id)
		let contactHeader = try item.$contactUser.id.map { try req.userCache.getHeader($0) }
		return try QuartermasterData(item: item, owner: ownerHeader, contactUser: contactHeader)
	}

	/// `POST /api/v3/quartermaster/create`
	///
	/// Creates one or more `QuartermasterItem`s in a single batch. All items share the same
	/// `category`, `location`, and `contactUsername`; each item has its own `itemName` and
	/// optional `itemDescription`. All items are saved inside a single transaction so the batch
	/// is all-or-nothing.
	///
	/// At least one of `location` or `contactUsername` must be supplied.
	///
	/// - Throws: 400 on validation failure or unknown `contactUsername`; 401 if unauthenticated;
	///   403 if the user cannot create content (banned/quarantined).
	/// - Returns: `[QuartermasterData]` with HTTP 201 Created.
	func createHandler(_ req: Request) async throws -> Response {
		let data = try ValidatingJSONDecoder().decode(QuartermasterCreateData.self, fromBodyOf: req)
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()

		// Resolve the optional shared contact user once, before entering the transaction.
		let contactUserID: UUID?
		if let username = data.contactUsername, !username.isEmpty {
			guard let contactUser = req.userCache.getUser(username: username) else {
				throw Abort(.badRequest, reason: "User '@\(username)' not found.")
			}
			contactUserID = contactUser.userID
		}
		else {
			contactUserID = nil
		}

		let ownerHeader = cacheUser.makeHeader()
		let contactHeader = try contactUserID.map { try req.userCache.getHeader($0) }

		let savedItems: [QuartermasterData] = try await req.db.transaction { db in
			var results: [QuartermasterData] = []
			for entry in data.items {
				let item = QuartermasterItem(
					ownerID: cacheUser.userID,
					category: data.category,
					itemName: entry.itemName,
					itemDescription: entry.itemDescription,
					location: data.location,
					contactUserID: contactUserID
				)
				try await item.save(on: db)
				results.append(try QuartermasterData(item: item, owner: ownerHeader, contactUser: contactHeader))
			}
			return results
		}

		let response = Response(status: .created)
		try response.content.encode(savedItems)
		return response
	}

	/// `POST /api/v3/quartermaster/:quartermaster_id/update`
	///
	/// Updates a single Quartermaster item. The owner may update any field; a moderator may also
	/// update items belonging to other users.
	///
	/// When any text field (`itemName`, `itemDescription`, or `location`) changes, a
	/// `QuartermasterItemEdit` is created first to snapshot the prior state for mod accountability.
	/// Category-only changes do **not** create an edit record.
	///
	/// - Throws: 400 on validation failure, unknown `contactUsername`, or item not found;
	///   401 if unauthenticated; 403 if the caller cannot modify this item.
	/// - Returns: `QuartermasterData`
	func updateHandler(_ req: Request) async throws -> QuartermasterData {
		let data = try ValidatingJSONDecoder().decode(QuartermasterContentData.self, fromBodyOf: req)
		let cacheUser = try req.auth.require(UserCacheData.self)
		let item = try await findItem(on: req)
		try cacheUser.guardCanModifyContent(item)

		// Resolve the new contact user if specified.
		let newContactUserID: UUID?
		if let username = data.contactUsername, !username.isEmpty {
			guard let contactUser = req.userCache.getUser(username: username) else {
				throw Abort(.badRequest, reason: "User '@\(username)' not found.")
			}
			newContactUserID = contactUser.userID
		}
		else {
			newContactUserID = nil
		}

		// Snapshot the current text fields before applying changes, only when text actually changed.
		let contentChanged = data.itemName != item.itemName
			|| data.itemDescription != item.itemDescription
			|| data.location != item.location
			|| newContactUserID != item.$contactUser.id
		if contentChanged {
			let edit = try QuartermasterItemEdit(item: item, editorID: cacheUser.userID)
			try await item.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
			try await edit.save(on: req.db)
		}

		// Apply new values.
		item.category = data.category
		item.itemName = data.itemName
		item.itemDescription = data.itemDescription
		item.location = data.location
		item.$contactUser.id = newContactUserID
		try await item.save(on: req.db)

		let ownerHeader = try req.userCache.getHeader(item.$owner.id)
		let contactHeader = try newContactUserID.map { try req.userCache.getHeader($0) }
		return try QuartermasterData(item: item, owner: ownerHeader, contactUser: contactHeader)
	}

	/// `POST /api/v3/quartermaster/:quartermaster_id/delete`
	/// `DELETE /api/v3/quartermaster/:quartermaster_id`
	///
	/// Soft-deletes a Quartermaster item. The item's owner may delete their own item; a moderator
	/// may delete any item. The soft-delete timestamp is recorded so moderators can still view
	/// deleted items during review.
	///
	/// - Throws: 400 if item not found; 401 if unauthenticated;
	///   403 if the caller is neither the owner nor a moderator.
	/// - Returns: HTTP 204 No Content.
	func deleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let item = try await findItem(on: req)
		guard cacheUser.userID == item.$owner.id || cacheUser.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have permission to delete this item.")
		}
		try cacheUser.guardCanModifyContent(item)
		try await item.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		try await item.delete(on: req.db)
		return .noContent
	}

	// MARK: - Private Helpers

	/// Looks up the `QuartermasterItem` identified by `quartermasterIDParam`, converting a
	/// not-found result to a 400 Bad Request per the Swiftarr API convention (404 is reserved
	/// for endpoints that do not exist).
	private func findItem(on req: Request) async throws -> QuartermasterItem {
		do {
			return try await QuartermasterItem.findFromParameter(quartermasterIDParam, on: req)
		}
		catch let abort as Abort where abort.status == .notFound {
			throw Abort(.badRequest, reason: abort.reason)
		}
	}

	/// `POST /api/v3/quartermaster/:quartermaster_id/report`
	///
	/// Files a report against a Quartermaster item, feeding it into the moderation queue.
	/// Duplicate reports from the same user are silently ignored. No auto-quarantine occurs —
	/// moderators must manually quarantine items.
	///
	/// - Throws: 400 if item not found; 401 if unauthenticated.
	/// - Returns: HTTP 201 Created.
	func reportHandler(_ req: Request) async throws -> HTTPStatus {
		let submitter = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let item = try await findItem(on: req)
		return try await item.fileReport(submitter: submitter, submitterMessage: data.message, on: req)
	}
}

import Vapor

// Form data from the Add Item(s) / Edit Item form. Each row is a fixed slot of THREE discrete,
// independently-optional fields (itemNameN / itemDescriptionN / itemImageN) rather than parallel
// arrays -- earlier this used shared-name `itemName`/`itemDescription` arrays (relying on Vapor's
// multipart decoder to collect repeated same-named text parts into `[String]`), which happened to
// work in isolation, but broke the moment file fields were added alongside: mixing an array-typed
// field into the same keyed multipart container as several sibling Optional scalar fields corrupted
// decoding of the array field too (confirmed empirically: even 2 rows failed with "expected array but
// encountered single value" once file fields joined the struct). `messagePostForm.html`'s
// `MessagePostFormContent` sidesteps this the same way, with discrete `localPhoto1...8` fields instead
// of an array -- this struct now follows that same proven pattern for every per-row field.
//
// Rows are kept aligned with their slot index by `swiftarr.js`'s `renumberQmRowInputs()`, which
// renumbers every row's three field names by DOM position after any add/remove.
struct QuartermasterFormContent: Codable {
	static let maxRows = 10

	var category: String
	var location: String?
	// Checkbox input: present (value "on") when checked, absent from the form body when unchecked.
	var hideOwnerName: String?
	var itemName0: String?
	var itemDescription0: String?
	var itemImage0: Data?
	var itemName1: String?
	var itemDescription1: String?
	var itemImage1: Data?
	var itemName2: String?
	var itemDescription2: String?
	var itemImage2: Data?
	var itemName3: String?
	var itemDescription3: String?
	var itemImage3: Data?
	var itemName4: String?
	var itemDescription4: String?
	var itemImage4: Data?
	var itemName5: String?
	var itemDescription5: String?
	var itemImage5: Data?
	var itemName6: String?
	var itemDescription6: String?
	var itemImage6: Data?
	var itemName7: String?
	var itemDescription7: String?
	var itemImage7: Data?
	var itemName8: String?
	var itemDescription8: String?
	var itemImage8: Data?
	var itemName9: String?
	var itemDescription9: String?
	var itemImage9: Data?
	// Edit-only (row 0 always): the item's existing image filename, carried in a hidden field so
	// re-submitting without picking a new file doesn't drop the photo.
	var currentItemImage: String?
	// Edit-only: checkbox, present (value "on") when the user wants to remove the item's photo
	// without replacing it.
	var removeItemImage: String?

	// One tuple per row slot, in position order (see the type-level doc comment for why these are
	// discrete fields rather than parallel arrays).
	private var rows: [(name: String?, description: String?, image: Data?)] {
		[
			(itemName0, itemDescription0, itemImage0),
			(itemName1, itemDescription1, itemImage1),
			(itemName2, itemDescription2, itemImage2),
			(itemName3, itemDescription3, itemImage3),
			(itemName4, itemDescription4, itemImage4),
			(itemName5, itemDescription5, itemImage5),
			(itemName6, itemDescription6, itemImage6),
			(itemName7, itemDescription7, itemImage7),
			(itemName8, itemDescription8, itemImage8),
			(itemName9, itemDescription9, itemImage9),
		]
	}

	// Trims a field down to nil-if-empty, the way the API expects optional text fields.
	private static func nilIfEmpty(_ str: String?) -> String? {
		guard let trimmed = str?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
			return nil
		}
		return trimmed
	}

	// Builds entries from every row slot with a non-blank name, trimming whitespace and normalizing
	// blank descriptions/images to nil. Throws if no usable rows remain. `image` here only ever
	// reflects a newly-chosen file -- reconciling that against an existing image is
	// `buildContentData()`'s job, since only the single-row edit form has one.
	func buildItemEntries() throws -> [QuartermasterItemEntry] {
		var entries: [QuartermasterItemEntry] = []
		for row in rows {
			guard let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
				continue
			}
			let imageData = row.image
			entries.append(QuartermasterItemEntry(
				itemName: name,
				itemDescription: Self.nilIfEmpty(row.description),
				image: (imageData?.isEmpty ?? true) ? nil : ImageUploadData(nil, imageData)
			))
		}
		guard !entries.isEmpty else {
			throw Abort(.badRequest, reason: "At least one item must have a name.")
		}
		return entries
	}

	// Builds the batch-create DTO from every usable row. Used by POST /quartermaster/create.
	func buildCreateData() throws -> QuartermasterCreateData {
		return QuartermasterCreateData(
			category: try QuartermasterCategory.fromAPIString(category),
			location: Self.nilIfEmpty(location),
			hideOwnerName: hideOwnerName == "on",
			items: try buildItemEntries()
		)
	}

	// Builds the single-item update DTO from row 0 only. Used by POST /quartermaster/ID/update.
	// Combines the new-file-per-row zip from buildItemEntries() with the edit form's existing-image
	// and remove-image fields to produce the item's full desired image state.
	func buildContentData() throws -> QuartermasterContentData {
		let firstEntry = try buildItemEntries()[0]
		let keepExistingFilename = removeItemImage == "on" ? nil : Self.nilIfEmpty(currentItemImage)
		let image: ImageUploadData? = (firstEntry.image != nil || keepExistingFilename != nil)
			? ImageUploadData(keepExistingFilename, firstEntry.image?.image)
			: nil
		return QuartermasterContentData(
			category: try QuartermasterCategory.fromAPIString(category),
			itemName: firstEntry.itemName,
			itemDescription: firstEntry.itemDescription,
			location: Self.nilIfEmpty(location),
			hideOwnerName: hideOwnerName == "on",
			image: image
		)
	}
}

// Leaf context used by the Have, Need, and Owned list pages. All three tabs share one template.
struct QuartermasterListPageContext: Encodable {
	enum QMTab: String, Codable {
		case about, have, need, owned
	}

	struct QueryParams: Content {
		var category: String?
	}

	// The Owned tab's category filter has no query param for "show everything" -- absence of the
	// param means "all". Pulled out as a static fn so the mapping is unit-testable without a Request.
	static func categorySelection(from requestedCategory: String?) -> String {
		return requestedCategory ?? "all"
	}

	var trunk: TrunkContext
	var itemList: QuartermasterListData
	var paginator: PaginatorContext
	var tab: QMTab
	var searchText: String
	var searchPlaceholder: String
	var searchActionPath: String
	var categorySelection: String  // "all" | "have" | "need" -- Owned tab only; ignored elsewhere.
	var addItemURL: String  // Pre-selects the Have/Need category on the create page; Owned defaults to Have.
	var showCategoryBadge: Bool
	// Fed into each item's Edit link as `?from=`, so editing and returning lands back on this tab.
	// See `QuartermasterCreateUpdatePageContext.successURL(from:)`.
	var editReturnTo: String
	var filterAllURL: String
	var filterHaveURL: String
	var filterNeedURL: String

	init(_ req: Request, itemList: QuartermasterListData, tab: QMTab) throws {
		let params = try req.query.decode(QueryParams.self)
		let title: String
		let basePath: String
		switch tab {
			case .about:
				title = "Quartermastarr"
				basePath = "/quartermaster/about"
			case .have:
				title = "Quartermastarr: Have"
				basePath = "/quartermaster"
			case .need:
				title = "Quartermastarr: Need"
				basePath = "/quartermaster/need"
			case .owned:
				title = "Quartermastarr: Owned"
				basePath = "/quartermaster/owned"
		}
		trunk = .init(req, title: title, tab: .quartermaster)
		self.itemList = itemList
		self.tab = tab
		let searchText = req.query[String.self, at: "search"] ?? ""
		self.searchText = searchText
		switch tab {
			case .have: searchPlaceholder = "Search items people have"
			case .need: searchPlaceholder = "Search items people need"
			case .owned: searchPlaceholder = "Search your items"
			case .about: searchPlaceholder = ""
		}
		searchActionPath = basePath
		categorySelection = Self.categorySelection(from: params.category)
		switch tab {
			case .have: addItemURL = "/quartermaster/create?category=have&from=have"
			case .need: addItemURL = "/quartermaster/create?category=need&from=need"
			case .owned: addItemURL = "/quartermaster/create?from=owned"
			case .about: addItemURL = "/quartermaster/create"
		}
		showCategoryBadge = tab == .owned
		editReturnTo = tab.rawValue

		let searchQueryPart = searchText.isEmpty
			? nil : searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).map { "search=\($0)" }
		filterAllURL = "/quartermaster/owned" + (searchQueryPart.map { "?\($0)" } ?? "")
		filterHaveURL = "/quartermaster/owned?category=have" + (searchQueryPart.map { "&\($0)" } ?? "")
		filterNeedURL = "/quartermaster/owned?category=need" + (searchQueryPart.map { "&\($0)" } ?? "")

		// Only the Owned tab has a user-facing category selector; Have/Need bake their category into
		// the API call itself and don't need it echoed into the pagination URL.
		let categoryForPagination = tab == .owned ? params.category : nil
		let limit = itemList.paginator.limit
		paginator = .init(itemList.paginator) { pageIndex in
			var url = "\(basePath)?start=\(pageIndex * limit)&limit=\(limit)"
			if let category = categoryForPagination {
				url += "&category=\(category)"
			}
			if let searchQueryPart = searchQueryPart {
				url += "&\(searchQueryPart)"
			}
			return url
		}
	}
}

// Leaf context used by the single-item detail page (GET /quartermaster/ID). Reuses the same
// Quartermaster/quartermasterItem partial the list pages render each row with, so it carries the
// same trunk/showCategoryBadge/editReturnTo shape that partial expects (see its header comment).
struct QuartermasterItemPageContext: Encodable {
	var trunk: TrunkContext
	var item: QuartermasterData
	// Always shown here, unlike the list pages, since there's no enclosing tab to imply the category.
	var showCategoryBadge: Bool = true
	// The item's own ID: editing from here and returning lands back on this same item page. See
	// `QuartermasterCreateUpdatePageContext.successURL(from:)`.
	var editReturnTo: String

	init(_ req: Request, item: QuartermasterData) throws {
		trunk = .init(req, title: "Quartermastarr: \(item.itemName)", tab: .quartermaster)
		self.item = item
		editReturnTo = item.itemID.uuidString
	}
}

// Leaf context used by the Add Item(s) and Edit Item pages. One template serves both; in edit mode
// there's exactly one (locked) item row and the "add another row" button is hidden.
struct QuartermasterCreateUpdatePageContext: Encodable {
	struct ItemRow: Encodable {
		var itemName: String
		var itemDescription: String
		// The existing image's filename (edit only; empty for a fresh create row). Rendered into a
		// hidden `currentItemImage` field so re-submitting without picking a new file keeps the photo.
		var itemImage: String = ""
		// Thumbnail URL for the existing image, or "" when there isn't one. Precomputed here rather
		// than in Leaf since it's just string concatenation over `itemImage`.
		var itemImageThumbURL: String = ""
		// Leaf's `#if` doesn't treat an empty String as falsy the way it does Bool/Optional, so the
		// template needs an explicit Bool to decide whether to show the existing-photo preview. Must
		// be a stored property (not computed) since synthesized Encodable only encodes stored ones.
		var hasImage: Bool = false
	}

	var trunk: TrunkContext
	var pageTitle: String
	var formAction: String
	var submitButtonTitle: String = "Add Item(s)"
	var category: String = "have"
	var location: String = ""
	var hideOwnerName: Bool = false
	var items: [ItemRow]
	var isEdit: Bool
	var maxRows: Int = QuartermasterFormContent.maxRows
	// Where the ajax form sends the browser after a successful submit. Carries the tab the user
	// followed the Add Item(s)/Edit link from (via `?from=`) so submitting returns them to that
	// same tab instead of always landing on Owned.
	var successURL: String

	// Maps a `?from=` query value to where the ajax form should send the browser next. The value is
	// either a `QuartermasterListPageContext.QMTab` raw value (edited from a list page: return to
	// that tab) or a Quartermaster item ID (edited from that item's own detail page: return there).
	// Falls back to Owned when the param is missing or unrecognized.
	private static func successURL(from req: Request) -> String {
		switch req.query[String.self, at: "from"] {
			case "have": return "/quartermaster"
			case "need": return "/quartermaster/need"
			case .some(let itemID) where UUID(uuidString: itemID) != nil: return "/quartermaster/\(itemID)"
			default: return "/quartermaster/owned"
		}
	}

	// Create: empty header, one blank starting row, name shown by default. The category dropdown
	// preselects to whichever of Have/Need the caller followed the "Add Item(s)" link from, via an
	// optional `?category=` query param; an absent or invalid value falls back to the "have" default.
	init(_ req: Request) throws {
		trunk = .init(req, title: "Add Quartermastarr Item(s)", tab: .quartermaster)
		pageTitle = "Add Item(s)"
		formAction = "/quartermaster/create"
		if let requestedCategory = req.query[String.self, at: "category"],
			let parsedCategory = try? QuartermasterCategory.fromAPIString(requestedCategory)
		{
			category = parsedCategory.rawValue
		}
		items = [ItemRow(itemName: "", itemDescription: "")]
		isEdit = false
		successURL = Self.successURL(from: req)
	}

	// Edit: prefill everything from the existing item; exactly one row, locked.
	init(_ req: Request, item: QuartermasterData) throws {
		trunk = .init(req, title: "Edit Quartermastarr Item", tab: .quartermaster)
		pageTitle = "Edit Item"
		formAction = "/quartermaster/\(item.itemID)/update"
		submitButtonTitle = "Save"
		category = item.category.rawValue
		location = item.location ?? ""
		hideOwnerName = item.hideOwnerName
		let imageFilename = item.image ?? ""
		items = [ItemRow(
			itemName: item.itemName,
			itemDescription: item.itemDescription ?? "",
			itemImage: imageFilename,
			itemImageThumbURL: imageFilename.isEmpty ? "" : "/api/v3/image/thumb/\(imageFilename)",
			hasImage: !imageFilename.isEmpty
		)]
		isEdit = true
		successURL = Self.successURL(from: req)
	}
}

/// Pages for browsing, searching, creating, editing, and reporting Quartermaster items -- the
/// "have / need" item board. See `QuartermasterController` for the API layer this calls into.
struct SiteQuartermasterController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- two logged-in users could share
		// this URL and both see the content.
		let globalRoutes = getGlobalRoutes(app).grouped("quartermaster")
			.grouped(DisabledSiteSectionMiddleware(feature: .quartermaster))
		globalRoutes.get("", use: haveListPageHandler).destination("the Quartermastarr Have list")
		globalRoutes.get("need", use: needListPageHandler).destination("the Quartermastarr Need list")
		globalRoutes.get("owned", use: ownedListPageHandler).destination("your Quartermastarr items")
		globalRoutes.get("about", use: aboutPageHandler).destination("the Quartermastarr description")
		globalRoutes.get(quartermasterIDParam, use: itemPageHandler).destination("this Quartermastarr item")

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped("quartermaster")
			.grouped(DisabledSiteSectionMiddleware(feature: .quartermaster))
		privateRoutes.get("create", use: createPageHandler)
		privateRoutes.on(
			.POST, "create",
			body: .collect(maxSize: ByteCount(value: Settings.shared.imageMaxBodySize)),
			use: createPostHandler
		)
		privateRoutes.get(quartermasterIDParam, "edit", use: editPageHandler)
		privateRoutes.on(
			.POST, quartermasterIDParam, "update",
			body: .collect(maxSize: ByteCount(value: Settings.shared.imageMaxBodySize)),
			use: updatePostHandler
		)
		privateRoutes.post(quartermasterIDParam, "delete", use: deletePostHandler)
		privateRoutes.delete(quartermasterIDParam, use: deletePostHandler)
		privateRoutes.get("report", quartermasterIDParam, use: reportPageHandler)
		privateRoutes.post("report", quartermasterIDParam, use: reportPostHandler)
	}

	// MARK: - Quartermaster

	// Shared body for the three list tabs. `queryItems` bakes in the tab's fixed filter (category
	// for Have/Need, mine=true for Owned); passThroughQuery forwards search/start/limit, and, for
	// Owned, the user-chosen category filter, straight through to the API.
	private func renderList(_ req: Request, tab: QuartermasterListPageContext.QMTab, queryItems: [URLQueryItem])
		async throws -> View
	{
		let response = try await apiQuery(req, endpoint: "/quartermaster", query: queryItems, passThroughQuery: true)
		let itemList = try response.content.decode(QuartermasterListData.self)
		let ctx = try QuartermasterListPageContext(req, itemList: itemList, tab: tab)
		return try await req.view.render("Quartermaster/quartermasterList", ctx)
	}

	// GET /quartermaster
	// Shows items everyone has to offer. Also supports search by passing through the query.
	func haveListPageHandler(_ req: Request) async throws -> View {
		try await renderList(req, tab: .have, queryItems: [URLQueryItem(name: "category", value: "have")])
	}

	// GET /quartermaster/need
	// Shows items everyone is looking for. Also supports search by passing through the query.
	func needListPageHandler(_ req: Request) async throws -> View {
		try await renderList(req, tab: .need, queryItems: [URLQueryItem(name: "category", value: "need")])
	}

	// GET /quartermaster/owned
	// Shows the current user's own items, of either category. Supports an optional `?category=`
	// filter (from the All/Have/Need buttons) plus search, both forwarded via passThroughQuery.
	func ownedListPageHandler(_ req: Request) async throws -> View {
		try await renderList(req, tab: .owned, queryItems: [URLQueryItem(name: "mine", value: "true")])
	}

	// GET /quartermaster/about
	// Shows a static description of the Quartermaster board.
	func aboutPageHandler(_ req: Request) async throws -> View {
		struct QuartermasterAboutPageContext: Encodable {
			var trunk: TrunkContext
			var tab: QuartermasterListPageContext.QMTab

			init(_ req: Request) throws {
				trunk = .init(req, title: "Quartermastarr", tab: .quartermaster)
				tab = .about
			}
		}
		let ctx = try QuartermasterAboutPageContext(req)
		return try await req.view.render("Quartermaster/quartermasterAbout", ctx)
	}

	// GET /quartermaster/ID
	// Shows a single item's detail page. Exists so a shared link to one item (e.g. via the "Send
	// Seamail" reply, or just copying the URL) resolves to something useful, instead of only ever
	// being reachable by scrolling through the Have/Need/Owned lists.
	func itemPageHandler(_ req: Request) async throws -> View {
		guard let itemID = req.parameters.get(quartermasterIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing quartermaster_id")
		}
		let response = try await apiQuery(req, endpoint: "/quartermaster/\(itemID)")
		let item = try response.content.decode(QuartermasterData.self)
		let ctx = try QuartermasterItemPageContext(req, item: item)
		return try await req.view.render("Quartermaster/quartermasterItemPage", ctx)
	}

	// GET /quartermaster/create
	// Shows the Add Item(s) page.
	func createPageHandler(_ req: Request) async throws -> View {
		let ctx = try QuartermasterCreateUpdatePageContext(req)
		return try await req.view.render("Quartermaster/quartermasterCreate", ctx)
	}

	// GET /quartermaster/ID/edit
	// Shows the Edit Item page, prefilled from the existing item.
	func editPageHandler(_ req: Request) async throws -> View {
		guard let itemID = req.parameters.get(quartermasterIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing quartermaster_id")
		}
		let response = try await apiQuery(req, endpoint: "/quartermaster/\(itemID)")
		let item = try response.content.decode(QuartermasterData.self)
		let ctx = try QuartermasterCreateUpdatePageContext(req, item: item)
		return try await req.view.render("Quartermaster/quartermasterCreate", ctx)
	}

	// POST /quartermaster/create
	// Handles the POST from the Add Item(s) page. Submits every filled-in row as one batch.
	func createPostHandler(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(QuartermasterFormContent.self)
		let createData = try postStruct.buildCreateData()
		try await apiQuery(req, endpoint: "/quartermaster/create", method: .POST, encodeContent: createData)
		return .created
	}

	// POST /quartermaster/ID/update
	// Handles the POST from the Edit Item page.
	func updatePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let itemID = req.parameters.get(quartermasterIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing quartermaster_id")
		}
		let postStruct = try req.content.decode(QuartermasterFormContent.self)
		let contentData = try postStruct.buildContentData()
		try await apiQuery(req, endpoint: "/quartermaster/\(itemID)/update", method: .POST, encodeContent: contentData)
		return .created
	}

	// POST /quartermaster/ID/delete
	// DELETE /quartermaster/ID
	// Deletes an item. Owner or moderator only.
	func deletePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let itemID = req.parameters.get(quartermasterIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing quartermaster_id")
		}
		let response = try await apiQuery(req, endpoint: "/quartermaster/\(itemID)", method: .DELETE)
		return response.status
	}

	// GET /quartermaster/report/ID
	// Shows the page for reporting a Quartermaster item.
	func reportPageHandler(_ req: Request) async throws -> View {
		guard let itemID = req.parameters.get(quartermasterIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing quartermaster_id")
		}
		let ctx = try ReportPageContext(req, quartermasterItemID: itemID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /quartermaster/report/ID
	// Submits a report on a Quartermaster item.
	func reportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let itemID = req.parameters.get(quartermasterIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing quartermaster_id")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/quartermaster/\(itemID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}
}

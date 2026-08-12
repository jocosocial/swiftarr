import Vapor

// Form data from the Add Item(s) / Edit Item form. `itemName` and `itemDescription` are parallel
// arrays -- one entry per item row. The browser sends repeated `itemName=`/`itemDescription=` pairs
// (one per row, all sharing the same field name), which Vapor's URLEncodedFormDecoder collects into
// arrays without needing a `[]` suffix on the field name.
struct QuartermasterFormContent: Codable {
	var category: String
	var location: String?
	// Checkbox input: present (value "on") when checked, absent from the form body when unchecked.
	var hideOwnerName: String?
	var itemName: [String]
	var itemDescription: [String]

	// Trims a field down to nil-if-empty, the way the API expects optional text fields.
	private static func nilIfEmpty(_ str: String?) -> String? {
		guard let trimmed = str?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
			return nil
		}
		return trimmed
	}

	// Zips `itemName` and `itemDescription` into entries, trimming whitespace, dropping rows whose
	// name is blank, and normalizing blank descriptions to nil. Throws if no usable rows remain.
	func buildItemEntries() throws -> [QuartermasterItemEntry] {
		var entries: [QuartermasterItemEntry] = []
		for index in 0..<itemName.count {
			let name = itemName[index].trimmingCharacters(in: .whitespacesAndNewlines)
			guard !name.isEmpty else { continue }
			let rawDescription = index < itemDescription.count ? itemDescription[index] : ""
			entries.append(QuartermasterItemEntry(itemName: name, itemDescription: Self.nilIfEmpty(rawDescription)))
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
	func buildContentData() throws -> QuartermasterContentData {
		let firstEntry = try buildItemEntries()[0]
		return QuartermasterContentData(
			category: try QuartermasterCategory.fromAPIString(category),
			itemName: firstEntry.itemName,
			itemDescription: firstEntry.itemDescription,
			location: Self.nilIfEmpty(location),
			hideOwnerName: hideOwnerName == "on"
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
			case .have: addItemURL = "/quartermaster/create?category=have"
			case .need: addItemURL = "/quartermaster/create?category=need"
			case .owned, .about: addItemURL = "/quartermaster/create"
		}
		showCategoryBadge = tab == .owned

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

// Leaf context used by the Add Item(s) and Edit Item pages. One template serves both; in edit mode
// there's exactly one (locked) item row and the "add another row" button is hidden.
struct QuartermasterCreateUpdatePageContext: Encodable {
	struct ItemRow: Encodable {
		var itemName: String
		var itemDescription: String
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
		items = [ItemRow(itemName: item.itemName, itemDescription: item.itemDescription ?? "")]
		isEdit = true
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

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped("quartermaster")
			.grouped(DisabledSiteSectionMiddleware(feature: .quartermaster))
		privateRoutes.get("create", use: createPageHandler)
		privateRoutes.post("create", use: createPostHandler)
		privateRoutes.get(quartermasterIDParam, "edit", use: editPageHandler)
		privateRoutes.post(quartermasterIDParam, "update", use: updatePostHandler)
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

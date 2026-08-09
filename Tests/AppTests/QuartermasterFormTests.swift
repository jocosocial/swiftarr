import XCTVapor
@testable import swiftarr

// Tests for Quartermaster Phase 4: the Site (Leaf/HTML) layer's Add Item(s)/Edit Item form -> API DTO
// mapping, plus the small tab/filter parsing helpers. Pure Swift -- no DB or network required, matching
// QuartermasterValidationTests (Phase 2).
class QuartermasterFormTests: XCTestCase {

	private func makeForm(
		category: String = "have",
		location: String? = "Deck 5",
		contactUsername: String? = nil,
		names: [String],
		descriptions: [String]? = nil
	) -> QuartermasterFormContent {
		QuartermasterFormContent(
			category: category,
			location: location,
			contactUsername: contactUsername,
			itemName: names,
			itemDescription: descriptions ?? names.map { _ in "" }
		)
	}

	// MARK: - buildItemEntries

	func testBuildItemEntries_ZipsNamesAndDescriptions() throws {
		let form = makeForm(names: ["Widget", "Gadget"], descriptions: ["First", "Second"])
		let entries = try form.buildItemEntries()
		XCTAssertEqual(entries.count, 2)
		XCTAssertEqual(entries[0].itemName, "Widget")
		XCTAssertEqual(entries[0].itemDescription, "First")
		XCTAssertEqual(entries[1].itemName, "Gadget")
		XCTAssertEqual(entries[1].itemDescription, "Second")
	}

	func testBuildItemEntries_DropsBlankNameRows() throws {
		let form = makeForm(names: ["Widget", "  ", "Gadget"], descriptions: ["a", "b", "c"])
		let entries = try form.buildItemEntries()
		XCTAssertEqual(entries.map { $0.itemName }, ["Widget", "Gadget"])
	}

	func testBuildItemEntries_AllBlankNames_Throws() {
		let form = makeForm(names: ["", "   ", ""])
		XCTAssertThrowsError(try form.buildItemEntries()) { err in
			XCTAssertEqual((err as? Abort)?.status, .badRequest)
		}
	}

	func testBuildItemEntries_BlankDescription_BecomesNil() throws {
		let form = makeForm(names: ["Widget"], descriptions: ["   "])
		let entries = try form.buildItemEntries()
		XCTAssertNil(entries[0].itemDescription)
	}

	func testBuildItemEntries_MissingDescriptionSlot_TreatedAsBlank() throws {
		// itemDescription can be shorter than itemName if a browser omits an empty trailing field.
		let form = QuartermasterFormContent(
			category: "have",
			location: "Deck 5",
			contactUsername: nil,
			itemName: ["Widget", "Gadget"],
			itemDescription: ["Only one"]
		)
		let entries = try form.buildItemEntries()
		XCTAssertEqual(entries[0].itemDescription, "Only one")
		XCTAssertNil(entries[1].itemDescription)
	}

	func testBuildItemEntries_TrimsWhitespace() throws {
		let form = makeForm(names: ["  Widget  "], descriptions: ["  Has spaces  "])
		let entries = try form.buildItemEntries()
		XCTAssertEqual(entries[0].itemName, "Widget")
		XCTAssertEqual(entries[0].itemDescription, "Has spaces")
	}

	func testBuildItemEntries_50Rows_Succeeds() throws {
		let names = (1...50).map { "Item \($0)" }
		let form = makeForm(names: names)
		let entries = try form.buildItemEntries()
		XCTAssertEqual(entries.count, 50)
	}

	// MARK: - buildCreateData (Add Item(s) -- batch create)

	func testBuildCreateData_HappyPath() throws {
		let form = makeForm(category: "need", location: "  Deck 9  ", contactUsername: "  sam  ", names: ["Widget"])
		let data = try form.buildCreateData()
		XCTAssertEqual(data.category, .need)
		XCTAssertEqual(data.location, "Deck 9")
		XCTAssertEqual(data.contactUsername, "sam")
		XCTAssertEqual(data.items.count, 1)
	}

	func testBuildCreateData_EmptyLocationAndContact_BecomeNil() throws {
		let form = makeForm(location: "", contactUsername: "   ", names: ["Widget"])
		let data = try form.buildCreateData()
		XCTAssertNil(data.location)
		XCTAssertNil(data.contactUsername)
	}

	func testBuildCreateData_InvalidCategory_Throws() {
		let form = makeForm(category: "bogus", names: ["Widget"])
		XCTAssertThrowsError(try form.buildCreateData()) { err in
			XCTAssertEqual((err as? Abort)?.status, .badRequest)
		}
	}

	func testBuildCreateData_AllBlankNames_Throws() {
		let form = makeForm(names: [""])
		XCTAssertThrowsError(try form.buildCreateData())
	}

	func testBuildCreateData_50Rows_Succeeds() throws {
		let names = (1...50).map { "Item \($0)" }
		let form = makeForm(names: names)
		let data = try form.buildCreateData()
		XCTAssertEqual(data.items.count, 50)
	}

	// MARK: - buildContentData (Edit Item -- single-item update, row 0 only)

	func testBuildContentData_TakesOnlyFirstRow() throws {
		let form = makeForm(names: ["Widget", "Gadget"], descriptions: ["First", "Second"])
		let data = try form.buildContentData()
		XCTAssertEqual(data.itemName, "Widget")
		XCTAssertEqual(data.itemDescription, "First")
	}

	func testBuildContentData_SkipsLeadingBlankRow() throws {
		// If row 0's name were somehow blank, buildItemEntries drops it, so row 1 becomes "first".
		let form = makeForm(names: ["   ", "Gadget"], descriptions: ["", "Second"])
		let data = try form.buildContentData()
		XCTAssertEqual(data.itemName, "Gadget")
	}

	func testBuildContentData_BlankName_Throws() {
		let form = makeForm(names: [""])
		XCTAssertThrowsError(try form.buildContentData())
	}

	// MARK: - QMTab / Owned category filter parsing

	func testQMTab_ParsesKnownValues() {
		XCTAssertEqual(QuartermasterListPageContext.QMTab(rawValue: "about"), .about)
		XCTAssertEqual(QuartermasterListPageContext.QMTab(rawValue: "have"), .have)
		XCTAssertEqual(QuartermasterListPageContext.QMTab(rawValue: "need"), .need)
		XCTAssertEqual(QuartermasterListPageContext.QMTab(rawValue: "owned"), .owned)
	}

	func testQMTab_UnknownValue_ReturnsNil() {
		XCTAssertNil(QuartermasterListPageContext.QMTab(rawValue: "bogus"))
	}

	func testOwnedCategorySelection_NilRequestedCategory_DefaultsToAll() {
		XCTAssertEqual(QuartermasterListPageContext.categorySelection(from: nil), "all")
	}

	func testOwnedCategorySelection_ExplicitCategory_PassesThrough() {
		XCTAssertEqual(QuartermasterListPageContext.categorySelection(from: "have"), "have")
		XCTAssertEqual(QuartermasterListPageContext.categorySelection(from: "need"), "need")
	}
}

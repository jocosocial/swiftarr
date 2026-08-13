import XCTVapor
@testable import swiftarr

// Tests for Quartermaster Phase 4: the Site (Leaf/HTML) layer's Add Item(s)/Edit Item form -> API DTO
// mapping, plus the small tab/filter parsing helpers. Pure Swift -- no DB or network required, matching
// QuartermasterValidationTests (Phase 2).
class QuartermasterFormTests: XCTestCase {

	private static let nameSlots: [WritableKeyPath<QuartermasterFormContent, String?>] = [
		\.itemName0, \.itemName1, \.itemName2, \.itemName3, \.itemName4,
		\.itemName5, \.itemName6, \.itemName7, \.itemName8, \.itemName9,
	]
	private static let descriptionSlots: [WritableKeyPath<QuartermasterFormContent, String?>] = [
		\.itemDescription0, \.itemDescription1, \.itemDescription2, \.itemDescription3, \.itemDescription4,
		\.itemDescription5, \.itemDescription6, \.itemDescription7, \.itemDescription8, \.itemDescription9,
	]
	private static let imageSlots: [WritableKeyPath<QuartermasterFormContent, Data?>] = [
		\.itemImage0, \.itemImage1, \.itemImage2, \.itemImage3, \.itemImage4,
		\.itemImage5, \.itemImage6, \.itemImage7, \.itemImage8, \.itemImage9,
	]

	// Builds a form from parallel row arrays, spreading them across the discrete itemNameN /
	// itemDescriptionN / itemImageN slots the way the real multipart form does (see
	// QuartermasterFormContent's doc comment for why these aren't array-typed fields).
	private func makeForm(
		category: String = "have",
		location: String? = "Deck 5",
		hideOwnerName: String? = nil,
		names: [String?],
		descriptions: [String?]? = nil,
		images: [Data?]? = nil,
		currentItemImage: String? = nil,
		removeItemImage: String? = nil
	) -> QuartermasterFormContent {
		var form = QuartermasterFormContent(
			category: category,
			location: location,
			hideOwnerName: hideOwnerName,
			currentItemImage: currentItemImage,
			removeItemImage: removeItemImage
		)
		for (index, name) in names.enumerated() {
			form[keyPath: Self.nameSlots[index]] = name
		}
		if let descriptions {
			for (index, desc) in descriptions.enumerated() {
				form[keyPath: Self.descriptionSlots[index]] = desc
			}
		}
		if let images {
			for (index, data) in images.enumerated() {
				form[keyPath: Self.imageSlots[index]] = data
			}
		}
		return form
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

	func testBuildItemEntries_UnsetDescriptionSlot_TreatedAsBlank() throws {
		// itemDescription1 is left nil, the way a row whose description field the browser omitted
		// (or a freshly-cloned row nobody touched) would submit it.
		let form = makeForm(names: ["Widget", "Gadget"], descriptions: ["Only one"])
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

	func testBuildItemEntries_10Rows_Succeeds() throws {
		let names: [String?] = (1...10).map { "Item \($0)" }
		let form = makeForm(names: names)
		let entries = try form.buildItemEntries()
		XCTAssertEqual(entries.count, 10)
	}

	// MARK: - buildItemEntries — images

	func testBuildItemEntries_NewImageData_SetsEntryImage() throws {
		let imageBytes = Data([0x01, 0x02, 0x03])
		let form = makeForm(names: ["Widget"], images: [imageBytes])
		let entries = try form.buildItemEntries()
		XCTAssertEqual(entries[0].image?.image, imageBytes)
		XCTAssertNil(entries[0].image?.filename)
	}

	func testBuildItemEntries_EmptyImageData_LeavesEntryImageNil() throws {
		let form = makeForm(names: ["Widget"], images: [Data()])
		let entries = try form.buildItemEntries()
		XCTAssertNil(entries[0].image)
	}

	func testBuildItemEntries_UnsetImageSlot_TreatedAsNoImage() throws {
		// Row 1's itemImage1 slot is left nil, the way a row with no file chosen submits it.
		let form = makeForm(names: ["Widget", "Gadget"], descriptions: ["", ""], images: [Data([0x01])])
		let entries = try form.buildItemEntries()
		XCTAssertNotNil(entries[0].image)
		XCTAssertNil(entries[1].image)
	}

	// MARK: - buildCreateData (Add Item(s) -- batch create)

	func testBuildCreateData_HappyPath() throws {
		let form = makeForm(category: "need", location: "  Deck 9  ", hideOwnerName: "on", names: ["Widget"])
		let data = try form.buildCreateData()
		XCTAssertEqual(data.category, .need)
		XCTAssertEqual(data.location, "Deck 9")
		XCTAssertTrue(data.hideOwnerName)
		XCTAssertEqual(data.items.count, 1)
	}

	func testBuildCreateData_EmptyLocationAndNoHide_BecomesNilFalse() throws {
		let form = makeForm(location: "", hideOwnerName: nil, names: ["Widget"])
		let data = try form.buildCreateData()
		XCTAssertNil(data.location)
		XCTAssertFalse(data.hideOwnerName)
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

	func testBuildCreateData_10Rows_Succeeds() throws {
		let names: [String?] = (1...10).map { "Item \($0)" }
		let form = makeForm(names: names)
		let data = try form.buildCreateData()
		XCTAssertEqual(data.items.count, 10)
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

	// MARK: - buildContentData — image reconciliation

	func testBuildContentData_NoNewFileNoRemove_KeepsExistingImage() throws {
		let form = makeForm(names: ["Widget"], currentItemImage: "existing.jpg")
		let data = try form.buildContentData()
		XCTAssertEqual(data.image?.filename, "existing.jpg")
		XCTAssertNil(data.image?.image)
	}

	func testBuildContentData_NewFile_ReplacesExistingImage() throws {
		let imageBytes = Data([0x01, 0x02])
		let form = makeForm(names: ["Widget"], images: [imageBytes], currentItemImage: "existing.jpg")
		let data = try form.buildContentData()
		XCTAssertEqual(data.image?.image, imageBytes)
	}

	func testBuildContentData_RemoveChecked_ClearsImage() throws {
		let form = makeForm(names: ["Widget"], currentItemImage: "existing.jpg", removeItemImage: "on")
		let data = try form.buildContentData()
		XCTAssertNil(data.image)
	}

	func testBuildContentData_RemoveCheckedButNewFileChosen_NewFileWins() throws {
		let imageBytes = Data([0x01, 0x02])
		let form = makeForm(
			names: ["Widget"], images: [imageBytes], currentItemImage: "existing.jpg", removeItemImage: "on"
		)
		let data = try form.buildContentData()
		XCTAssertEqual(data.image?.image, imageBytes)
	}

	func testBuildContentData_NoExistingNoNewImage_ImageIsNil() throws {
		let form = makeForm(names: ["Widget"])
		let data = try form.buildContentData()
		XCTAssertNil(data.image)
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

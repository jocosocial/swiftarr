@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class ForumTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let testVerification = "ABC ABC"
    let adminURI = "/api/v3/admin/"
    let authURI = "/api/v3/auth/"
    let eventsURI = "/api/v3/events/"
    let forumURI = "/api/v3/forum/"
    let testURI = "/api/v3/test/"
    let userURI = "/api/v3/user/"
    let usersURI = "/api/v3/users/"
    var app: Application!
    var conn: PostgreSQLConnection!
    
    /// Reset databases, create testable app instance and connect it to database.
    override func setUp() {
        try! Application.reset()
        app = try! Application.testable()
        conn = try! app.newConnection(to: .psql).wait()
    }
    
    /// Release database connection, then shut down the app.
    override func tearDown() {
        conn.close()
        try? app.syncShutdownGracefully()
        super.tearDown()
    }
    
    // MARK: - Tests
    // Note: We migrate an "admin" user first during boot, so it is always present as `.first()`.
    
    /// Ensure that `Categories` migration was successful.
    func testCategoriesMigration() throws {
        // create user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.basicAuthorization = BasicAuthorization(username: testUsername, password: testPassword)
        
        // get categories
        let categories = try app.getResult(
            from: forumURI + "categories",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        XCTAssertFalse(categories.isEmpty, "should be categories")
    }
    
    /// `GET /api/v3/forum/categories`
    /// `GET /api/v3/forum/categories/admin`
    /// `GET /api/v3/forum/categories/user`
    func testCategoryTypes() throws {
        // create user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.basicAuthorization = BasicAuthorization(username: testUsername, password: testPassword)
        
        // test categories
        var categories = try app.getResult(
            from: forumURI + "categories",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let categoriesCount = categories.count
        XCTAssertFalse(categories.isEmpty, "should be categories")
        categories = try app.getResult(
            from: forumURI + "categories/admin",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let adminCount = categories.count
        categories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let userCount = categories.count
        XCTAssertTrue(userCount + adminCount == categoriesCount, "should be \(categoriesCount)")
        XCTAssertTrue(categories[0].title == "Test 1", "should be 'Test 1'")
    }
    
    /// `GET /api/v3/forum/categories/admin`
    /// `GET /api/v3/forum/categories/user`
    /// `GET /api/v3/forum/categories/ID`
    func testForumCategory() throws {
        // create user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.basicAuthorization = BasicAuthorization(username: testUsername, password: testPassword)
        
        // get admin categories
        let categories = try app.getResult(
            from: forumURI + "categories/admin",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        XCTAssertTrue(categories[0].title == "Twit-arr Support", "should be 'Twit-arr Support'")
        
        // test bad ID
        let response = try app.getResponse(
            from: forumURI + "categories/\(UUID())",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        
        // test get forums
        let forums = try app.getResult(
            from: forumURI + "categories/\(categories[0].categoryID)",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(forums.count == 2, "should be 2 forums")
        XCTAssertTrue(forums[1].title == "Twit-arr Feedback", "should be 'Twit-arr Feedback")
    }
    
    /// `GET /api/v3/forum/owner`
    /// `GET /api/v3/user/forums`
    func testForumOwner() throws {
        // admin owns all seed forums
        let token = try app.login(username: "admin", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test forum api
        let forumForums = try app.getResult(
            from: forumURI + "owner",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(forumForums.count == 2, "should be 2 forums")
        
        // test user api
        let userForums = try app.getResult(
            from: userURI + "forums",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(forumForums.count == userForums.count, "should be same")
        XCTAssertTrue(forumForums[0].forumID == userForums[0].forumID, "should be same order")
    }
    
    /// `POST /api/v3/forum/categories/ID/create`
    func testForumCreate() throws {
        // created verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // get categories
        let adminCategories = try app.getResult(
            from: forumURI + "categories/admin",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        
        // create data
        let imageFile = "test-image.jpg"
        let directoryConfig = DirectoryConfig.detect()
        let imagePath = directoryConfig.workDir.appending("seeds/").appending(imageFile)
        let data = FileManager.default.contents(atPath: imagePath)
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: data
        )
        
        // test user forum
        var categoryID = userCategories.first?.categoryID
        var forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.title == forumCreateData.title, "should be \(forumCreateData.title)")
        XCTAssertFalse(forumData.posts.isEmpty, "should be a post")
        XCTAssertNotNil(UUID(forumData.posts.first!.image), "should be a UUID")
        
        // test disallow admin forum
        categoryID = adminCategories.first?.categoryID
        let response = try app.getResponse(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("in category"), "in category")
        
        // test admin forum
        token = try app.login(username: "moderator", password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.title == forumCreateData.title, "should be \(forumCreateData.title)")
        XCTAssertFalse(forumData.posts.isEmpty, "should be a post")
        XCTAssertNotNil(UUID(forumData.posts.first!.image), "should be a UUID")
    }
    
//    /// `POST /api/v3/forum/ID/lock`
//    /// `POST /api/v3/forum/ID/unlock`
//    func testForumLock() throws {
//
//    }
    
//    /// `POST /api/v3/forum/ID/rename/STRING`
//    func testForumRename() throws {
//        
//    }
    
    // test forum block
}

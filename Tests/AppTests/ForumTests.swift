@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class ForumTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let adminURI = "/api/v3/admin/"
    let forumURI = "/api/v3/forum/"
    let userURI = "/api/v3/user/"
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
        var categories = try app.getResult(
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
        var forums = try app.getResult(
            from: forumURI + "categories/\(categories[0].categoryID)",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(forums.count == 2, "should be 2 forums")
        XCTAssertTrue(forums[1].title == "Twit-arr Feedback", "should be 'Twit-arr Feedback")
        
        // get user categories
        categories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        XCTAssertTrue(categories[0].title == "Test 1", "should be 'Test 1'")
        
        // test get user forums for test coverage
        let token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = categories.first?.categoryID
        let _ = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        forums = try app.getResult(
            from: forumURI + "categories/\(categoryID!)",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(forums.count == 1, "should be 1 forum")
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
        XCTAssertTrue(forumForums.count == 415, "should be 415 forums")
        
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
    
    /// `GET /api/v3/forum/ID`
    /// `POST /api/v3/forum/ID/create`
    /// `POST /api/v3/forum/ID/rename/STRING`
    /// `POST /api/v3/forum/ID/lock`
    /// `POST /api/v3/forum/ID/unlock`
    func testForumModify() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        var forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.title == forumCreateData.title, "should be \(forumCreateData.title)")
        XCTAssertFalse(forumData.isLocked, "should not be locked")
        
        // test rename
        let newTitle = "New%20Name!"
        var response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/rename/\(newTitle)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        forumData = try app.getResult(
            from: forumURI + "\(forumData.forumID)",
            method: .GET,
            headers: headers,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.title == "New Name!", "should be 'New Name!'")
        
        // test lock
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/lock",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        forumData = try app.getResult(
            from: forumURI + "\(forumData.forumID)",
            method: .GET,
            headers: headers,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.isLocked, "should be locked")
        
        // test attempt post
        let verifiedHeaders = headers
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        let postCreateData = PostCreateData(text: "Hello!", imageData: nil)
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/create",
            method: .POST,
            headers: headers,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

        // test attempt unlock
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/unlock",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test unlock
        headers = verifiedHeaders
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/unlock",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
        forumData = try app.getResult(
            from: forumURI + "\(forumData.forumID)",
            method: .GET,
            headers: headers,
            decodeTo: ForumData.self
        )
        XCTAssertFalse(forumData.isLocked, "should be unlocked")
        
        // test moderator can lock
        token = try app.login(username: "moderator", password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/lock",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/unlock",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
    }
    
    /// `POST /api/v3/forum/post/ID/delete`
    func testPostDelete() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        var forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        
        // create post
        let postCreateData = PostCreateData(text: "Hello!", imageData: nil)
        var response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/create",
            method: .POST,
            headers: headers,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")

        // get post
        forumData = try app.getResult(
            from: forumURI + "\(forumData.forumID)",
            method: .GET,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let postsCount = forumData.posts.count
        let post = forumData.posts[0]
        XCTAssertTrue(post.text == "\(forumCreateData.text)", "should be \(forumCreateData.text)")
        
        // test attempt delete
        let verifiedHeaders = headers
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test delete
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/delete",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
        forumData = try app.getResult(
            from: forumURI + "\(forumData.forumID)",
            method: .GET,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.posts.count == postsCount - 1, "should be \(postsCount - 1)")
    }
    
    func testForumReport() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        
        // test submit
        var reportData = ReportData(message: "")
        var response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/report",
            method: .POST,
            headers: headers,
            body: reportData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        
        // test no limit
        reportData.message = "Ugh."
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/report",
            method: .POST,
            headers: headers,
            body: reportData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        
        // test data
        token = try app.login(username: "admin", password: testPassword, on: conn)
        var adminHeaders = HTTPHeaders()
        adminHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        let reports = try app.getResult(
            from: adminURI + "reports",
            method: .GET,
            headers: adminHeaders,
            decodeTo: [Report].self
        )
        XCTAssertTrue(reports.count == 2, "should be 2 reports")
        XCTAssertFalse(reports[0].isClosed, "should be open")
        XCTAssertTrue(reports[1].submitterMessage == reportData.message, "should be \(reportData.message)")
    }
    
    func testPostReport() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test submit
        var reportData = ReportData(message: "")
        var response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/report",
            method: .POST,
            headers: headers,
            body: reportData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        
        // test limited to 1
        reportData.message = "Ugh."
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/report",
            method: .POST,
            headers: headers,
            body: reportData
        )
        XCTAssertTrue(response.http.status.code == 409, "should be 409 Conflict")
        
        // test data
        token = try app.login(username: "admin", password: testPassword, on: conn)
        var adminHeaders = HTTPHeaders()
        adminHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        let reports = try app.getResult(
            from: adminURI + "reports",
            method: .GET,
            headers: adminHeaders,
            decodeTo: [Report].self
        )
        XCTAssertTrue(reports.count == 1, "should be 1 report")
        XCTAssertFalse(reports[0].isClosed, "should be open")
        XCTAssertTrue(reports[0].submitterMessage.isEmpty, "should be empty message report")
    }
    
    /// `POST /api/v3/forum/post/ID/update`
    func testPostUpdate() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test update post
        let postContentData = PostContentData(text: "Changed post text.", image: post.image)
        let postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/update",
            method: .POST,
            headers: headers,
            body: postContentData,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.postID == post.postID, "should be \(post.postID)")
        XCTAssertTrue(postData.text == postContentData.text, "should be '\(postContentData.text)'")
        
        // test no update
        let postDataAgain = try app.getResult(
            from: forumURI + "post/\(post.postID)/update",
            method: .POST,
            headers: headers,
            body: postContentData,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postDataAgain.text == postData.text, "should be same")
        XCTAssertTrue(postDataAgain.image == postData.image, "should be same")
        
        // test no access
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        let response = try app.getFormResponse(
            from: forumURI + "post/\(post.postID)/update",
            method: .POST,
            headers: headers,
            body: postContentData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
    }
    
    /// `GET /api/v3/forum/post/ID`
    func testContentFilter() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A filterable forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test unfiltered
        var response = try app.getResponse(
            from: forumURI + "post/\(post.postID)",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 200, "shoulb be 200 OK")

        // set muteword
        let muteKeywordData = try app.getResult(
            from: userURI + "mutewords/add/filter",
            method: .POST,
            headers: headers,
            decodeTo: MuteKeywordData.self
        )
        XCTAssertTrue(muteKeywordData.keywords.count == 1, "should be 1 keyword")
        XCTAssertTrue(muteKeywordData.keywords[0] == "filter", "should be 'filter'")
        
        // test filtered
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404 , "should be 404 Not Found")
    }
    
    /// `GET /api/v3/forum/post/ID/forum`
    func testPostForum() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test get forum from post
        let postForumData = try app.getResult(
            from: forumURI + "post/\(post.postID)/forum",
            method: .GET,
            headers: headers,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.forumID == postForumData.forumID, "should be same")
        XCTAssertTrue(forumData.posts[0].postID == postForumData.posts[0].postID, "should be same")
    }
    
    /// `POST /api/v3/forum/post/ID/image`
    /// `POST /api/v3/forum/post/ID/image/remove`
    func testPostImage() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test add image
        let imageFile = "test-image.jpg"
        let directoryConfig = DirectoryConfig.detect()
        let imagePath = directoryConfig.workDir.appending("seeds/").appending(imageFile)
        let data = FileManager.default.contents(atPath: imagePath)
        let imageUploadData = ImageUploadData(filename: imageFile, image: data!)
        var postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/image",
            method: .POST,
            headers: headers,
            body: imageUploadData,
            decodeTo: PostData.self
        )
        let imageName = postData.image
        XCTAssertNotNil(UUID(postData.image), "should have an image string")
        
        // test replace image
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/image",
            method: .POST,
            headers: headers,
            body: imageUploadData,
            decodeTo: PostData.self
        )
        XCTAssertNotNil(UUID(postData.image), "should have an image string")
        XCTAssertNotEqual(postData.image, imageName, "should have a different name")
        
        // test remove image
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/image/remove",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.image.isEmpty, "should be no image")
        
        // test no access
        let _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        var response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/image",
            method: .POST,
            headers: headers,
            body: imageUploadData
        )
        XCTAssertTrue(response.http.status.code == 403 , "should be 403 Forbidden")
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/image/remove",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403 , "should be 403 Forbidden")
    }
    
    /// `GET /api/v3/forum/match/STRING`
    func testMatchForum() throws {
        // test with Basic access
        var headers = HTTPHeaders()
        let credentials = BasicAuthorization(username: "unverified", password: testPassword)
        headers.basicAuthorization = credentials
        
        let forums = try app.getResult(
            from: forumURI + "match/concert",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(forums.count > 0, "should be some forums")
        XCTAssertTrue(forums[0].title.lowercased().contains("concert"), "should be true")
    }
    
    /// `GET /api/v3/forum/ID/search/STRING`
    func testForumSearch() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post for FaNcYpAnTs searching!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test search
        let posts = try app.getResult(
            from: forumURI + "\(forumData.forumID)/search/fancy",
            method: .GET,
            headers: headers,
            decodeTo: [PostData].self
        )
        XCTAssertTrue(posts.count > 0, "should be a post")
        XCTAssertTrue(posts[0].text.lowercased().contains("fancy"), "should contain 'FaNcY'")
        XCTAssertEqual(posts[0].postID, post.postID, "should be same")
    }
    
    /// `GET /api/v3/forum/post/search/STRING`
    func testPostSearch() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post for FaNcYpAnTs searching!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test search
        let posts = try app.getResult(
            from: forumURI + "post/search/fancy",
            method: .GET,
            headers: headers,
            decodeTo: [PostData].self
        )
        XCTAssertTrue(posts.count > 0, "should be a post")
        XCTAssertTrue(posts[0].text.lowercased().contains("fancy"), "should contain 'FaNcY'")
        XCTAssertEqual(posts[0].postID, post.postID, "should be same")
    }
    
    /// `POST /api/v3/forum/post/ID/laugh`
    /// `POST /api/v3/forum/post/ID/like`
    /// `POST /api/v3/forum/post/ID/love`
    /// `POST /api/v3/forum/post/ID/unreact`
    func testPostReactions() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create user forum
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post for like testing!",
            image: nil
        )
        let categoryID = userCategories.first?.categoryID
        let forumData = try app.getResult(
            from: forumURI + "categories/\(categoryID!)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        let post = forumData.posts[0]
        
        // test cannot like own post
        var response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/laugh",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/like",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/love",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test like
        let verifiedHeaders = headers
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        var postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/laugh",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.userLike == LikeType.laugh, "should be '.laugh'")
        
        // test replaces previous
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/laugh",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.userLike == LikeType.laugh, "should be '.laugh'")

        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/like",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.userLike == LikeType.like, "should be '.like'")
        
        // test last of the bunch
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/love",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.userLike == LikeType.love, "should be '.love'")
        
        // test coverage for ID
        let postDetailData = try app.getResult(
            from: forumURI + "post/\(post.postID)",
            method: .GET,
            headers: headers,
            decodeTo: PostDetailData.self
        )
        XCTAssertTrue(postDetailData.loves.count == 1, "should be 1 love")
        
        // test unreact
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/unreact",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertNil(postData.userLike, "should be no reaction")
        
        // test nothing to unreact
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/unreact",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")

        // test owner cannot remove
        response = try app.getResponse(
            from: forumURI + "post/\(post.postID)/laugh",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test coverage create like/laugh
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/like",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.userLike == LikeType.like, "should be '.like'")
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/unreact",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertNil(postData.userLike, "should be no reaction")
        postData = try app.getResult(
            from: forumURI + "post/\(post.postID)/love",
            method: .POST,
            headers: headers,
            decodeTo: PostData.self
        )
        XCTAssertTrue(postData.userLike == LikeType.love, "should be '.love'")


    }
    
    func testForumBarrel() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // get forums
        let adminCategories = try app.getResult(
            from: forumURI + "categories/admin",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        var adminForums = try app.getResult(
            from: forumURI + "categories/\(adminCategories[0].categoryID)",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        let userCategories = try app.getResult(
            from: forumURI + "categories/user",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        let forumCreateData = ForumCreateData(
            title: "A forum!",
            text: "A forum post for like testing!",
            image: nil
        )
         var forumData = try app.getResult(
            from: forumURI + "categories/\(userCategories[0].categoryID)/create",
            method: .POST,
            headers: headers,
            body: forumCreateData,
            decodeTo: ForumData.self
        )
        
        // test favorite
        var response = try app.getResponse(
            from: forumURI + "\(adminForums[0].forumID)/favorite",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/favorite",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        adminForums = try app.getResult(
            from: forumURI + "categories/\(adminCategories[0].categoryID)",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(adminForums[0].isFavorite, "should be true")
        forumData = try app.getResult(
            from: forumURI + "\(forumData.forumID)",
            method: .GET,
            headers: headers,
            decodeTo: ForumData.self
        )
        XCTAssertTrue(forumData.isFavorite, "should be true")
        var favoriteForums = try app.getResult(
            from: forumURI + "favorites",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(favoriteForums.count == 2, "should be 2 forums")
        
        // test remove favorite
        response = try app.getResponse(
            from: forumURI + "\(forumData.forumID)/favorite/remove",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
        favoriteForums = try app.getResult(
            from: forumURI + "favorites",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(favoriteForums.count == 1, "should be 1 forum")
    }
    // test forum block
}

@testable import App
import Vapor
import XCTest
import FluentPostgreSQL
import Foundation

final class TwitarrTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let adminURI = "/api/v3/admin/"
    let twitarrURI = "/api/v3/twitarr/"
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
    
    /// `POST /api/v3/twitarr/create`
    /// `POST /api/v3/twitarr/ID/update`
    /// `POST /api/v3/twitarr/ID/image`
    /// `POST /api/v3/twitarr/ID/image/remove`
    /// `POST /api/v3/twitarr/ID/delete`
    func testTwarrtCUD() throws {
        // create 2 users
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test create
        let postCreateData = PostCreateData(text: "This is a twarrt.", imageData: nil)
        var twarrtData = try app.getResult(
            from: twitarrURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: postCreateData,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.text == postCreateData.text, "should be \(postCreateData.text)")
        
        // test update
        let postContentData = PostContentData(text: "This is an update.", image: twarrtData.image)
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/update",
            method: .POST,
            headers: verifiedHeaders,
            body: postContentData,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.text == postContentData.text, "should be \(postContentData.text)")
        
        // update again for test coverage
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/update",
            method: .POST,
            headers: verifiedHeaders,
            body: postContentData,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.text == postContentData.text, "should be \(postContentData.text)")
        
        // test no update access
        var response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/update",
            method: .POST,
            headers: userHeaders,
            body: postContentData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test image
        let imageFile = "test-image.jpg"
        let directoryConfig = DirectoryConfig.detect()
        let imagePath = directoryConfig.workDir.appending("seeds/").appending(imageFile)
        let data = FileManager.default.contents(atPath: imagePath)
        let imageUploadData = ImageUploadData(filename: imageFile, image: data!)
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/image",
            method: .POST,
            headers: verifiedHeaders,
            body: imageUploadData,
            decodeTo: TwarrtData.self
        )
        XCTAssertNotNil(UUID(twarrtData.image), "should be valid UUID")
        
        // test image remove
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/image/remove",
            method: .POST,
            headers: verifiedHeaders,
            body: imageUploadData,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.image.isEmpty, "should be no image")
        
        // test no image access
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/image",
            method: .POST,
            headers: userHeaders,
            body: imageUploadData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

        // test no image remove access
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/image/remove",
            method: .POST,
            headers: userHeaders,
            body: imageUploadData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

        // test no delete access
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/delete",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

        // test delete
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/delete",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
    }
    
    /// `POST /api/v3/twitarr/ID/laugh`
    /// `POST /api/v3/twitarr/ID/like`
    /// `POST /api/v3/twitarr/ID/love`
    /// `POST /api/v3/twitarr/ID/unreact`
    /// `GET /api/v3/twitarr/likes`
    /// `GET /api/v3/twitarr/ID`
    func testLikes() throws {
        // create 2 users
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create twarrt
        let postCreateData = PostCreateData(text: "This is a twarrt.", imageData: nil)
        var twarrtData = try app.getResult(
            from: twitarrURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: postCreateData,
            decodeTo: TwarrtData.self
        )
        
        // test no like access
        var response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/laugh",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/like",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/love",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/unreact",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test like
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/laugh",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.userLike == .laugh, "should be `.laugh`")
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/like",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.userLike == .like, "should be `.like`")
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/love",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.userLike == .love, "should be `.love`")
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/unreact",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        XCTAssertNil(twarrtData.userLike, "should be no reaction")
        
        // fill out test branch coverage
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/like",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.userLike == .like, "should be `.like`")
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/unreact",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        XCTAssertNil(twarrtData.userLike, "should be no reaction")
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/love",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        XCTAssertTrue(twarrtData.userLike == .love, "should be `.love`")
        
        // test get detail
        let twarrtDetail = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)",
            method: .GET,
            headers: userHeaders,
            decodeTo: TwarrtDetailData.self
        )
        XCTAssertTrue(twarrtDetail.loves.count == 1, "should be 1 love")
        XCTAssertTrue(twarrtDetail.loves[0].username == "@\(testUsername)", "should be `@\(testUsername)`")
        
        // test get likes
        var twarrts = try app.getResult(
            from: twitarrURI + "likes",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 1, "should be 1 twarrt")
        XCTAssertTrue(twarrts[0].userLike == .love, "should be `.love`")
        twarrtData = try app.getResult(
            from: twitarrURI + "\(twarrtData.twarrtID)/unreact",
            method: .POST,
            headers: userHeaders,
            decodeTo: TwarrtData.self
        )
        twarrts = try app.getResult(
            from: twitarrURI + "likes",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 0, "should be no twarrts")
    }
    
    /// `POST /api/v3/twitarr/ID/bookmark`
    /// `POST /api/v3/twitarr/ID/bookmark/remove`
    /// `GET /api/v3/twitarr/bookmarks`
    func testBookmarks() throws {
        // create 2 users
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create twarrt
        let postCreateData = PostCreateData(text: "This is a twarrt.", imageData: nil)
        let twarrtData = try app.getResult(
            from: twitarrURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: postCreateData,
            decodeTo: TwarrtData.self
        )
        
        // test add bookmark
        var response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/bookmark",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 201 , "should be 201 Created")
        
        // test duplicate
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/bookmark",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 400 , "should be 400 Bad Request")
        
        // test remove
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/bookmark/remove",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 204 , "should be 204 No Content")
        
        // test virgin remove
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/bookmark/remove",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 400 , "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("has not bookmarked"), "has not bookmarked")
        
        // test bookmarks
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/bookmark",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 201 , "should be 201 Created")
        var twarrts = try app.getResult(
            from: twitarrURI + "bookmarks",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 1, "should be 1 twarrt")
        XCTAssertTrue(twarrts[0].isBookmarked, "should be bookmarked")
        response = try app.getResponse(
            from: twitarrURI + "\(twarrtData.twarrtID)/bookmark/remove",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 204 , "should be 204 No Content")
        twarrts = try app.getResult(
            from: twitarrURI + "bookmarks",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 0, "should be no twarrts")
    }
    
    /// `GET /api/v3/twitarr/user`
    /// `GET /api/v3/twitarr/user/ID`
    /// `GET /api/v3/twitarr/hashtag/#HASHTAG`
    /// `GET /api/v3/twitarr/search/STRING`
    /// `GET /api/v3/twitarr/barrel/ID`
    func testUsers() throws {
        // create 3 users
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "moderator", password: testPassword, on: conn)
        var moderatorHeaders = HTTPHeaders()
        moderatorHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create twarrts
        var postCreateData = PostCreateData(text: "This is from verified, @\(testUsername).", imageData: nil)
        var response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        postCreateData.text = "This is from moderator, @\(testUsername).#hashtag"
        response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: moderatorHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        postCreateData.text = "This is from moderator. #hashtag"
        response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: moderatorHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        postCreateData.text = "This might be from @\(testUsername). #hashtag2020"
        response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: userHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")

        // test user
        var twarrts = try app.getResult(
            from: twitarrURI + "user",
            method: .GET,
            headers: moderatorHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 2, "should be 2 twarrts")
        
        // test user/ID
        twarrts = try app.getResult(
            from: twitarrURI + "user/\(user.userID)",
            method: .GET,
            headers: moderatorHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 1, "should be 1 twarrt")
        
        // test hashtag
        twarrts = try app.getResult(
            from: twitarrURI + "hashtag/#hashtag",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 2, "should be 2 twarrts")
        
        // test search
        twarrts = try app.getResult(
            from: twitarrURI + "search/MIGHT",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 1, "should be 1 twarrt")
        
        // test barrel
        let verifiedInfo = try app.getResult(
            from: usersURI + "find/verified",
            method: .GET,
            headers: userHeaders,
            decodeTo: UserInfo.self
        )
        let moderatorInfo = try app.getResult(
            from: usersURI + "find/moderator",
            method: .GET,
            headers: userHeaders,
            decodeTo: UserInfo.self
        )
        let barrelCreateData = BarrelCreateData(
            name: "Favorites",
            uuidList: [verifiedInfo.userID, moderatorInfo.userID],
            stringList: nil
        )
        let barrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: userHeaders,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        twarrts = try app.getResult(
            from: twitarrURI + "barrel/\(barrelData.barrelID)",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 3, "should be 3 twarrts")
        XCTAssertTrue(twarrts[2].authorID == verifiedInfo.userID, "should be \(verifiedInfo.userID)")
        
        // test bad barrel ID
        let barrels = try app.getResult(
            from: userURI + "barrels",
            method: .GET,
            headers: userHeaders,
            decodeTo: [BarrelListData].self
        )
        response = try app.getResponse(
            from: twitarrURI + "barrel/\(barrels[0].barrelID)",
            method: .GET,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("not a seamonkey"), "not a seamonkey")
    }
    
    /// `GET /api/v3/twitarr/mentions`
    /// `GET /api/v3/twitarr/mentions?after=ID`
    /// `GET /api/v3/twitarr/mentions?afterdate=DATE`
    func testMentions() throws {
        // create 3 users
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        let _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "moderator", password: testPassword, on: conn)
        var moderatorHeaders = HTTPHeaders()
        moderatorHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test empty return
        var twarrts = try app.getResult(
            from: twitarrURI + "mentions",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 0, "should be no twarrts")

        // create twarrts
        var postCreateData = PostCreateData(text: "This is from verified, @\(testUsername).", imageData: nil)
        var response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        postCreateData.text = "This is from moderator, @\(testUsername).#hashtag"
        response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: moderatorHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        postCreateData.text = "This is from moderator. #hashtag"
        response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: moderatorHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        postCreateData.text = "This might be from @\(testUsername). #hashtag2020"
        response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: userHeaders,
            body: postCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")

        // test mentions
        twarrts = try app.getResult(
            from: twitarrURI + "mentions",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 3, "should be 3 twarrts")
        
        let date = Date().timeIntervalSince1970
        let id = twarrts[0].twarrtID

        // create another mention
        sleep(1)
        postCreateData.text = "Yo, @\(testUsername)!"
        response = try app.getResponse(
            from: twitarrURI + "create",
            method: .POST,
            headers: moderatorHeaders,
            body: postCreateData
        )
        twarrts = try app.getResult(
            from: twitarrURI + "mentions",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 4, "should be 4 twarrts")

        // test mentions?after
        twarrts = try app.getResult(
            from: twitarrURI + "mentions?after=\(id)",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 1, "should be 1 twarrt")
        
        // test mentions?afterdate
        twarrts = try app.getResult(
            from: twitarrURI + "mentions?afterdate=\(date)",
            method: .GET,
            headers: userHeaders,
            decodeTo: [TwarrtData].self
        )
        XCTAssertTrue(twarrts.count == 1, "should be 1 twarrt")
    }

    // test reply
    // test report
    // test twarrts
}

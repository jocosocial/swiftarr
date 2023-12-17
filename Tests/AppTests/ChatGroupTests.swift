@testable import App
import Vapor
import XCTest

import Foundation

final class ChatGroupTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let adminURI = "/api/v3/admin/"
    let chatGroupURI = "/api/v3/chatgroup/"
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
    
    /// `GET /api/v3/chatgroup/types`
    /// `POST /api/v3/chatgroup/create`
    func testCreate() throws {
        // get logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test types
        let types = try app.getResult(
            from: chatGroupURI + "types",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertFalse(types.isEmpty, "should be types")
        
        // test chatgroup with times
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        var chatGroupContentData = ChatGroupContentData(
            chatGroupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var chatGroupData = try app.getResult(
            from: chatGroupURI + "create",
            method: .POST,
            headers: headers,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys[0].username == "@verified", "should be 'verified'")
        
        // test with no times
        chatGroupContentData.startTime = ""
        chatGroupContentData.endTime = ""
        chatGroupData = try app.getResult(
            from: chatGroupURI + "create",
            method: .POST,
            headers: headers,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.startTime == "TBD", "should be 'TBD'")
        XCTAssertTrue(chatGroupData.endTime == "TBD", "should be 'TBD'")
        
        // test with invalid times
        chatGroupContentData.startTime = "abc"
        chatGroupContentData.endTime = "def"
        let response = try app.getResponse(
            from: chatGroupURI + "create",
            method: .POST,
            headers: headers,
            body: chatGroupContentData
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
    }
    
    /// `POST /api/v3/chatgroup/ID/join`
    /// `GET /api/v3/chatgroup/joined`
    /// `GET /api/v3/chatgroup/owner`
    /// `POST /api/v3/chatgroup/ID/unjoin`
    func testJoin() throws {
        // need 3 logged in users
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "moderator", password: testPassword, on: conn)
        var moderatorHeaders = HTTPHeaders()
        moderatorHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create chatgroup
        let types = try app.getResult(
            from: chatGroupURI + "types",
            method: .GET,
            headers: userHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let chatGroupContentData = ChatGroupContentData(
            chatGroupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var chatGroupData = try app.getResult(
            from: chatGroupURI + "create",
            method: .POST,
            headers: userHeaders,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys[0].username == "@\(testUsername)", "should be \(testUsername)")
        
        // test join chatgroup
        chatGroupData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/join",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(chatGroupData.seamonkeys[1].username == "@verified", "should be '@verified'")
        
        // test waitList
        chatGroupData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/join",
            method: .POST,
            headers: moderatorHeaders,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(chatGroupData.waitingList.count == 1, "should be 1 waiting")
        XCTAssertTrue(chatGroupData.waitingList[0].username == "@moderator", "should be '@moderator'")

        // test joined
        var joined = try app.getResult(
            from: chatGroupURI + "joined",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(joined.count == 1, "should be 1 chatgroup")
        var response = try app.getResponse(
            from: chatGroupURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: chatGroupContentData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        joined = try app.getResult(
            from: chatGroupURI + "joined",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(joined.count == 2, "should be 2 chatgroups")
        
        // test owner
        let whoami = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: CurrentUserData.self
        )
        var owned = try app.getResult(
            from: chatGroupURI + "owner",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(owned.count == 1, "should be 1 chatgroup")
        XCTAssertTrue(owned[0].ownerID == whoami.userID, "should be \(whoami.userID)")
        owned = try app.getResult(
            from: chatGroupURI + "owner",
            method: .GET,
            headers: userHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(owned.count == 1, "should be 1 chatgroup")
        XCTAssertTrue(owned[0].ownerID == user.userID, "should be \(user.userID)")
        
        // test unjoin
        chatGroupData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/unjoin",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(chatGroupData.seamonkeys[1].username == "@moderator", "should be '@moderator'")
        XCTAssertTrue(chatGroupData.waitingList.isEmpty, "should be 0 waiting")
        
        
        // test block
        let verifiedInfo = try app.getResult(
            from: usersURI + "find/verified",
            method: .GET,
            headers: userHeaders,
            decodeTo: UserInfo.self
        )
        response = try app.getResponse(
            from: usersURI + "\(verifiedInfo.userID)/block",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        response = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
    }
    
    /// `GET /api/v3/chatgroup/open`
    func testOpen() throws {
        // need 2 logged in users
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create chatgroups
        let types = try app.getResult(
            from: chatGroupURI + "types",
            method: .GET,
            headers: userHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let chatGroupContentData = ChatGroupContentData(
            chatGroupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        let chatGroupData1 = try app.getResult(
            from: chatGroupURI + "create",
            method: .POST,
            headers: userHeaders,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        let chatGroupData2 = try app.getResult(
            from: chatGroupURI + "create",
            method: .POST,
            headers: userHeaders,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        
        // test open
        var open = try app.getResult(
            from: chatGroupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(open.count == 2, "should be 2 chatgroups")
        _ = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData1.chatGroupID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: chatGroupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(open.count == 1, "should be 1 chatgroup")
        _ = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData2.chatGroupID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: chatGroupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(open.count == 0, "should be no chatgroup")
        _ = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData1.chatGroupID)/unjoin",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: chatGroupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [ChatGroupData].self
        )
        XCTAssertTrue(open.count == 1, "should be 1 chatgroup")
    }
    
    /// `POST /api/v3/chatgroup/ID/user/ID/add`
    /// `POST /api/v3/chatgroup/ID/user/ID/remove`
    /// `POST /api/v3/chatgroup/ID/update`
    /// `POST /api/v3/chatgroup/ID/candcel`
    func testOwnerModify() throws {
        // need 2 users
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        let whoami = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: CurrentUserData.self
        )
        
        // create chatgroup
        let types = try app.getResult(
            from: chatGroupURI + "types",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        var chatGroupContentData = ChatGroupContentData(
            chatGroupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var chatGroupData = try app.getResult(
            from: chatGroupURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test add user
        chatGroupData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/user/\(user.userID)/add",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(chatGroupData.seamonkeys[1].username == "@\(testUsername)", "should be '@\(testUsername)'")
        
        // test can't add twice
        var response = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/user/\(user.userID)/add",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        
        // test not owner
        response = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/user/\(whoami.userID)/add",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

        // test remove user
        chatGroupData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/user/\(user.userID)/remove",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys[1].username == "AvailableSlot", "should be 'AvailableSlot'")
        XCTAssertTrue(chatGroupData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test can't remove twice
        response = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/user/\(user.userID)/remove",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        
        // test not owner
        response = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/user/\(whoami.userID)/remove",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test update
        chatGroupContentData.chatGroupType = types[1]
        chatGroupContentData.title = "A new title!"
        chatGroupContentData.info = "This is an updated description."
        chatGroupContentData.startTime = String(startTime.advanced(by: 7200))
        chatGroupContentData.endTime = ""
        chatGroupContentData.location = "SeaView Pool"
        chatGroupContentData.minCapacity = 0
        chatGroupContentData.maxCapacity = 10
        chatGroupData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/update",
            method: .POST,
            headers: verifiedHeaders,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        XCTAssert(chatGroupData.chatGroupType == chatGroupContentData.chatGroupType, "should be \(chatGroupContentData.chatGroupType)")
        XCTAssert(chatGroupData.title == chatGroupContentData.title, "should be \(chatGroupContentData.title)")
        XCTAssert(chatGroupData.info == chatGroupContentData.info, "should be \(chatGroupContentData.info)")
        XCTAssert(chatGroupData.endTime == "TBD", "should be 'TBD')")
        XCTAssert(chatGroupData.location == chatGroupContentData.location, "should be \(chatGroupContentData.location)")
        XCTAssert(chatGroupData.seamonkeys.count == 10, "should be \(chatGroupContentData.maxCapacity)")
        XCTAssert(chatGroupData.waitingList.count == 0, "should be no waitList")
        
        // test not owner
        response = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/update",
            method: .POST,
            headers: userHeaders,
            body: chatGroupContentData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test cancel
        chatGroupData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/cancel",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.title.hasPrefix("[CANCELLED]"), "should be cancelled")
        XCTAssertTrue(chatGroupData.info.hasPrefix("[CANCELLED]"), "should be cancelled")
        XCTAssertTrue(chatGroupData.startTime == "[CANCELLED]", "should be cancelled")
        XCTAssertTrue(chatGroupData.endTime == "[CANCELLED]", "should be cancelled")
        XCTAssertTrue(chatGroupData.location.hasPrefix("[CANCELLED]"), "should be cancelled")
        
        // test not owner
        response = try app.getResponse(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/cancel",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
    }
    
    /// `GET /api/v3/chatgroup/ID`
    /// `POST /api/v3/chatgroup/ID/post`
    /// `POST /api/v3/chatgroup/post/ID/delete`
    func testPosts() throws {
        // need 2 users
        let _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create chatgroup
        let types = try app.getResult(
            from: chatGroupURI + "types",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let chatGroupContentData = ChatGroupContentData(
            chatGroupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        let chatGroupData = try app.getResult(
            from: chatGroupURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: chatGroupContentData,
            decodeTo: ChatGroupData.self
        )
        XCTAssertTrue(chatGroupData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test chatgroup detail
        var chatGroupDetailData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: ChatGroupDetailData.self
        )
        XCTAssertTrue(chatGroupDetailData.posts.count == 0, "should be no posts")
        
        // test post
        let postCreateData = PostCreateData(text: "Hello.", imageData: nil)
        chatGroupDetailData = try app.getResult(
            from: chatGroupURI + "\(chatGroupData.chatGroupID)/post",
            method: .POST,
            headers: verifiedHeaders,
            body: postCreateData,
            decodeTo: ChatGroupDetailData.self
        )
        XCTAssertTrue(chatGroupDetailData.posts.count == 1, "should be 1 post")
        
        // test can't delete post
        let response = try app.getResponse(
            from: chatGroupURI + "post/\(chatGroupDetailData.posts[0].postID)/delete",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test delete post
        chatGroupDetailData = try app.getResult(
            from: chatGroupURI + "post/\(chatGroupDetailData.posts[0].postID)/delete",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: ChatGroupDetailData.self
        )
        XCTAssertTrue(chatGroupDetailData.posts.count == 0, "should be no posts")
    }
}

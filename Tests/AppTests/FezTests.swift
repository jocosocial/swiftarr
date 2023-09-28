@testable import App
import Vapor
import XCTest

import Foundation

final class GroupTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let adminURI = "/api/v3/admin/"
    let groupURI = "/api/v3/group/"
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
    
    /// `GET /api/v3/group/types`
    /// `POST /api/v3/group/create`
    func testCreate() throws {
        // get logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test types
        let types = try app.getResult(
            from: groupURI + "types",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertFalse(types.isEmpty, "should be types")
        
        // test group with times
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        var groupContentData = GroupContentData(
            groupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var groupData = try app.getResult(
            from: groupURI + "create",
            method: .POST,
            headers: headers,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys[0].username == "@verified", "should be 'verified'")
        
        // test with no times
        groupContentData.startTime = ""
        groupContentData.endTime = ""
        groupData = try app.getResult(
            from: groupURI + "create",
            method: .POST,
            headers: headers,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.startTime == "TBD", "should be 'TBD'")
        XCTAssertTrue(groupData.endTime == "TBD", "should be 'TBD'")
        
        // test with invalid times
        groupContentData.startTime = "abc"
        groupContentData.endTime = "def"
        let response = try app.getResponse(
            from: groupURI + "create",
            method: .POST,
            headers: headers,
            body: groupContentData
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
    }
    
    /// `POST /api/v3/group/ID/join`
    /// `GET /api/v3/group/joined`
    /// `GET /api/v3/group/owner`
    /// `POST /api/v3/group/ID/unjoin`
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
        
        // create group
        let types = try app.getResult(
            from: groupURI + "types",
            method: .GET,
            headers: userHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let groupContentData = GroupContentData(
            groupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var groupData = try app.getResult(
            from: groupURI + "create",
            method: .POST,
            headers: userHeaders,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys[0].username == "@\(testUsername)", "should be \(testUsername)")
        
        // test join group
        groupData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/join",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(groupData.seamonkeys[1].username == "@verified", "should be '@verified'")
        
        // test waitList
        groupData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/join",
            method: .POST,
            headers: moderatorHeaders,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(groupData.waitingList.count == 1, "should be 1 waiting")
        XCTAssertTrue(groupData.waitingList[0].username == "@moderator", "should be '@moderator'")

        // test joined
        var joined = try app.getResult(
            from: groupURI + "joined",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(joined.count == 1, "should be 1 group")
        var response = try app.getResponse(
            from: groupURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: groupContentData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        joined = try app.getResult(
            from: groupURI + "joined",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(joined.count == 2, "should be 2 groups")
        
        // test owner
        let whoami = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: CurrentUserData.self
        )
        var owned = try app.getResult(
            from: groupURI + "owner",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(owned.count == 1, "should be 1 group")
        XCTAssertTrue(owned[0].ownerID == whoami.userID, "should be \(whoami.userID)")
        owned = try app.getResult(
            from: groupURI + "owner",
            method: .GET,
            headers: userHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(owned.count == 1, "should be 1 group")
        XCTAssertTrue(owned[0].ownerID == user.userID, "should be \(user.userID)")
        
        // test unjoin
        groupData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/unjoin",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(groupData.seamonkeys[1].username == "@moderator", "should be '@moderator'")
        XCTAssertTrue(groupData.waitingList.isEmpty, "should be 0 waiting")
        
        
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
            from: groupURI + "\(groupData.groupID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
    }
    
    /// `GET /api/v3/group/open`
    func testOpen() throws {
        // need 2 logged in users
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create groups
        let types = try app.getResult(
            from: groupURI + "types",
            method: .GET,
            headers: userHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let groupContentData = GroupContentData(
            groupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        let groupData1 = try app.getResult(
            from: groupURI + "create",
            method: .POST,
            headers: userHeaders,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        let groupData2 = try app.getResult(
            from: groupURI + "create",
            method: .POST,
            headers: userHeaders,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        
        // test open
        var open = try app.getResult(
            from: groupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(open.count == 2, "should be 2 groups")
        _ = try app.getResponse(
            from: groupURI + "\(groupData1.groupID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: groupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(open.count == 1, "should be 1 group")
        _ = try app.getResponse(
            from: groupURI + "\(groupData2.groupID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: groupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(open.count == 0, "should be no group")
        _ = try app.getResponse(
            from: groupURI + "\(groupData1.groupID)/unjoin",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: groupURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [GroupData].self
        )
        XCTAssertTrue(open.count == 1, "should be 1 group")
    }
    
    /// `POST /api/v3/group/ID/user/ID/add`
    /// `POST /api/v3/group/ID/user/ID/remove`
    /// `POST /api/v3/group/ID/update`
    /// `POST /api/v3/group/ID/candcel`
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
        
        // create group
        let types = try app.getResult(
            from: groupURI + "types",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        var groupContentData = GroupContentData(
            groupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var groupData = try app.getResult(
            from: groupURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test add user
        groupData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/user/\(user.userID)/add",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(groupData.seamonkeys[1].username == "@\(testUsername)", "should be '@\(testUsername)'")
        
        // test can't add twice
        var response = try app.getResponse(
            from: groupURI + "\(groupData.groupID)/user/\(user.userID)/add",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        
        // test not owner
        response = try app.getResponse(
            from: groupURI + "\(groupData.groupID)/user/\(whoami.userID)/add",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

        // test remove user
        groupData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/user/\(user.userID)/remove",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys[1].username == "AvailableSlot", "should be 'AvailableSlot'")
        XCTAssertTrue(groupData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test can't remove twice
        response = try app.getResponse(
            from: groupURI + "\(groupData.groupID)/user/\(user.userID)/remove",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        
        // test not owner
        response = try app.getResponse(
            from: groupURI + "\(groupData.groupID)/user/\(whoami.userID)/remove",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test update
        groupContentData.groupType = types[1]
        groupContentData.title = "A new title!"
        groupContentData.info = "This is an updated description."
        groupContentData.startTime = String(startTime.advanced(by: 7200))
        groupContentData.endTime = ""
        groupContentData.location = "SeaView Pool"
        groupContentData.minCapacity = 0
        groupContentData.maxCapacity = 10
        groupData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/update",
            method: .POST,
            headers: verifiedHeaders,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        XCTAssert(groupData.groupType == groupContentData.groupType, "should be \(groupContentData.groupType)")
        XCTAssert(groupData.title == groupContentData.title, "should be \(groupContentData.title)")
        XCTAssert(groupData.info == groupContentData.info, "should be \(groupContentData.info)")
        XCTAssert(groupData.endTime == "TBD", "should be 'TBD')")
        XCTAssert(groupData.location == groupContentData.location, "should be \(groupContentData.location)")
        XCTAssert(groupData.seamonkeys.count == 10, "should be \(groupContentData.maxCapacity)")
        XCTAssert(groupData.waitingList.count == 0, "should be no waitList")
        
        // test not owner
        response = try app.getResponse(
            from: groupURI + "\(groupData.groupID)/update",
            method: .POST,
            headers: userHeaders,
            body: groupContentData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test cancel
        groupData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/cancel",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.title.hasPrefix("[CANCELLED]"), "should be cancelled")
        XCTAssertTrue(groupData.info.hasPrefix("[CANCELLED]"), "should be cancelled")
        XCTAssertTrue(groupData.startTime == "[CANCELLED]", "should be cancelled")
        XCTAssertTrue(groupData.endTime == "[CANCELLED]", "should be cancelled")
        XCTAssertTrue(groupData.location.hasPrefix("[CANCELLED]"), "should be cancelled")
        
        // test not owner
        response = try app.getResponse(
            from: groupURI + "\(groupData.groupID)/cancel",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
    }
    
    /// `GET /api/v3/group/ID`
    /// `POST /api/v3/group/ID/post`
    /// `POST /api/v3/group/post/ID/delete`
    func testPosts() throws {
        // need 2 users
        let _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create group
        let types = try app.getResult(
            from: groupURI + "types",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let groupContentData = GroupContentData(
            groupType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        let groupData = try app.getResult(
            from: groupURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: groupContentData,
            decodeTo: GroupData.self
        )
        XCTAssertTrue(groupData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test group detail
        var groupDetailData = try app.getResult(
            from: groupURI + "\(groupData.groupID)",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: GroupDetailData.self
        )
        XCTAssertTrue(groupDetailData.posts.count == 0, "should be no posts")
        
        // test post
        let postCreateData = PostCreateData(text: "Hello.", imageData: nil)
        groupDetailData = try app.getResult(
            from: groupURI + "\(groupData.groupID)/post",
            method: .POST,
            headers: verifiedHeaders,
            body: postCreateData,
            decodeTo: GroupDetailData.self
        )
        XCTAssertTrue(groupDetailData.posts.count == 1, "should be 1 post")
        
        // test can't delete post
        let response = try app.getResponse(
            from: groupURI + "post/\(groupDetailData.posts[0].postID)/delete",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        
        // test delete post
        groupDetailData = try app.getResult(
            from: groupURI + "post/\(groupDetailData.posts[0].postID)/delete",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: GroupDetailData.self
        )
        XCTAssertTrue(groupDetailData.posts.count == 0, "should be no posts")
    }
}

@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class BarrelTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let testVerification = "ABC ABC"
    let adminURI = "/api/v3/admin/"
    let authURI = "/api/v3/auth/"
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
    
    /// `GET /api/v3/user/alertwords`
    /// `GET /api/v3/user/blocks`
    /// `GET /api/v3/user/mutes`
    /// `GET /api/v3/user/mutewords`
    func testDefaultBarrels() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test empty barrels exist
        let alertKeywordData = try app.getResult(
            from: userURI + "alertwords",
            method: .GET,
            headers: headers,
            decodeTo: AlertKeywordData.self
        )
        XCTAssertTrue(alertKeywordData.name == "Alert Keywords", "Alert Keywords")
        XCTAssertTrue(alertKeywordData.keywords.isEmpty, "should be no alerts")

        var blockedUserData = try app.getResult(
            from: userURI + "blocks",
            method: .GET,
            headers: headers,
            decodeTo: BlockedUserData.self
        )
        XCTAssertTrue(blockedUserData.name == "Blocked Users", "Blocked Users")
        XCTAssertTrue(blockedUserData.seamonkeys.isEmpty, "should be no blocks")
        
        let mutedUserData = try app.getResult(
            from: userURI + "mutes",
            method: .GET,
            headers: headers,
            decodeTo: MutedUserData.self
        )
        XCTAssertTrue(mutedUserData.name == "Muted Users", "Muted Users")
        XCTAssertTrue(blockedUserData.seamonkeys.isEmpty, "should be no mutes")
        
        let muteKeywordData = try app.getResult(
            from: userURI + "mutewords",
            method: .GET,
            headers: headers,
            decodeTo: MuteKeywordData.self
        )
        XCTAssertTrue(muteKeywordData.name == "Muted Keywords", "Muted Keywords")
        XCTAssertTrue(muteKeywordData.keywords.isEmpty, "should be no mutes")

        // add sub-account
        let userCreateData = UserCreateData(username: "subaccount", password: testPassword)
        let addedUserData = try app.getResult(
            from: userURI + "add",
            method: .POST,
            headers: headers,
            body: userCreateData,
            decodeTo: AddedUserData.self
        )
        token = try app.login(username: addedUserData.username, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test sub-account has empty blocks barrel
        blockedUserData = try app.getResult(
            from: userURI + "blocks",
            method: .GET,
            headers: headers,
            decodeTo: BlockedUserData.self
        )
        XCTAssertTrue(blockedUserData.name == "Blocked Users", "Blocked Users")
        XCTAssertTrue(blockedUserData.seamonkeys.isEmpty, "should be no blocks")
    }
    
    /// `POST /api/v3/user/barrel`
    /// `GET /api/v3/user/barrels`
    /// `GET /api/v3/user/barrels/seamonkey`
    /// `POST /api/v3/user/barrels/ID/delete`
    /// `POST /api/v3/user/barrels/ID/rename/STRING`
    func testBarrelCreate() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // get some IDs
        let admin = try app.getResult(
            from: usersURI + "find/admin",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        let moderator = try app.getResult(
            from: usersURI + "find/moderator",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )

        // test UUID barrel
        var barrelCreateData = BarrelCreateData(
            name: "Favorites",
            uuidList: [admin.userID, moderator.userID],
            stringList: nil
        )
        var barrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(barrelData.name == "Favorites", "should be 'Favorites'")
        XCTAssertTrue(barrelData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(barrelData.seamonkeys[0].username == "@admin", "should be '@admin'")
        XCTAssertTrue(barrelData.seamonkeys[1].username == "@moderator", "should be '@moderator'")
        XCTAssertNil(barrelData.stringList, "should be nil")
        
        // test string barrel
        let stringData = ["green", "purple"]
        barrelCreateData.name = "Bikeshedding"
        barrelCreateData.uuidList = nil
        barrelCreateData.stringList = stringData
        barrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(barrelData.name == "Bikeshedding", "should be 'Bikeshedding'")
        XCTAssertTrue(barrelData.stringList?.count == 2, "should be 2 words")
        XCTAssertTrue(barrelData.seamonkeys.isEmpty, "should be no seamonkeys")
        
        // test get barrels + sort
        barrelCreateData = BarrelCreateData(
            name: "Favorites 2",
            uuidList: [admin.userID, moderator.userID],
            stringList: nil
        )
        _ = try app.getResponse(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData
        )
        var barrels = try app.getResult(
            from: userURI + "barrels",
            method: .GET,
            headers: headers,
            decodeTo: [BarrelListData].self
        )
        XCTAssertTrue(barrels.count == 7, "should be 4 defaults + 3 created")
        XCTAssertTrue(barrels[0].name == "Blocked Users", "'Blocked Users' should be first")
        XCTAssertTrue(barrels[1].name == "Muted Users", "'Muted Users' should be second")
        XCTAssertTrue(barrels[2].name == "Alert Keywords", "'Alert Keywords' should be third")
        XCTAssertTrue(barrels[3].name == "Muted Keywords", "'Muted Keywords' should be fourth")
        XCTAssertTrue(barrels[4].name == "Bikeshedding", "'Bikeshedding' should be fifth")
        XCTAssertTrue(barrels[5].name == "Favorites", "'Favorites' should be sixth")
        XCTAssertTrue(barrels[6].name == "Favorites 2", "'Favorites 2' should be last")
        
        // test get seamonkeys
        barrels = try app.getResult(
            from: userURI + "barrels/seamonkey",
            method: .GET,
            headers: headers,
            decodeTo: [BarrelListData].self
        )
        XCTAssertTrue(barrels.count == 2, "should be 2 barrels")
        
        // test delete barrel
        let response = try app.getResponse(
            from: userURI + "barrels/\(barrels[1].barrelID)/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
        barrels = try app.getResult(
            from: userURI + "barrels/seamonkey",
            method: .GET,
            headers: headers,
            decodeTo: [BarrelListData].self
        )
        XCTAssertTrue(barrels.count == 1, "should be 1 barrel")

        // test rename barrel
        barrelData = try app.getResult(
            from: userURI + "barrels/\(barrels[0].barrelID)/rename/New%20Name",
            method: .POST,
            headers: headers,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(barrelData.name == "New Name", "should be 'New Name'")
    }
    
    /// `GET /api/v3/user/barrel/ID`
    func testUserBarrel() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create seamonkey barrel
        let admin = try app.getResult(
            from: usersURI + "find/admin",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        let barrelCreateData = BarrelCreateData(
            name: "Favorites",
            uuidList: [admin.userID],
            stringList: nil
        )
        let barrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(barrelData.name == "Favorites", "should be 'Favorites'")

        // test get barrel
        var response = try app.getResponse(
            from: userURI + "barrels/\(barrelData.barrelID)",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 200, "should be 200 OK")
        
        // test bad string
        response = try app.getResponse(
            from: userURI + "barrels/GARBAGE",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 500, "should be 500 Internal Server Error")
        XCTAssertTrue(response.http.body.description.contains("Could not convert"), "Could not convert")
        
        // test bad ID
        response = try app.getResponse(
            from: userURI + "barrels/\(UUID())",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No model")

        // test bad owner
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "barrels/\(barrelData.barrelID)",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not owner"), "not owner")
        
        // FIXME: can't test until other types exist
//        // test wrong type
//        let barrels = try app.getResult(
//            from: userURI + "barrels",
//            method: .GET,
//            headers: headers,
//            decodeTo: [BarrelListData].self
//        )
//        response = try app.getResponse(
//            from: userURI + "barrels/\(barrels[0].barrelID)",
//            method: .GET,
//            headers: headers
//        )
//        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
//        XCTAssertTrue(response.http.body.description.contains("this endpoint"), "this endpoint")
    }
    
    /// `POST /api/v3/user/barrels/ID/delete`
    func testUserBarrelDelete() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create seamonkey barrels
        let admin = try app.getResult(
            from: usersURI + "find/admin",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        let barrelCreateData = BarrelCreateData(
            name: "Favorites",
            uuidList: [admin.userID],
            stringList: nil
        )
        let barrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(barrelData.name == "Favorites", "should be 'Favorites'")
        
        // test bad string
        var response = try app.getResponse(
            from: userURI + "barrels/GARBAGE/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 500, "should be 500 Internal Server Error")
        XCTAssertTrue(response.http.body.description.contains("Could not convert"), "Could not convert")
        
        // test bad ID
        response = try app.getResponse(
            from: userURI + "barrels/\(UUID())/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No model")

        // test bad owner
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "barrels/\(barrelData.barrelID)/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not owner"), "not owner")
        
        // test wrong type
        let barrels = try app.getResult(
            from: userURI + "barrels",
            method: .GET,
            headers: headers,
            decodeTo: [BarrelListData].self
        )
        response = try app.getResponse(
            from: userURI + "barrels/\(barrels[0].barrelID)/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("cannot be deleted"), "cannot be deleted")
        
        // test delete
        token = try app.login(username: "verified", password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "barrels/\(barrelData.barrelID)/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
    }
    
    /// POST /api/v3/user/barrels/ID/rename/STRING`
    func testUserBarrelRename() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create seamonkey barrels
        let admin = try app.getResult(
            from: usersURI + "find/admin",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        let barrelCreateData = BarrelCreateData(
            name: "Favorites",
            uuidList: [admin.userID],
            stringList: nil
        )
        var barrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(barrelData.name == "Favorites", "should be 'Favorites'")
        
        // test bad string
        var response = try app.getResponse(
            from: userURI + "barrels/GARBAGE/rename/New%20Name",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 500, "should be 500 Internal Server Error")
        XCTAssertTrue(response.http.body.description.contains("Could not conver"), "Could not convert")
        
        // test bad ID
        response = try app.getResponse(
            from: userURI + "barrels/\(UUID())/rename/New%20Name",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No model")
        
        // test bad owner
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "barrels/\(barrelData.barrelID)/rename/New%20Name",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not owner"), "not owner")
        
        // test wrong type
        let barrels = try app.getResult(
            from: userURI + "barrels",
            method: .GET,
            headers: headers,
            decodeTo: [BarrelListData].self
        )
        response = try app.getResponse(
            from: userURI + "barrels/\(barrels[0].barrelID)/rename/New%20Name",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("cannot be renamed"), "cannot be renamed")
        
        // test rename
        token = try app.login(username: "verified", password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        barrelData = try app.getResult(
            from: userURI + "barrels/\(barrelData.barrelID)/rename/New%20Name",
            method: .POST,
            headers: headers,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(barrelData.name == "New Name", "should be 'New Name'")
    }
    
    /// `POST /api/v3/user/barrels/ID/add/STRING`
    /// `POST /api/v3/user/barrels/ID/remove/STRING`
    func testBarrelModify() throws {
        // create verified logged in user
        var token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create seamonkey barrel
        let admin = try app.getResult(
            from: usersURI + "find/admin",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        var barrelCreateData = BarrelCreateData(
            name: "Favorites",
            uuidList: [admin.userID],
            stringList: nil
        )
        var uuidBarrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(uuidBarrelData.name == "Favorites", "should be 'Favorites'")
        
        // create userWords barrel
        barrelCreateData = BarrelCreateData(
            name: "Words",
            uuidList: nil,
            stringList: ["apple"]
        )
        let wordBarrelData = try app.getResult(
            from: userURI + "barrel",
            method: .POST,
            headers: headers,
            body: barrelCreateData,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(wordBarrelData.name == "Words", "should be 'Words'")

        // get test UUID
        let moderator = try app.getResult(
            from: usersURI + "find/moderator",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        
        // test bad ID string
        var response = try app.getResponse(
            from: userURI + "barrels/GARBAGE/add/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 500, "should be 500 Internal Server Error")
        XCTAssertTrue(response.http.body.description.contains("Could not convert"), "Could not convert")
        response = try app.getResponse(
            from: userURI + "barrels/GARBAGE/remove/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 500, "should be 500 Internal Server Error")
        XCTAssertTrue(response.http.body.description.contains("Could not convert"), "Could not convert")

        // test bad ID
        response = try app.getResponse(
            from: userURI + "barrels/\(UUID())/add/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No model")
        response = try app.getResponse(
            from: userURI + "barrels/\(UUID())/remove/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No model")

        // test bad owner
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "barrels/\(uuidBarrelData.barrelID)/add/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not owner"), "not owner")
        response = try app.getResponse(
            from: userURI + "barrels/\(uuidBarrelData.barrelID)/remove/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not owner"), "not owner")
        response = try app.getResponse(
            from: userURI + "barrels/\(wordBarrelData.barrelID)/add/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not owner"), "not owner")
        response = try app.getResponse(
            from: userURI + "barrels/\(wordBarrelData.barrelID)/remove/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not owner"), "not owner")

        // test wrong type
        let barrels = try app.getResult(
            from: userURI + "barrels",
            method: .GET,
            headers: headers,
            decodeTo: [BarrelListData].self
        )
        response = try app.getResponse(
            from: userURI + "barrels/\(barrels[0].barrelID)/add/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("this endpoint"), "this endpoint")
        response = try app.getResponse(
            from: userURI + "barrels/\(barrels[0].barrelID)/remove/\(moderator.userID)",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("this endpoint"), "this endpoint")
        response = try app.getResponse(
            from: userURI + "barrels/\(barrels[0].barrelID)/add/banana",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("this endpoint"), "this endpoint")
        response = try app.getResponse(
            from: userURI + "barrels/\(barrels[0].barrelID)/remove/banana",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("this endpoint"), "this endpoint")

        // test add uuid
        token = try app.login(username: "verified", password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        uuidBarrelData = try app.getResult(
            from: userURI + "barrels/\(uuidBarrelData.barrelID)/add/\(moderator.userID)",
            method: .POST,
            headers: headers,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(uuidBarrelData.seamonkeys.count == 2, "should have 2")
        XCTAssertTrue(uuidBarrelData.seamonkeys[1].username == "@moderator", "should be '@moderator'")
        
        // test remove uuid
        uuidBarrelData = try app.getResult(
            from: userURI + "barrels/\(uuidBarrelData.barrelID)/remove/\(moderator.userID)",
            method: .POST,
            headers: headers,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(uuidBarrelData.seamonkeys.count == 1, "should have 1")
        XCTAssertTrue(uuidBarrelData.seamonkeys[0].username == "@admin", "should be '@admin'")
        
        // test add string
        uuidBarrelData = try app.getResult(
            from: userURI + "barrels/\(wordBarrelData.barrelID)/add/banana",
            method: .POST,
            headers: headers,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(uuidBarrelData.stringList?.count == 2, "should have 2")
        XCTAssertTrue(uuidBarrelData.stringList?[1] == "banana", "should be 'banana'")
        
        // test remove string
        uuidBarrelData = try app.getResult(
            from: userURI + "barrels/\(wordBarrelData.barrelID)/remove/apple",
            method: .POST,
            headers: headers,
            decodeTo: BarrelData.self
        )
        XCTAssertTrue(uuidBarrelData.stringList?.count == 1, "should have 1")
        XCTAssertTrue(uuidBarrelData.stringList?[0] == "banana", "should be 'banana'")
    }
    
    func testAlertWordsModify() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test add
        var alertKeywordData = try app.getResult(
            from: userURI + "alertwords",
            method: .GET,
            headers: headers,
            decodeTo: AlertKeywordData.self
        )
        XCTAssertTrue(alertKeywordData.keywords.isEmpty, "should be no keywords")
        alertKeywordData = try app.getResult(
            from: userURI + "alertwords/add/test%20phrase",
            method: .POST,
            headers: headers,
            decodeTo: AlertKeywordData.self
        )
        XCTAssertTrue(alertKeywordData.keywords.count == 1, "should be 1 keyword")
        XCTAssertTrue(alertKeywordData.keywords[0] == "test phrase", "should be 'test phrase'")
        
        // test sort
        alertKeywordData = try app.getResult(
            from: userURI + "alertwords/add/Brains",
            method: .POST,
            headers: headers,
            decodeTo: AlertKeywordData.self
        )
        XCTAssertTrue(alertKeywordData.keywords.count == 2, "should be 2 keywords")
        XCTAssertTrue(alertKeywordData.keywords[1] == "test phrase", "should be 'test phrase'")
        
        // test remove
        alertKeywordData = try app.getResult(
            from: userURI + "alertwords/remove/test%20phrase",
            method: .POST,
            headers: headers,
            decodeTo: AlertKeywordData.self
        )
        XCTAssertTrue(alertKeywordData.keywords.count == 1, "should be 1 keyword")
        XCTAssertTrue(alertKeywordData.keywords[0] == "Brains", "should be 'Brains'")
    }
    
    func testMuteWordsModify() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test add
        var muteKeywordData = try app.getResult(
            from: userURI + "mutewords",
            method: .GET,
            headers: headers,
            decodeTo: MuteKeywordData.self
        )
        XCTAssertTrue(muteKeywordData.keywords.isEmpty, "should be no keywords")
        muteKeywordData = try app.getResult(
            from: userURI + "mutewords/add/test%20phrase",
            method: .POST,
            headers: headers,
            decodeTo: MuteKeywordData.self
        )
        XCTAssertTrue(muteKeywordData.keywords.count == 1, "should be 1 keyword")
        XCTAssertTrue(muteKeywordData.keywords[0] == "test phrase", "should be 'test phrase'")
        
        // test sort
        muteKeywordData = try app.getResult(
            from: userURI + "mutewords/add/Brains",
            method: .POST,
            headers: headers,
            decodeTo: MuteKeywordData.self
        )
        XCTAssertTrue(muteKeywordData.keywords.count == 2, "should be 2 keywords")
        XCTAssertTrue(muteKeywordData.keywords[1] == "test phrase", "should be 'test phrase'")
        
        // test remove
        muteKeywordData = try app.getResult(
            from: userURI + "mutewords/remove/test%20phrase",
            method: .POST,
            headers: headers,
            decodeTo: MuteKeywordData.self
        )
        XCTAssertTrue(muteKeywordData.keywords.count == 1, "should be 1 keyword")
        XCTAssertTrue(muteKeywordData.keywords[0] == "Brains", "should be 'Brains'")
    }
    
    func testUserBlock() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test bad user
        var response = try app.getResponse(
            from: usersURI + "\(UUID())/block",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No Model")
        
        // test block
        let unverified = try app.getResult(
            from: usersURI + "find/unverified",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/block",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        let blockedUserData = try app.getResult(
            from: userURI + "blocks",
            method: .GET,
            headers: headers,
            decodeTo: BlockedUserData.self
        )
        XCTAssertTrue(blockedUserData.seamonkeys.count == 1, "should be 1 block")
        XCTAssertTrue(blockedUserData.seamonkeys[0].username == "@unverified", "should be '@unverified'")
    }

    func testUserUnblock() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test bad user
        var response = try app.getResponse(
            from: usersURI + "\(UUID())/unblock",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No Model")
        
        // test not blocked
        let unverified = try app.getResult(
            from: usersURI + "find/unverified",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/unblock",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("not found in"), "not found in")

        // test unblock
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/block",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/unblock",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
    }
    
    func testUserMute() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test bad user
        var response = try app.getResponse(
            from: usersURI + "\(UUID())/mute",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No Model")
        
        // test block
        let unverified = try app.getResult(
            from: usersURI + "find/unverified",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/mute",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        let mutedUserData = try app.getResult(
            from: userURI + "mutes",
            method: .GET,
            headers: headers,
            decodeTo: MutedUserData.self
        )
        XCTAssertTrue(mutedUserData.seamonkeys.count == 1, "should be 1 block")
        XCTAssertTrue(mutedUserData.seamonkeys[0].username == "@unverified", "should be '@unverified'")
    }

    func testUserUnmute() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test bad user
        var response = try app.getResponse(
            from: usersURI + "\(UUID())/unmute",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("No model"), "No Model")
        
        // test not blocked
        let unverified = try app.getResult(
            from: usersURI + "find/unverified",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/unmute",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("not found in"), "not found in")

        // test unblock
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/mute",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        response = try app.getResponse(
            from: usersURI + "\(unverified.userID)/unmute",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
    }

}

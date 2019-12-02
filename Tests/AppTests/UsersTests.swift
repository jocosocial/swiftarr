@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class UsersTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
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
    
    /// `GET /api/v3/users/ID`
    /// `GET /api/v3/users/find/STRING`
    func testUsersFind() throws {
        // create logged in user
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        let token = try app.login(username: user.username, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test userHandler
        let preResult = try app.getResult(
            from: usersURI + "\(user.userID)",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        XCTAssertTrue(preResult.userID == user.userID, "should be \(user.userID)")
        
        // test updatedAt changes
        sleep(1)
        let newUsername = "newusername"
        let userUsernameData = UserUsernameData(username: newUsername)
        _ = try app.getResponse(
            from: userURI + "username",
            method: .POST,
            headers: headers,
            body: userUsernameData
        )
        let postResult = try app.getResult(
            from: usersURI + "\(user.userID)",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        XCTAssertTrue(postResult.userID == preResult.userID, "should be \(preResult.userID)")
        XCTAssertTrue(postResult.username == newUsername, "should be \(newUsername)")
        XCTAssertFalse(preResult.updatedAt == postResult.updatedAt, "should be different dates")
                
        // test findHandler with UUID
        let uuidResult = try app.getResult(
            from: usersURI + "find/\(user.userID)",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        XCTAssertTrue(uuidResult.userID == user.userID, "should be \(user.userID)")

        // test findHandler with username
        let usernameResult = try app.getResult(
            from: usersURI + "find/\(newUsername)",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        XCTAssertTrue(usernameResult.userID == user.userID, "should be \(user.userID)")

        // test findHandler with garbage
        let usernameResponse = try app.getResponse(
            from: usersURI + "find/GARBAGE",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(usernameResponse.http.status.code == 404, "should be 404 Not Found")
    }
    
    /// `GET /api/v3/users/ID/header`
    func testUsersHeader() throws {
        // create user
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.basicAuthorization = BasicAuthorization(username: testUsername, password: testPassword)
        
        // test header
        var header = try app.getResult(
            from: usersURI + "\(user.userID)/header",
            method: .GET,
            headers: headers,
            decodeTo: UserHeader.self
        )
        XCTAssertTrue(header.userID == user.userID, "should be \(user.userID)")
        XCTAssertTrue(header.displayedName.contains("@\(user.username)"), "@\(user.username)")
        
        // test update
        let userProfileData = UserProfileData(
            about: "",
            displayName: "Cookie Monster",
            email: "",
            homeLocation: "",
            message: "",
            preferredPronoun: "",
            realName: "",
            roomNumber: "",
            limitAccess: false
        )
        _ = try app.getResponse(
            from: userURI + "profile",
            method: .POST,
            headers: headers,
            body: userProfileData
        )
        header = try app.getResult(
            from: usersURI + "\(user.userID)/header",
            method: .GET,
            headers: headers,
            decodeTo: UserHeader.self
        )
        XCTAssertTrue(header.displayedName.contains("Cookie Monster (@"), "Cookie Monster (@\(user.username))")
    }
    
    /// `GET /api/v3/users/match/username/STRING`
    func testMatchUsername() throws {
        // create logged in user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        let token = try app.login(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test basic
        var usernames = try app.getResult(
            from: usersURI + "match/username/ver",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 2, "should have 'unverified','verified'")
        
        // test case-insensitive
        usernames = try app.getResult(
            from: usersURI + "match/username/VER",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 2, "should have 'unverified', 'verified'")
        
        // test single character
        usernames = try app.getResult(
            from: usersURI + "match/username/a",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 4, "'admin', 'quarantined`, 'banned', 'moderator'")
        
        // test nada
        usernames = try app.getResult(
            from: usersURI + "match/username/x",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 0, "should have no matches")
        
        // test + separator, and ensure prepended @
        _ = try app.createUser(username: "jim+kim", password: testPassword, on: conn)
        usernames = try app.getResult(
            from: usersURI + "match/username/+",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'jim+kim'")
        XCTAssertTrue(usernames[0] == "@jim+kim", "should be '@jim+kim'")
        
        // test - separator
        _ = try app.createUser(username: "jim-kim", password: testPassword, on: conn)
        usernames = try app.getResult(
            from: usersURI + "match/username/-",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'jim-kim'")
        XCTAssertTrue(usernames[0] == "@jim-kim", "should be '@jim-kim'")

        // test _ separator
        _ = try app.createUser(username: "jim_kim", password: testPassword, on: conn)
        usernames = try app.getResult(
            from: usersURI + "match/username/_",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'jim_kim'")
        XCTAssertTrue(usernames[0] == "@jim_kim", "should be '@jim_kim'")

        // test . separator
        _ = try app.createUser(username: "jim.kim", password: testPassword, on: conn)
        usernames = try app.getResult(
            from: usersURI + "match/username/.",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'jim.kim'")
        XCTAssertTrue(usernames[0] == "@jim.kim", "should be '@jim.kim'")
    }
    
    /// `GET /api/v3/users/match/allnames/STRING`
    func testMatchAllNames() throws {
        // create logged in user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        let token = try app.login(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test basic
        var usernames = try app.getResult(
            from: usersURI + "match/allnames/ver",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        XCTAssertTrue(usernames.count == 2, "should have 'unverified','verified'")
        
        // test formatted username
        usernames = try app.getResult(
            from: usersURI + "match/allnames/@ver",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'verified'")
        XCTAssertTrue(usernames[0].userSearch == "@verified", "should be '@verified'")

        // populate
        let userProfileData = UserProfileData(
            about: "",
            displayName: "%Sir% 😀 Cookie!",
            email: "",
            homeLocation: "",
            message: "",
            preferredPronoun: "",
            realName: "Alistair Cookie",
            roomNumber: "",
            limitAccess: false
        )
        _ = try app.getResponse(
            from: userURI + "profile",
            method: .POST,
            headers: headers,
            body: userProfileData
        )
        
        // ensure userSearch returns intact
        usernames = try app.getResult(
            from: usersURI + "match/allnames/sir",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'grundoon'")
        XCTAssertTrue(usernames[0].userSearch == "%Sir% 😀 Cookie! (@grundoon) - Alistair Cookie", "should be")

        // test !
        usernames = try app.getResult(
            from: usersURI + "match/allnames/!",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'grundoon'")
        XCTAssertTrue(usernames[0].userSearch.contains("grundoon"), "should be 'grundoon'")

        // test unicode
        usernames = try app.getResult(
            from: usersURI + "match/allnames/%F0%9F%98%80",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'grundoon'")
        XCTAssertTrue(usernames[0].userSearch.contains("grundoon"), "should be 'grundoon'")

        // test %20 space
        usernames = try app.getResult(
            from: usersURI + "match/allnames/r%20c",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        XCTAssertTrue(usernames.count == 1, "should have 'grundoon'")
        XCTAssertTrue(usernames[0].userSearch.contains("grundoon"), "should be 'grundoon'")

        // test bad @
        let response = try app.getResponse(
            from: usersURI + "match/allnames/@",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not a permitted"), "not a permitted")
    }
    
    func testUserReport() throws {
        // create logged in user
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test submit
        let userInfo = try app.getResult(
            from: usersURI + "find/verified",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        var userReportData = UserReportData(message: "")
        var response = try app.getResponse(
            from: usersURI + "\(userInfo.userID)/report",
            method: .POST,
            headers: headers,
            body: userReportData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        
        // test no limit
        userReportData.message = "Ugh."
        response = try app.getResponse(
            from: usersURI + "\(userInfo.userID)/report",
            method: .POST,
            headers: headers,
            body: userReportData
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
        XCTAssertTrue(reports[0].submitterID == user.userID, "should be \(user.userID)")
        XCTAssertTrue(reports[0].reportedID == userInfo.userID.uuidString, "should be \(userInfo.userID.uuidString)")
        XCTAssertFalse(reports[0].isClosed, "should be open")
        XCTAssertTrue(reports[1].submitterMessage == userReportData.message, "should be \(userReportData.message)")
    }
}

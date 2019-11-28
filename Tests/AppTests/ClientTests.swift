@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class ClientTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let testClientname = "client"
    let adminURI = "/api/v3/admin/"
    let authURI = "/api/v3/auth/"
    let clientURI = "/api/v3/client/"
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
    
    /// Ensure that ClientUsers migration was successful.
    func testClientMigration() throws {
        // test client exists
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        let credentials = BasicAuthorization(username: testUsername, password: testPassword)
        var headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        let result = try app.getResult(
            from: usersURI + "find/\(testClientname)",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        XCTAssertTrue(result.username == testClientname, "should be \(testClientname)")
        
        // test client can login
        let token = try app.login(username: testClientname, password: testPassword, on: conn)
        XCTAssertFalse(token.token.isEmpty, "should receive valid token string")
        
        // test client can recover
        let userRecoveryData = UserRecoveryData(username: testClientname, recoveryKey: "recovery key")
        let recoveryresult = try app.getResult(
            from: authURI + "recovery",
            method: .POST,
            body: userRecoveryData,
            decodeTo: TokenStringData.self
        )
        XCTAssertFalse(recoveryresult.token.isEmpty, "should receive valid token string")
    }
    
    /// `GET /api/v3/client/user/updates/since/DATE`
    func testUserUpdates() throws {
        // create user for x-swiftarr-user header
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        
        // create logged in client
        var token = try app.login(username: testClientname, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        
        // get client info for later
        headers.basicAuthorization = BasicAuthorization(username: testClientname, password: testPassword)
        let currentUserData = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: headers,
            decodeTo: CurrentUserData.self
        )

        // test no header
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        var response = try app.getResponse(
            from: clientURI + "user/updates/since/-1",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("no valid"), "no valid")

        // test bad header
        let uuid = UUID()
        headers.add(name: "x-swiftarr-user", value: "\(uuid)")
        response = try app.getResponse(
            from: clientURI + "user/updates/since/-1",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("user not found"), "user not found")

        // test user is client
        headers.replaceOrAdd(name: "x-swiftarr-user", value: "\(currentUserData.userID)")
        response = try app.getResponse(
            from: clientURI + "user/updates/since/-1",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("cannot be client"), "cannot be client")

        // test updates since -1
        headers.replaceOrAdd(name: "x-swiftarr-user", value: "\(user.userID)")
        var users = try app.getResult(
            from: clientURI + "user/updates/since/-1",
            method: .GET,
            headers: headers,
            decodeTo: [UserInfo].self
        )
        XCTAssertTrue(users.count > 1, "should be all accounts")

        // create update
        var currentDate = Date()
        let userProfileData = UserProfileData(
            about: "",
            displayName: "Client User",
            email: "",
            homeLocation: "",
            message: "",
            preferredPronoun: "",
            realName: "",
            roomNumber: "",
            limitAccess: false
        )
        response = try app.getResponse(
            from: userURI + "profile",
            method: .POST,
            headers: headers,
            body: userProfileData
        )
        XCTAssertTrue(response.http.status.code == 200, "should be 200 OK")
        
        // test updates with Double
        sleep(1)
        users = try app.getResult(
            from: clientURI + "user/updates/since/\(currentDate.timeIntervalSince1970)",
            method: .GET,
            headers: headers,
            decodeTo: [UserInfo].self
        )
        XCTAssertTrue(users.count == 1, "should be 1 updated account")

        // test updates with 8601 string
        var isoString = ""
        if #available(OSX 10.12, *) {
            isoString = ISO8601DateFormatter().string(from: currentDate)
        } else {
            // Fallback on earlier versions
        }
        users = try app.getResult(
            from: clientURI + "user/updates/since/\(isoString)",
            method: .GET,
            headers: headers,
            decodeTo: [UserInfo].self
        )
        XCTAssertTrue(users.count == 1, "should be 1 updated account")
        
        // test no updates
        sleep(1)
        currentDate = Date()
        users = try app.getResult(
            from: clientURI + "user/updates/since/\(currentDate.timeIntervalSince1970)",
            method: .GET,
            headers: headers,
            decodeTo: [UserInfo].self
        )
        XCTAssertTrue(users.count == 0, "should be no updated accounts")

        // test bad date
        response = try app.getResponse(
            from: clientURI + "user/updates/since/GARBAGE",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("not a recognized"), "not a recognized")
        
        // test not a client
        _ = try app.createUser(username: "notclient", password: testPassword, on: conn)
        token = try app.login(username: "notclient", password: testPassword, on: conn)
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: clientURI + "user/updates/since/\(currentDate.timeIntervalSince1970)",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("clients only"), "clients only")
    }
    
    /// `GET /api/v3/client/user/headers/since/DATE`
    func testUserHeaders() throws {
        // create user for x-swiftarr-user header
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        
        // create logged in client
        var token = try app.login(username: testClientname, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        
        // get client info for later
        headers.basicAuthorization = BasicAuthorization(username: testClientname, password: testPassword)
        let currentUserData = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: headers,
            decodeTo: CurrentUserData.self
        )

        // test no header
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        var response = try app.getResponse(
            from: clientURI + "user/headers/since/-1",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("no valid"), "no valid")

        // test bad header
        let uuid = UUID()
        headers.add(name: "x-swiftarr-user", value: "\(uuid)")
        response = try app.getResponse(
            from: clientURI + "user/headers/since/-1",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("user not found"), "user not found")

        // test user is client
        headers.replaceOrAdd(name: "x-swiftarr-user", value: "\(currentUserData.userID)")
        response = try app.getResponse(
            from: clientURI + "user/headers/since/-1",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("cannot be client"), "cannot be client")

        // test updates since -1
        headers.replaceOrAdd(name: "x-swiftarr-user", value: "\(user.userID)")
        var users = try app.getResult(
            from: clientURI + "user/headers/since/-1",
            method: .GET,
            headers: headers,
            decodeTo: [UserHeader].self
        )
        XCTAssertTrue(users.count > 1, "should be all accounts")
        
        // create update
        var currentDate = Date()
        let userProfileData = UserProfileData(
            about: "",
            displayName: "Client User",
            email: "",
            homeLocation: "",
            message: "",
            preferredPronoun: "",
            realName: "",
            roomNumber: "",
            limitAccess: false
        )
        response = try app.getResponse(
            from: userURI + "profile",
            method: .POST,
            headers: headers,
            body: userProfileData
        )
        XCTAssertTrue(response.http.status.code == 200, "should be 200 OK")

        // test headers with 8601 string
        sleep(1)
        var isoString = ""
        if #available(OSX 10.12, *) {
            isoString = ISO8601DateFormatter().string(from: currentDate)
        } else {
            // Fallback on earlier versions
        }
        users = try app.getResult(
            from: clientURI + "user/headers/since/\(isoString)",
            method: .GET,
            headers: headers,
            decodeTo: [UserHeader].self
        )
        XCTAssertTrue(users.count == 1, "should be 1 updated header")
        
        // test no updates
        sleep(1)
        currentDate = Date()
        users = try app.getResult(
            from: clientURI + "user/headers/since/\(currentDate.timeIntervalSince1970)",
            method: .GET,
            headers: headers,
            decodeTo: [UserHeader].self
        )
        XCTAssertTrue(users.count == 0, "should be no updated headers")

        // test bad date
        response = try app.getResponse(
            from: clientURI + "user/updates/since/GARBAGE",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("not a recognized"), "not a recognized")

        // test not a client
        _ = try app.createUser(username: "notclient", password: testPassword, on: conn)
        token = try app.login(username: "notclient", password: testPassword, on: conn)
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: clientURI + "user/headers/since/\(currentDate.timeIntervalSince1970)",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("clients only"), "clients only")
    }
    
    func testUsersearch() throws {
        // create user for x-swiftarr-user header
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        
        // create logged in client
        let token = try app.login(username: testClientname, password: testPassword, on: conn)
        var headers = HTTPHeaders()

        // get client info for later
        headers.basicAuthorization = BasicAuthorization(username: testClientname, password: testPassword)
        let currentUserData = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: headers,
            decodeTo: CurrentUserData.self
        )

        // test no header
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        var response = try app.getResponse(
            from: clientURI + "usersearch",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("no valid"), "no valid")

        // test bad header
        let uuid = UUID()
        headers.add(name: "x-swiftarr-user", value: "\(uuid)")
        response = try app.getResponse(
            from: clientURI + "usersearch",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("user not found"), "user not found")
        
        // test user is client
        headers.replaceOrAdd(name: "x-swiftarr-user", value: "\(currentUserData.userID)")
        response = try app.getResponse(
            from: clientURI + "usersearch",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 401, "should be 401 Unauthorized")
        XCTAssertTrue(response.http.body.description.contains("cannot be client"), "cannot be client")
        
        // test
        headers.replaceOrAdd(name: "x-swiftarr-user", value: "\(user.userID)")
        var userSearches = try app.getResult(
            from: clientURI + "usersearch",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        let count = userSearches.count
        XCTAssertTrue(userSearches[0].userSearch.contains("@admin"), "should be '@admin'")
        _ = try app.createUser(username: "zarathustra", password: testPassword, on: conn)
        userSearches = try app.getResult(
            from: clientURI + "usersearch",
            method: .GET,
            headers: headers,
            decodeTo: [UserSearch].self
        )
        XCTAssertTrue(userSearches.count == count + 1, "should be \(count) + 1")
        XCTAssertTrue(userSearches[count].userSearch.contains("@zara"), "should be '@zarathustra")
    }
}

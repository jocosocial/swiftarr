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
            decodeTo: User.Public.self
        )
        XCTAssertTrue(preResult.id == user.userID, "should be \(user.userID)")
        
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
            decodeTo: User.Public.self
        )
        XCTAssertTrue(postResult.id == preResult.id, "should be \(preResult.id)")
        XCTAssertTrue(postResult.username == newUsername, "should be \(newUsername)")
        XCTAssertFalse(preResult.updatedAt == postResult.updatedAt, "should be different dates")
                
        // test findHandler with UUID
        let uuidResult = try app.getResult(
            from: usersURI + "find/\(user.userID)",
            method: .GET,
            headers: headers,
            decodeTo: User.Public.self
        )
        XCTAssertTrue(uuidResult.id == user.userID, "should be \(user.userID)")

        // test findHandler with username
        let usernameResult = try app.getResult(
            from: usersURI + "find/\(newUsername)",
            method: .GET,
            headers: headers,
            decodeTo: User.Public.self
        )
        XCTAssertTrue(usernameResult.id == user.userID, "should be \(user.userID)")

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
            decodeTo: UserProfile.Header.self
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
            decodeTo: UserProfile.Header.self
        )
        XCTAssertTrue(header.displayedName.contains("Cookie Monster (@"), "Cookie Monster (@\(user.username))")
    }
}

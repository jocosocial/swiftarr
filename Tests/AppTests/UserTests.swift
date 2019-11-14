@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class UserTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let testVerification = "ABC ABC"
    let authURI = "/api/v3/auth/"
    let testURI = "/api/v3/test/"
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
    // Note: We migrate an "admin" user during boot, so it is always present as `.first()`.
    
    /// Ensure that `UserAccessLevel` values are ordered and comparable by `.rawValue`.
    func testUserAccessLevelsAreOrdered() throws {
        let accessLevel0: UserAccessLevel = .unverified
        let accessLevel1: UserAccessLevel = .banned
        let accessLevel2: UserAccessLevel = .quarantined
        let accessLevel3: UserAccessLevel = .verified
        let accessLevel4: UserAccessLevel = .moderator
        let accessLevel5: UserAccessLevel = .tho
        let accessLevel6: UserAccessLevel = .admin
        
        XCTAssert(accessLevel0.rawValue < accessLevel1.rawValue)
        XCTAssert(accessLevel1.rawValue > accessLevel0.rawValue && accessLevel1.rawValue < accessLevel2.rawValue)
        XCTAssert(accessLevel2.rawValue > accessLevel1.rawValue && accessLevel2.rawValue < accessLevel3.rawValue)
        XCTAssert(accessLevel3.rawValue > accessLevel2.rawValue && accessLevel3.rawValue < accessLevel4.rawValue)
        XCTAssert(accessLevel4.rawValue > accessLevel3.rawValue && accessLevel4.rawValue < accessLevel5.rawValue)
        XCTAssert(accessLevel5.rawValue > accessLevel4.rawValue && accessLevel5.rawValue < accessLevel6.rawValue)
        XCTAssert(accessLevel6.rawValue > accessLevel5.rawValue)
    }
    
    /// `GET /api/v3/test/getregistrationcodes`
    func testRegistrationCodesMigration() throws {
        let codes = try app.getResult(
            from: testURI + "getregistrationcodes",
            decodeTo: [RegistrationCode].self
        )
        XCTAssertTrue(codes.count == 10, "there are 10 codes in the test seed file")
    }
    
    /// `POST /api/v3/user/create`
    /// `User.create()` testing convenience helper
    /// `GET /api/v3/test/getusers`
    /// `GET /api/v3/test/getprofiles``
    func testUserCreation() throws {
        // a specified user via helper
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        // a random user via helper
        _ = try app.createUser(password: testPassword, on: conn)
        // a user via API
        let apiUsername = "apiuser"
        let userCreateData = UserCreateData(username: apiUsername, password: "password")
        let result = try app.getResult(
            from: userURI + "create",
            method: .POST,
            body: userCreateData,
            decodeTo: CreatedUserData.self
        )
        
        // check user creations
        let users = try app.getResult(from: testURI + "/getusers", decodeTo: [User].self)
        XCTAssertTrue(users.count == 10, "should be 10 users")
        XCTAssertTrue(users[0].username == "admin", "'admin' should be first user")
        XCTAssertTrue(users[7].username == user.username, "should be `\(testUsername)`")
        XCTAssertNotNil(UUID(uuidString: users[8].username), "should be a valid UUID")
        XCTAssertTrue(users.last?.username == result.username, "last user should be '\(apiUsername)'")
        
        // check profile creations
        let profiles = try app.getResult(
            from: testURI + "/getprofiles",
            method: .GET,
            decodeTo: [UserProfile].self
        )
        XCTAssert(profiles.count == 10, "should be 10 profiles")
        XCTAssertEqual(profiles.last?.userID, users.last?.id, "profile.userID should be user.id")
        
        // test duplicate user
        let response = try app.getResponse(
            from: userURI + "create",
            method: .POST,
            body: userCreateData
        )
        XCTAssertTrue(response.http.status.code == 409, "should be 409 Conflict")
        XCTAssertTrue(response.http.body.description.contains("not available"), "not available")
    }
    
    /// `POST /api/v3/user/verify`
    func testUserVerify() throws {
        // create user
        let createdUserData = try app.createUser(username: testUsername,password: testPassword, on: conn)
        var credentials = BasicAuthorization(username: testUsername, password: testPassword)
        var headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        
        // test bad code
        var userVerifyData = UserVerifyData(verification: "CBA CBA")
        var response = try app.getResponse(
            from: userURI + "verify",
            method: .POST,
            headers: headers,
            body: userVerifyData
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("not found"), "not found")
        
        // test good code
        // check accessLevel is .unverified
        let userID = "\(createdUserData.userID)"
        let adminToken = try app.login(username: "admin", on: conn)
        let adminCredentials = BearerAuthorization(token: adminToken.token)
        var adminHeaders = HTTPHeaders()
        adminHeaders.bearerAuthorization = adminCredentials
        var user = try app.getResult(
            from: "/api/v3/admin/users/" + userID,
            method: .GET,
            headers: adminHeaders,
            decodeTo: User.self
        )
        XCTAssertTrue(user.accessLevel == .unverified, "should be .unverified")
        // verify with good code
        userVerifyData = UserVerifyData(verification: testVerification)
        response = try app.getResponse(
            from: userURI + "verify",
            method: .POST,
            headers: headers,
            body: userVerifyData
        )
        XCTAssertTrue(response.http.status.code == 200, "should be 200 OK")
        // check accessLevel has been applied
        user = try app.getResult(
            from: "/api/v3/admin/users/" + userID,
            method: .GET,
            headers: adminHeaders,
            decodeTo: User.self
        )
        XCTAssertTrue(user.accessLevel == .verified, "should be .verified")
        
        // test already verified
        response = try app.getResponse(
            from: userURI + "verify",
            method: .POST,
            headers: headers,
            body: userVerifyData
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("already verified"), "already verified")
        
        // test duplicate code
        _ = try app.createUser(username: "testUser2", password: testPassword, on: conn)
        credentials = BasicAuthorization(username: "testUser2", password: testPassword)
        headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        
        userVerifyData.verification = testVerification
        response = try app.getResponse(
            from: userURI + "verify",
            method: .POST,
            headers: headers,
            body: userVerifyData
        )
        XCTAssertTrue(response.http.status.code == 409, "should be 409 Conflict")
        XCTAssertTrue(response.http.body.description.contains("been used"), "been used")
    }
    
    /// `POST /api/v3/auth/recovery`
    func testAuthRecovery() throws {
        // create verified user
        let createdUserData = try app.createUser(username: testUsername, password: testPassword, on: conn)
        let userVerifyData = UserVerifyData(verification: testVerification)
        let credentials = BasicAuthorization(username: testUsername, password: testPassword)
        var headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        _ = try app.getResponse(from: userURI + "verify", method: .POST, headers: headers, body: userVerifyData)
        
        // test recovery with key
        var userRecoveryData = UserRecoveryData(username: testUsername, recoveryKey: createdUserData.recoveryKey!)
        var result = try app.getResult(
            from: authURI + "recovery",
            method: .POST,
            body: userRecoveryData,
            decodeTo: TokenStringData.self
        )
        XCTAssertFalse(result.token.isEmpty, "should receive valid token string")
        
        // test recovery with password
        userRecoveryData.recoveryKey = testPassword
        result = try app.getResult(
            from: authURI + "recovery",
            method: .POST,
            body: userRecoveryData,
            decodeTo: TokenStringData.self
        )
        XCTAssertFalse(result.token.isEmpty, "should receive valid token string")
        
        // test recovery with registration code
        userRecoveryData.recoveryKey = testVerification
        result = try app.getResult(
            from: authURI + "recovery",
            method: .POST,
            body: userRecoveryData,
            decodeTo: TokenStringData.self
        )
        XCTAssertFalse(result.token.isEmpty, "should receive valid token string")
        
        // test registration code already used fails
        var response = try app.getResponse(
            from: authURI + "recovery",
            method: .POST,
            body: userRecoveryData
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 bad request")
        XCTAssertTrue(response.http.body.description.contains("recovery key"), "recovery key")
        
        // test bad user
        userRecoveryData.username = "nonsense"
        response = try app.getResponse(
            from: authURI + "recovery",
            method: .POST,
            body: userRecoveryData
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("username"), "username")
        
        // test bad key fails
        userRecoveryData.username = testUsername
        userRecoveryData.recoveryKey = "nonsense"
        response = try app.getResponse(from: authURI + "recovery", method: .POST, body: userRecoveryData)
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("no match"), "no match")
        
        // test too many attempts
        response = try app.getResponse(from: authURI + "recovery", method: .POST, body: userRecoveryData)
        response = try app.getResponse(from: authURI + "recovery", method: .POST, body: userRecoveryData)
        response = try app.getResponse(from: authURI + "recovery", method: .POST, body: userRecoveryData)
        response = try app.getResponse(from: authURI + "recovery", method: .POST, body: userRecoveryData)
        response = try app.getResponse(from: authURI + "recovery", method: .POST, body: userRecoveryData)
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("Team member"), "Team member")
    }
    
    /// `POST /api/v3/auth/login`
    func testAuthLogin() throws {
        // test verified user
        var credentials = BasicAuthorization(username: "verified", password: testPassword)
        var headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        let result = try app.getResult(
            from: authURI + "login",
            method: .POST,
            headers: headers,
            decodeTo: TokenStringData.self
        )
        XCTAssertFalse(result.token.isEmpty, "should receive valid token string")
        
        // test banned user fails
        credentials = BasicAuthorization(username: "banned", password: testPassword)
        headers.basicAuthorization = credentials
        let response = try app.getResponse(
            from: authURI + "login",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("nope"), "nope")
    }
    
    /// `POST /api/v3/auth/logout`
    func testAuthLogout() throws {
        // create logged in user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        let token = try app.login(username: testUsername, on: conn)
        let bearerCredentials = BearerAuthorization(token: token.token)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = bearerCredentials
        
        // test logout
        let response = try app.getResponse(from: authURI + "logout", method: .POST, headers: headers)
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
        
        // test re-login generates new token
        let newToken = try app.login(username: testUsername, on: conn)
        XCTAssertNotEqual(token.token, newToken.token, "tokens should not match")
    }
    
    func testUserPassword() throws {
        // create logged in user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, on: conn)
        let bearerCredentials = BearerAuthorization(token: token.token)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = bearerCredentials
        
        // test password change
        let newPassword = "newpassword"
        let userPasswordData = UserPasswordData(password: newPassword)
        let response = try app.getResponse(
            from: userURI + "password",
            method: .POST,
            headers: headers,
            body: userPasswordData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        
        // test password works
        _ = try app.getResponse(from: authURI + "logout", method: .POST, headers: headers)
        token = try app.login(username: testUsername, password: newPassword, on: conn)
        XCTAssertFalse(token.token.isEmpty, "should receive valid token string")
    }
}

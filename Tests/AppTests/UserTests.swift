@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class UserTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "pasword"
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
        let user = try User.create(username: testUsername, accessLevel: .unverified, on: conn)
        // a random user via helper
        _ = try User.create(accessLevel: .unverified, on: conn)
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
        XCTAssertTrue(users.count == 4, "should be 4 users")
        XCTAssertTrue(users[0].username == "admin", "'admin' should be first user")
        XCTAssertTrue(users[1].username == user.username, "should be `\(testUsername)`")
        XCTAssertNotNil(UUID(uuidString: users[2].username), "should be a valid UUID")
        XCTAssertTrue(users.last?.username == result.username, "last user should be '\(apiUsername)'")
        
        // check profile creations
        let profiles = try app.getResult(
            from: testURI + "/getprofiles",
            method: .GET,
            decodeTo: [UserProfile].self
        )
        XCTAssert(profiles.count == 4, "should be 4 profiles")
        XCTAssertEqual(profiles.last?.userID, users.last?.id, "profile.userID should be user.id")
        
        // test duplicate user
        let response = try app.getResponse(
            from: userURI + "create",
            method: .POST,
            body: userCreateData
        )
        XCTAssertTrue(response.http.status.code == 409, "should be 409 conflict")
    }
}

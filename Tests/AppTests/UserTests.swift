@testable import App
import Vapor
import XCTest
import FluentPostgreSQL

final class UserTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "pasword"
    let authURI = "/api/v3/auth"
    let userURI = "/api/v3/user"
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
//    func testCanRetrieveUserViaAPI() throws {
//        // a specified user
//        let user = try User.create(username: testUsername, accessLevel: .unverified, on: conn)
//        // a random user
//        _ = try User.create(accessLevel: .unverified, on: conn)
//
//        let users = try app.getResult(from: userU, decodeTo: <#T##Content.Protocol#>)
//    }
}

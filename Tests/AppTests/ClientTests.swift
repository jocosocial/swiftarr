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
        var credentials = BasicAuthorization(username: testUsername, password: testPassword)
        var headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        let result = try app.getResult(
            from: usersURI + "find/\(testClientname)",
            method: .GET,
            headers: headers,
            decodeTo: User.Public.self
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
}


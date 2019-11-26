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
    func testBarrelCreation() throws {
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
        XCTAssertTrue(alertKeywordData.keywords.count == 0, "should be no alerts")

        var blockedUserData = try app.getResult(
            from: userURI + "blocks",
            method: .GET,
            headers: headers,
            decodeTo: BlockedUserData.self
        )
        XCTAssertTrue(blockedUserData.name == "Blocked Users", "Blocked Users")
        XCTAssertTrue(blockedUserData.seamonkeys.count == 0, "should be no blocks")
        
        let mutedUserData = try app.getResult(
            from: userURI + "mutes",
            method: .GET,
            headers: headers,
            decodeTo: MutedUserData.self
        )
        XCTAssertTrue(mutedUserData.name == "Muted Users", "Muted Users")
        XCTAssertTrue(blockedUserData.seamonkeys.count == 0, "should be no mutes")
        
        let muteKeywordData = try app.getResult(
            from: userURI + "mutewords",
            method: .GET,
            headers: headers,
            decodeTo: MuteKeywordData.self
        )
        XCTAssertTrue(muteKeywordData.name == "Muted Keywords", "Muted Keywords")
        XCTAssertTrue(muteKeywordData.keywords.count == 0, "should be no mutes")

        // add subaccount
        let userAddData = UserAddData(username: "subaccount", password: testPassword)
        let addedUserData = try app.getResult(
            from: userURI + "add",
            method: .POST,
            headers: headers,
            body: userAddData,
            decodeTo: AddedUserData.self
        )
        token = try app.login(username: addedUserData.username, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test subaccount has empty blocks barrel
        blockedUserData = try app.getResult(
            from: userURI + "blocks",
            method: .GET,
            headers: headers,
            decodeTo: BlockedUserData.self
        )
        XCTAssertTrue(blockedUserData.name == "Blocked Users", "Blocked Users")
        XCTAssertTrue(blockedUserData.seamonkeys.count == 0, "should be no blocks")
    }
}


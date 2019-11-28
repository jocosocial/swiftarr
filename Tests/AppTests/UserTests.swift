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
    
    /// Ensure that `UserAccessLevel` values are ordered and comparable by `.rawValue`.
    func testUserAccessLevelsAreOrdered() throws {
        let unverified: UserAccessLevel = .unverified
        let banned: UserAccessLevel = .banned
        let quarantined: UserAccessLevel = .quarantined
        let verified: UserAccessLevel = .verified
        let client: UserAccessLevel = .client
        let moderator: UserAccessLevel = .moderator
        let tho: UserAccessLevel = .tho
        let admin: UserAccessLevel = .admin
        
        XCTAssert(unverified.rawValue < banned.rawValue)
        XCTAssert(banned.rawValue < quarantined.rawValue)
        XCTAssert(quarantined.rawValue < verified.rawValue)
        XCTAssert(verified.rawValue < client.rawValue)
        XCTAssert(client.rawValue < moderator.rawValue)
        XCTAssert(moderator.rawValue < tho.rawValue)
        XCTAssert(tho.rawValue < admin.rawValue)
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
    func testUserCreate() throws {
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
        XCTAssertTrue(users[0].username == "admin", "'admin' should be first user")
        XCTAssertTrue(users[users.count - 3].username == user.username, "should be `\(testUsername)`")
        XCTAssertNotNil(UUID(uuidString: users[users.count - 2].username), "should be a valid UUID")
        XCTAssertTrue(users[users.count - 1].username == result.username, "last user should be '\(apiUsername)'")
        
        // check profile creations
        let profiles = try app.getResult(
            from: testURI + "/getprofiles",
            method: .GET,
            decodeTo: [UserProfile].self
        )
        XCTAssertTrue(profiles.count == users.count, "should be \(users.count)")
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
        var userRecoveryData = UserRecoveryData(username: testUsername, recoveryKey: createdUserData.recoveryKey)
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
        
        // test token is reused
        let token = try app.getResult(
            from: authURI + "login",
            method: .POST,
            headers: headers,
            decodeTo: TokenStringData.self
        )
        XCTAssertTrue(token.token == result.token, "should be \(result.token)")

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
    
    /// `POST /api/v3/user/password`
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
        var response = try app.getResponse(
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
        
        // test .client fails
        token = try app.login(username: "client", password: testPassword, on: conn)
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "password",
            method: .POST,
            headers: headers,
            body: userPasswordData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("would break"), "would break")
    }
    
    /// `GET /api/v3/user/whoami`
    func testUserWhoami() throws {
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()

        // test basic whoami
        headers.basicAuthorization = BasicAuthorization(username: testUsername, password: testPassword)
        var currentUserData = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: headers,
            decodeTo: CurrentUserData.self
        )
        XCTAssertTrue(currentUserData.username == testUsername, "should be \(testUsername)")
        XCTAssertFalse(currentUserData.isLoggedIn, "should not be logged in")
        
        // test bearer whoami
        let token = try app.login(username: testUsername, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        currentUserData = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: headers,
            decodeTo: CurrentUserData.self
        )
        XCTAssertTrue(currentUserData.username == testUsername, "should be \(testUsername)")
        XCTAssertTrue(currentUserData.isLoggedIn, "should be logged in")
    }
    
    /// `POST /api/v3/user/username`
    func testUserUsername() throws {
        // create logged in user
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: user.username, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test username change and .separators charset
        let newUsername = "new+us_er.na-me"
        var userUsernameData = UserUsernameData(username: newUsername)
        var response = try app.getResponse(
            from: userURI + "username",
            method: .POST,
            headers: headers,
            body: userUsernameData
        )
        var whoami = try app.getResult(
            from: userURI + "whoami",
            headers: headers,
            decodeTo: CurrentUserData.self
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        XCTAssertTrue(whoami.username == newUsername, "should be \(newUsername)")
        
        // test bad username
        userUsernameData.username = "_underscored"
        response = try app.getResponse(
            from: userURI + "username",
            method: .POST,
            headers: headers,
            body: userUsernameData
        )
        XCTAssertTrue(response.http.status.code == 400 , "should be 400 Bad Request")
        XCTAssertTrue(response.http.body.description.contains("must start with"), "must start with")

        // test unavailable username
        userUsernameData.username = "verified"
        response = try app.getResponse(
            from: userURI + "username",
            method: .POST,
            headers: headers,
            body: userUsernameData
        )
        whoami = try app.getResult(
            from: userURI + "whoami",
            headers: headers,
            decodeTo: CurrentUserData.self
        )
        XCTAssertTrue(response.http.status.code == 409 , "should be 409 Conflict")
        XCTAssertTrue(response.http.body.description.contains("not available"), "not available")
        XCTAssertTrue(whoami.username == newUsername, "should still be \(newUsername)")
        
        // test .client fails
        token = try app.login(username: "client", password: testPassword, on: conn)
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "username",
            method: .POST,
            headers: headers,
            body: userUsernameData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("would break"), "would break")
    }
    
    /// `POST /api/v3/user/add`
    func testUserAdd() throws {
        // create fresh verified user, will need recoveryKey later
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.basicAuthorization = BasicAuthorization(username: testUsername, password: testPassword)
        let userVerifyData = UserVerifyData(verification: testVerification)
        _ = try app.getResponse(
            from: userURI + "verify",
            method: .POST,
            headers: headers,
            body: userVerifyData
        )
        var token = try app.login(username: testUsername, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)

        // need an admin too
        let adminToken = try app.login(username: "admin", on: conn)
        var adminHeaders = HTTPHeaders()
        adminHeaders.bearerAuthorization = BearerAuthorization(token: adminToken.token)
        
        // test add subaccount
        var userAddData = UserAddData(username: "subaccount", password: testPassword)
        let addedUserData = try app.getResult(
            from: userURI + "add",
            method: .POST,
            headers: headers,
            body: userAddData,
            decodeTo: AddedUserData.self
        )
        let addedUser = try app.getResult(
            from: adminURI + "users/\(addedUserData.userID)",
            method: .GET,
            headers: adminHeaders,
            decodeTo: User.self
        )
        XCTAssertTrue(addedUser.parentID == user.userID, "parent should be user")
        
        // test recovery works
        let userRecoveryData = UserRecoveryData(
            username: addedUserData.username,
            recoveryKey: user.recoveryKey
        )
        let result = try app.getResult(
            from: authURI + "recovery",
            method: .POST,
            body: userRecoveryData,
            decodeTo: TokenStringData.self
        )
        XCTAssertFalse(result.token.isEmpty, "should receive valid token string")

        // test unavailable username
        userAddData.username = "verified"
        var response = try app.getResponse(
            from: userURI + "add",
            method: .POST,
            headers: headers,
            body: userAddData
        )
        XCTAssertTrue(response.http.status.code == 409, "should be 409 Conflict")
        XCTAssertTrue(response.http.body.description.contains("not available"), "not available")
        
        // test accessLevel
        token = try app.login(username: "quarantined", on: conn)
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "add",
            method: .POST,
            headers: headers,
            body: userAddData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("not currently"), "not currently")
    }
    
    /// `GET /api/v3/user/profile`
    /// `POST /api/v3/user/profile`
    /// `GET /api/v3/users/ID/profile`
    func testUserProfile() throws {
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var credentials = BasicAuthorization(username: testUsername, password: testPassword)
        var headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        
        // test convertToEdit
        var profileEdit = try app.getResult(
            from: userURI + "profile",
            method: .GET,
            headers: headers,
            decodeTo: UserProfile.Edit.self
        )
        XCTAssertTrue(profileEdit.username == testUsername, "should be \(testUsername)")
        XCTAssertTrue(profileEdit.displayName.isEmpty, "should be empty")
        
        // test post edit
        let userProfileData = UserProfileData(
            about: "I'm a test user.",
            displayName: "Alistair Cookie",
            email: "grundoon@gmail.com",
            homeLocation: "Boat",
            message: "Tonight on Monsterpiece Theatre...",
            preferredPronoun: "Sir",
            realName: "Cookie Monster",
            roomNumber: "11001",
            limitAccess: true
        )
        profileEdit = try app.getResult(
            from: userURI + "profile",
            method: .POST,
            headers: headers,
            body: userProfileData,
            decodeTo: UserProfile.Edit.self
        )
        XCTAssertTrue(profileEdit.realName.contains("Cookie"), "should have .realName")
        XCTAssertTrue(profileEdit.displayedName == "Alistair Cookie (@\(testUsername))", "should be")
        
        // test limitAccess
        var result = try app.getResult(
            from: usersURI + "\(user.userID)/profile",
            method: .GET,
            headers: headers,
            decodeTo: UserProfile.Public.self
        )
        XCTAssertTrue(result.message.contains("must be logged in"), "must be logged in")

        let token = try app.login(username: testUsername, password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        result = try app.getResult(
            from: usersURI + "\(user.userID)/profile",
            method: .GET,
            headers: headers,
            decodeTo: UserProfile.Public.self
        )
        XCTAssertTrue(result.message.contains("Tonight on"), "Tonight on")
        
        // test username change
        let userUsernameData = UserUsernameData(username: "cookie")
        _ = try app.getResponse(
            from: userURI + "username",
            method: .POST,
            headers: headers,
            body: userUsernameData
        )
        profileEdit = try app.getResult(
            from: userURI + "profile",
            method: .GET,
            headers: headers,
            decodeTo: UserProfile.Edit.self
        )
        XCTAssertTrue(profileEdit.displayedName.contains("(@cookie)"), "should be decorated cookie")
        XCTAssertTrue(profileEdit.preferredPronoun == "Sir", "should be there")
        
        // test retrieve banned
        let bannedUser = try app.getResult(
            from: usersURI + "find/banned",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        var response = try app.getResponse(
            from: usersURI + "\(bannedUser.userID)/profile",
            method: .GET,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
        XCTAssertTrue(response.http.body.description.contains("not available"), "not available")
        
        // test banned user
        credentials = BasicAuthorization(username: "banned", password: testPassword)
        headers = HTTPHeaders()
        headers.basicAuthorization = credentials
        response = try app.getResponse(
            from: userURI + "profile",
            method: .POST,
            headers: headers,
            body: userProfileData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("cannot be edited"), "cannot be edited")
    }
    
    /// `POST /api/v3/users/ID/note`
    /// `GET /api/v3/users/ID/note`
    /// `GET /api/v3/user/notes`
    /// `POST /api/v3/user/note`
    /// `POST /api/v3/users/ID/note/delete`
    func testUserNotes() throws {
        // create logged in user
        _ = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)

        // get some users
        let unverifiedUser = try app.getResult(
            from: usersURI + "find/unverified",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )
        let verifiedUser = try app.getResult(
            from: usersURI + "find/verified",
            method: .GET,
            headers: headers,
            decodeTo: UserInfo.self
        )

        // test create note
        let note1 = NoteCreateData(note: "had dinner with unverified last night")
        let note2 = NoteCreateData(note: "great scrabble player")
        let createdNoteData1 = try app.getResult(
            from: usersURI + "\(unverifiedUser.userID)/note",
            method: .POST,
            headers: headers,
            body: note1,
            decodeTo: CreatedNoteData.self
        )
        let createdNoteData2 = try app.getResult(
            from: usersURI + "\(verifiedUser.userID)/note",
            method: .POST,
            headers: headers,
            body: note2,
            decodeTo: CreatedNoteData.self
        )
        XCTAssertTrue(createdNoteData1.note == note1.note, "should be the same text")
        
        // test note exists
        var response = try app.getResponse(
            from: usersURI + "\(verifiedUser.userID)/note",
            method: .POST,
            headers: headers,
            body: note2
        )
        XCTAssertTrue(response.http.status.code == 409, "should be 409 Conflict")
        XCTAssertTrue(response.http.body.description.contains("already exists"), "already exists")
        
        // test retrieve note
        let noteEdit = try app.getResult(
            from: usersURI + "\(unverifiedUser.userID)/note",
            method: .GET,
            headers: headers,
            decodeTo: UserNote.Edit.self
        )
        XCTAssertTrue(noteEdit.noteID == createdNoteData1.noteID, "should be same ID")
        
        // test note appears on profile
        let profile = try app.getResult(
            from: usersURI + "\(unverifiedUser.userID)/profile",
            method: .GET,
            headers: headers,
            decodeTo: UserProfile.Public.self
        )
        XCTAssertTrue(profile.note == note1.note, "should have \(note1.note) value")
        
        // test retrieve notes
        var notes = try app.getResult(
            from: userURI + "notes",
            method: .GET,
            headers: headers,
            decodeTo: [NoteData].self
        )
        XCTAssertTrue(notes.count == 2, "should be 2 notes")
        XCTAssertTrue(notes.first?.noteID != notes.last?.noteID, "should be different notes")
        
        // test update note
        let noteUpdateData = NoteUpdateData(noteID: createdNoteData2.noteID, note: "")
        let noteData = try app.getResult(
             from: userURI + "note",
             method: .POST,
             headers: headers,
             body: noteUpdateData,
             decodeTo: NoteData.self
         )
        XCTAssertTrue(noteData.note.isEmpty, "should be emptry string")
                
        // test delete note
        response = try app.getResponse(
            from: usersURI + "\(unverifiedUser.userID)/note/delete",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
        notes = try app.getResult(
            from: userURI + "notes",
            method: .GET,
            headers: headers,
            decodeTo: [NoteData].self
        )
        XCTAssertTrue(notes.count == 1, "should be 1 note")
        XCTAssertTrue(notes.first?.noteID == createdNoteData2.noteID, "should be same IDs")
        
        // test bad note owner
        token = try app.login(username: "admin", password: testPassword, on: conn)
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        response = try app.getResponse(
            from: userURI + "note",
            method: .POST,
            headers: headers,
            body: noteUpdateData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
        XCTAssertTrue(response.http.body.description.contains("does not belong"), "does not belong")
    }
}

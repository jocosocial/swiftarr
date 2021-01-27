@testable import App
import Vapor
import XCTest


final class EventTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let testVerification = "ABC ABC"
    let adminURI = "/api/v3/admin/"
    let authURI = "/api/v3/auth/"
    let eventsURI = "/api/v3/events/"
    let forumURI = "/api/v3/forum/"
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
    
    /// Ensure that `Events` migration was successful.
    func testEventsMigration() throws {
        let events = try app.getResult(
            from: eventsURI,
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertFalse(events.isEmpty, "should be events")
        XCTAssertTrue(events.count > 100, "should be lots")
    }
    
    /// `GET /api/v3/events`
    /// `GET /api/v3/events/official`
    /// `GET /api/v3/events/shadow`
    func testEventsAll() throws {
        // test open access
        var events = try app.getResult(
            from: eventsURI,
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        var eventsCount = events.count
        events = try app.getResult(
            from: eventsURI + "official",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        var officialCount = events.count
        XCTAssertTrue(officialCount < eventsCount, "should be a subset")
        events = try app.getResult(
            from: eventsURI + "shadow",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        var shadowCount = events.count
        XCTAssertTrue(shadowCount < eventsCount, "should be a subset")
        XCTAssertTrue(shadowCount + officialCount == eventsCount, "should be \(eventsCount)")
        
        // test logged in
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        events = try app.getResult(
            from: eventsURI,
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        eventsCount = events.count
        events = try app.getResult(
            from: eventsURI + "official",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        officialCount = events.count
        XCTAssertTrue(officialCount < eventsCount, "should be a subset")
        events = try app.getResult(
            from: eventsURI + "shadow",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        shadowCount = events.count
        XCTAssertTrue(shadowCount < eventsCount, "should be a subset")
        XCTAssertTrue(shadowCount + officialCount == eventsCount, "should be \(eventsCount)")
    }
    
    /// `GET /api/v3/events/today`
    /// `GET /api/v3/events/official/today`
    /// `GET /api/v3/events/shadow/today`
    func testEventsToday() throws {
        // get baselines
        var events = try app.getResult(
            from: eventsURI + "today",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        let eventsCount = events.count
        events = try app.getResult(
            from: eventsURI + "official/today",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        let officialCount = events.count
        events = try app.getResult(
            from: eventsURI + "shadow/today",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        let shadowCount = events.count
        
        // create today events
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let eventStart = Date.init(timeInterval: 3600, since: todayStart)
        let eventEnd = Date.init(timeInterval: 7200, since: eventStart)
        var eventData = try app.createEvent(
            startTime: eventStart,
            endTime: eventEnd,
            title: "Test Event",
            description: "A testaculous test.",
            location: "13th Floor",
            eventType: .shadow,
            uid: "asdf",
            on: conn
        )
        XCTAssertTrue(eventData.title == "Test Event", "should be 'Test Event'")
        eventData = try app.createEvent(
            startTime: eventStart,
            endTime: eventEnd,
            title: "Pool Event",
            description: "A moister test.",
            location: "Seaview Deck",
            eventType: .general,
            uid: "qwerty",
            on: conn
        )
        XCTAssertTrue(eventData.title == "Pool Event", "should be 'Pool Event'")
        
        // test open access
        events = try app.getResult(
            from: eventsURI + "today",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 2, "should be \(eventsCount + 2)")
        events = try app.getResult(
            from: eventsURI + "official/today",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == officialCount + 1, "should be \(officialCount + 1)")
        events = try app.getResult(
            from: eventsURI + "shadow/today",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == shadowCount + 1, "should be \(shadowCount + 1)")
        
        // test logged in
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        events = try app.getResult(
            from: eventsURI + "today",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 2, "should be \(eventsCount + 2)")
        events = try app.getResult(
            from: eventsURI + "official/today",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == officialCount + 1, "should be \(officialCount + 1)")
        events = try app.getResult(
            from: eventsURI + "shadow/today",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == shadowCount + 1, "should be \(shadowCount + 1)")
    }
    
    /// `GET /api/v3/events/now`
    /// `GET /api/v3/events/official/now`
    /// `GET /api/v3/events/shadow/now`
    func testEventsNow() throws {
        // get baselines
        var events = try app.getResult(
            from: eventsURI + "now",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        let eventsCount = events.count
        events = try app.getResult(
            from: eventsURI + "official/now",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        let officialCount = events.count
        events = try app.getResult(
            from: eventsURI + "shadow/now",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        let shadowCount = events.count
        
        // create today + now events
        // FIXME: this seems a terrible test, depends entirely on time of day it's run
        var eventData = try app.createEvent(
            startTime: Date.init(timeInterval: 600, since: Date()),
            endTime: Date.init(timeInterval: 3600, since: Date()),
            title: "Test Event",
            description: "A testaculous test.",
            location: "13th Floor",
            eventType: .shadow,
            uid: "asdf",
            on: conn
        )
        XCTAssertTrue(eventData.title == "Test Event", "should be 'Test Event'")
        eventData = try app.createEvent(
            startTime: Date.init(timeInterval: -3600, since: Date()),
            endTime: Date.init(timeInterval: 3600, since: Date()),
            title: "Pool Event",
            description: "A moister test.",
            location: "Seaview Deck",
            eventType: .general,
            uid: "qwerty",
            on: conn
        )
        XCTAssertTrue(eventData.title == "Pool Event", "should be 'Pool Event'")
        eventData = try app.createEvent(
            startTime: Date(),
            endTime: Date.init(timeInterval: 3600, since: Date()),
            title: "Not Pool Event",
            description: "A fireside test. Wait, _fire_?",
            location: "Library",
            eventType: .shadow,
            uid: "zxcv",
            on: conn
        )
        XCTAssertTrue(eventData.title == "Not Pool Event", "should be 'Not Pool Event'")

        // test open access
        events = try app.getResult(
            from: eventsURI + "today",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 3, "should be \(eventsCount + 3)")
        events = try app.getResult(
            from: eventsURI + "now",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 2, "should be \(eventsCount + 2)")
        events = try app.getResult(
            from: eventsURI + "official/now",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == officialCount + 1, "should be \(officialCount + 1)")
        events = try app.getResult(
            from: eventsURI + "shadow/now",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == shadowCount + 1, "should be \(shadowCount + 1)")
        
        // test logged in
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        events = try app.getResult(
            from: eventsURI + "today",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 3, "should be \(eventsCount + 3)")
        events = try app.getResult(
            from: eventsURI + "now",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 2, "should be \(eventsCount + 2)")
        events = try app.getResult(
            from: eventsURI + "official/now",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == officialCount + 1, "should be \(officialCount + 1)")
        events = try app.getResult(
            from: eventsURI + "shadow/now",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == shadowCount + 1, "should be \(shadowCount + 1)")
    }
    
    /// `GET /api/v3/events/match/STRING`
    func testEventsMatch() throws {
        // get baseline
        var events = try app.getResult(
            from: eventsURI + "match/test",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        let eventsCount = events.count

        // create events
        _ = try app.createEvent(
            startTime: Date.init(timeInterval: -7200, since: Date()),
            endTime: Date.init(timeInterval: -3600, since: Date()),
            title: "Test Event",
            description: "Does not contain the matchy word.",
            location: "13th Floor",
            eventType: .shadow,
            uid: "asdf",
            on: conn
        )
        _ = try app.createEvent(
            startTime: Date.init(timeInterval: -3600, since: Date()),
            endTime: Date.init(timeInterval: 3600, since: Date()),
            title: "Pool Event",
            description: "A moister test.",
            location: "Seaview Deck",
            eventType: .general,
            uid: "qwerty",
            on: conn
        )
        
        // test open access
        events = try app.getResult(
            from: eventsURI + "match/test",
            method: .GET,
            headers: HTTPHeaders(),
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 2, "should be \(eventsCount + 2)")
        
        // test logged in
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        events = try app.getResult(
            from: eventsURI + "match/test",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == eventsCount + 2, "should be \(eventsCount + 2)")
    }
    
    /// `POST /api/v3/events/update`
    func testEventsUpdate() throws {
        // create logged in admin
        var token = try app.login(username: "admin", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test upload
        let scheduleFile = "test-updated-schedule.ics"
        let directoryConfig = DirectoryConfiguration.detect()
        let schedulePath = directoryConfig.workingDirectory.appending("seeds/").appending(scheduleFile)
        guard let data = FileManager.default.contents(atPath: schedulePath),
            let dataString = String(bytes: data, encoding: .utf8) else {
                XCTFail("Could not read schedule file.")
                return
        }
        let eventsUpdateData = EventsUpdateData(schedule: dataString)
        let events = try app.getResult(
            from: eventsURI + "update",
            method: .POST,
            headers: headers,
            body: eventsUpdateData,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count == 3, "should be 2 updated events, 1 new")
        
        // test not admin
        token = try app.login(username: "verified", password: testPassword, on: conn)
        headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        let response = try app.getResponse(
            from: eventsURI + "update",
            method: .POST,
            headers: headers,
            body: eventsUpdateData
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")
    }
    
    /// `GET /api/v3/events/ID/forum`
    func testEventForums() throws {
        // test with Basic access
        var headers = HTTPHeaders()
        let credentials = BasicAuthorization(username: "unverified", password: testPassword)
        headers.basicAuthorization = credentials
        
        let events = try app.getResult(
            from: eventsURI,
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(events.count > 0, "should have events")
    
        let adminCategories = try app.getResult(
            from: forumURI + "categories/admin",
            method: .GET,
            headers: headers,
            decodeTo: [CategoryData].self
        )
        XCTAssertTrue(adminCategories.count == 3, "should be 3 categories")
        
        let officialForums = try app.getResult(
            from: forumURI + "categories/\(adminCategories[1].categoryID)",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(officialForums.count > 0, "should have official forums")
        
        let shadowForums = try app.getResult(
            from: forumURI + "categories/\(adminCategories[2].categoryID)",
            method: .GET,
            headers: headers,
            decodeTo: [ForumListData].self
        )
        XCTAssertTrue(shadowForums.count > 0, "should have shadow forums")
        XCTAssertEqual(officialForums.count + shadowForums.count, events.count, "should be \(events.count)")
    }
    
    /// `POST /api/v3/events/ID/favorite`
    /// `POST /api/v3/events/ID/favorite/remove`
    /// `GET /api/v3/events/favorites`
    func testEventsBarrel() throws {
        // create verified logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // get events
        var officialEvents = try app.getResult(
            from: eventsURI + "official",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        var shadowEvents = try app.getResult(
            from: eventsURI + "shadow",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        
        // test favorite
        var response = try app.getResponse(
            from: eventsURI + "\(officialEvents[0].eventID)/favorite",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        response = try app.getResponse(
            from: eventsURI + "\(shadowEvents[0].eventID)/favorite",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        officialEvents = try app.getResult(
            from: eventsURI + "official",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(officialEvents[0].isFavorite, "should be favorited")
        shadowEvents = try app.getResult(
            from: eventsURI + "shadow",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(shadowEvents[0].isFavorite, "should be favorited")
        var favoriteEvents = try app.getResult(
            from: eventsURI + "favorites",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(favoriteEvents.count == 2, "should be 2 events")
        
        // test remove favorite
        response = try app.getResponse(
            from: eventsURI + "\(shadowEvents[0].eventID)/favorite/remove",
            method: .POST,
            headers: headers
        )
        XCTAssertTrue(response.http.status.code == 204, "should be 204 No Content")
        favoriteEvents = try app.getResult(
            from: eventsURI + "favorites",
            method: .GET,
            headers: headers,
            decodeTo: [EventData].self
        )
        XCTAssertTrue(favoriteEvents.count == 1, "should be 1 event")
    }
}

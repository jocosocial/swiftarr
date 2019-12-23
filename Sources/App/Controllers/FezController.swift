import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of /api/v3/fez/* route endpoints and handler functions related
/// to FriendlyFez/LFG barrels.

struct FezController: RouteCollection {
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/fez endpoints
        let fezRoutes = router.grouped("api", "v3", "fez")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let sharedAuthGroup = fezRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = fezRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // endpoints available whether logged in or not
        sharedAuthGroup.get("types", use: typesHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.post(FezCreateData.self, at: "create", use: createHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `/GET /api/v3/fez/types`
    ///
    /// Retrieve a list of all values for `FezType` as strings.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[String]` containing the `.label` value for each type.
    func typesHandler(_ req: Request) throws -> Future<[String]> {
        return req.future(FezType.AllCases.init().map { $0.label })
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/fez/create`
    ///
    /// Create a `Barrel` of `BarrelType` `.friendlyFez`. The creating user is automatically
    /// added to the participant list.
    ///
    /// The list of recognized values for use in the `.fezType` field is obtained from
    /// `GET /api/v3/fez/types`.
    ///
    /// The `.startTime` and `.endTime` fields should be passed as string representations of a
    /// date. The representation must be either a string literal of seconds since epoch (e.g.
    /// "1574364635") or an ISO8601 string. To create an open-ended / unknown `.startTime` or
    /// `.endTime` for the FriendlyFez, pass an *empty* string `""` as the value. This will be
    /// converted to "TBD" for display.
    ///
    /// - Important: Do **not** pass "0" as the date value. Unless you really are scheduling
    ///   something for the first stroke of midnight in 1970.
    ///
    /// A value of 0 in either the `.minCapacity` or `.maxCapacity` fields indicates an undefined
    /// limit: "there is no minimum", "there is no maximum".
    ///
    /// - Requires: `FezCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `FezCreateData` containing the fez data.
    /// - Throws: 400 error if the supplied data does not validate.
    /// - Returns: `FezData` containing the newly created fez.
    func createHandler(_ req: Request, data: FezCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // see `FezCreateData.validations()`
        try data.validate()
        // create barrel
        let barrel = try Barrel(
            ownerID: user.requireID(),
            barrelType: .friendlyFez,
            name: data.title,
            modelUUIDs: [user.requireID()],
            userInfo: [
                "label": [data.fezType],
                "info": [data.info],
                "startTime": [data.startTime],
                "endTime": [data.endTime],
                "location": [data.location],
                "minCapacity": [String(data.minCapacity)],
                "maxCapacity": [String(data.maxCapacity)],
                "waitList": []
            ]
        )
        return barrel.save(on: req).map {
            (savedBarrel) in
            // return as FezData
            let fezData = try FezData(
                fezType: data.fezType,
                title: data.title,
                info: data.info,
                startTime: self.fezTimeString(from: data.startTime),
                endTime: self.fezTimeString(from: data.endTime),
                location: data.location,
                seamonkeys: [user.convertToSeaMonkey()],
                waitingList: []
            )
            // with 201 status
            let response = Response(http: HTTPResponse(status: .created), using: req)
            try response.content.encode(fezData)
            return response
        }
    }
}

// MARK: - Helper Functions

extension FezController {
    /// Returns a display string representation of a date stored as a string in either ISO8601
    /// format or as a literal Double.
    ///
    /// - Parameter string: The string representation of the date.
    /// - Returns: String in date format "E, H:mm a", or "TBD" if the string value is "0" or
    ///   the date string is invalid.
    func fezTimeString(from string: String) -> String {
        let dateFormtter = DateFormatter()
        dateFormtter.dateFormat = "E, h:mm a"
        dateFormtter.timeZone = TimeZone(secondsFromGMT: 0)
        switch string {
            case "0":
                return "TBD"
            default:
                if let date = FezController.dateFromParameter(string: string) {
                    return dateFormtter.string(from: date)
                } else {
                    return "TBD"
            }
        }
    }
}

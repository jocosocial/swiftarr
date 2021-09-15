import Vapor
import Crypto
import FluentSQL

/// The collection of `/api/v3/admin` route endpoints and handler functions related to admin tasks.
///
/// All routes in this group should be restricted to users with administrator priviliges. This controller returns data of 
/// a privledged nature, and has control endpoints for setting overall server state.
struct AdminController: APIRouteCollection {
    
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/admin endpoints
		let modRoutes = app.grouped("api", "v3", "admin")
		
		// instantiate authentication middleware
		let requireAdminMiddleware = RequireAdminMiddleware()
						 
		// endpoints available for Admins only
		let adminAuthGroup = addTokenAuthGroup(to: modRoutes).grouped([requireAdminMiddleware])
		adminAuthGroup.post("dailytheme", "create", use: addDailyThemeHandler)
		adminAuthGroup.post("dailytheme", dailyThemeIDParam, "edit", use: editDailyThemeHandler)
		adminAuthGroup.post("dailytheme", dailyThemeIDParam, "delete", use: deleteDailyThemeHandler)
		adminAuthGroup.delete("dailytheme", dailyThemeIDParam, use: deleteDailyThemeHandler)
		
		adminAuthGroup.get("serversettings", use: settingsHandler)
		adminAuthGroup.post("serversettings", "update", use: settingsUpdateHandler)
	}

    /// `POST /api/v3/admin/dailytheme/create`
    ///
    /// Creates a new daily theme for a day of the cruise (or some other day). The 'day' field is unique, so attempts to create a new record
	/// with the same day as an existing record will fail--instead, you probably want to edit the existing DailyTheme for that day. 
	/// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 201 Created` if the theme was added successfully.
	func addDailyThemeHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot add daily themes")
 		let data = try ValidatingJSONDecoder().decode(DailyThemeUploadData.self, fromBodyOf: req)
 		let imageArray = data.image != nil ? [data.image!] : []
        // process images
        return self.processImages(imageArray, usage: .dailyTheme, on: req).throwingFlatMap { filenames in
        	let filename = filenames.isEmpty ? nil : filenames[0]
			let dailyTheme = DailyTheme(title: data.title, info: data.info, image: filename, day: data.cruiseDay)		
			return dailyTheme.save(on: req.db).transform(to: .created)
		}
	}
	
    /// `POST /api/v3/admin/dailytheme/ID/edit`
    ///
    /// Edits an existing daily theme. Passing nil for the image will remove an existing image. Although you can change the cruise day for a DailyTheme,
	/// you can't set the day to equal a day that already has a theme record. This means it'll take extra steps if you want to swap days for 2 themes.
	/// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 201 Created` if the theme was added successfully.
	func editDailyThemeHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot add daily themes")
 		let data = try ValidatingJSONDecoder().decode(DailyThemeUploadData.self, fromBodyOf: req)
 		let imageArray = data.image != nil ? [data.image!] : []
		return DailyTheme.query(on: req.db).filter(\.$cruiseDay == data.cruiseDay).first()
				.unwrap(or: Abort(.notFound, reason: "No theme found for given cruise day")).throwingFlatMap { dailyTheme in
			// process images
			return self.processImages(imageArray, usage: .dailyTheme, on: req).throwingFlatMap { filenames in
        		let filename = filenames.isEmpty ? nil : filenames[0]
				dailyTheme.title = data.title
				dailyTheme.info = data.info
				dailyTheme.image = filename
				dailyTheme.cruiseDay = data.cruiseDay
				return dailyTheme.save(on: req.db).transform(to: .created)
			}
		}
	}
	
    /// `POST /api/v3/admin/dailytheme/ID/delete`
    /// `DELETE /api/v3/admin/dailytheme/ID/`
    ///
    ///  Deletes a daily theme.
	/// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 201 Created` if the theme was added successfully.
	func deleteDailyThemeHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot delete daily themes")
		return DailyTheme.findFromParameter(dailyThemeIDParam, on: req).flatMap { theme in
			return theme.delete(on: req.db).transform(to: .noContent)
		}
	}
	
    /// `GET /api/v3/admin/serversettings`
    ///
    ///  Returns the current state of the server's Settings structure.
	/// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `SettingsAdminData`
	func settingsHandler(_ req: Request) throws -> SettingsAdminData {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.admin) else {
			throw Abort(.forbidden, reason: "Admin only")
		}
		return SettingsAdminData(Settings.shared)
	}
	
    /// `POST /api/v3/admin/serversettings/update`
    ///
    ///  Updates a bunch of settings in the Settings.shared object.
	/// 
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `HTTP 201 Created` if the theme was added successfully.
	func settingsUpdateHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		guard user.accessLevel.hasAccess(.admin) else {
			throw Abort(.forbidden, reason: "Admin only")
		}
 		let data = try ValidatingJSONDecoder().decode(SettingsUpdateData.self, fromBodyOf: req)
 		if let value = data.maximumTwarrts {
 			Settings.shared.maximumTwarrts = value
 		}
 		if let value = data.maximumForums {
 			Settings.shared.maximumForums = value
 		}
 		if let value = data.maximumForumPosts {
 			Settings.shared.maximumForumPosts = value
 		}
 		if let value = data.maxImageSize {
 			Settings.shared.maxImageSize = value
 		}
 		if let value = data.forumAutoQuarantineThreshold {
 			Settings.shared.forumAutoQuarantineThreshold = value
 		}
 		if let value = data.postAutoQuarantineThreshold {
 			Settings.shared.postAutoQuarantineThreshold = value
 		}
 		if let value = data.userAutoQuarantineThreshold {
 			Settings.shared.userAutoQuarantineThreshold = value
 		}
 		if let value = data.allowAnimatedImages {
 			Settings.shared.allowAnimatedImages = value
 		}
 		var localDisables = Settings.shared.disabledFeatures.value
 		for pair in data.enableFeatures {
 			if let app = SwiftarrClientApp(rawValue: pair.app), let feature = SwiftarrFeature(rawValue: pair.feature) {
				localDisables[app]?.remove(feature)
				if let featureSet = localDisables[app], featureSet.isEmpty {
					localDisables.removeValue(forKey: app)
				}
			}
 		}
 		for pair in data.disableFeatures {
 			if let app = SwiftarrClientApp(rawValue: pair.app), let feature = SwiftarrFeature(rawValue: pair.feature) {
 				if localDisables[app] == nil {
					localDisables[app] = Set(arrayLiteral: feature)
 				}
 				else {
					localDisables[app]?.insert(feature)
				}
			}
 		}
 		Settings.shared.disabledFeatures = DisabledFeaturesGroup(value: localDisables)
		return try Settings.shared.storeSettings(on: req).transform(to: HTTPStatus.ok)
	}
}


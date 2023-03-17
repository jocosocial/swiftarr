import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/user/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct UserController: APIRouteCollection {

	// MARK: Properties
		
	/// An array of words used to generate random phrases.
	static let words: [String] = [
		"aboriginal", "accept", "account", "acoustic", "adaptable", "adorable",
		"afternoon", "agreeable", "airport", "alive", "alluring", "amazing",
		"amused", "announce", "applause", "appreciate", "approve", "aquatic",
		"arithmetic", "aromatic", "arrive", "aspiring", "attractive", "aunt",
		"auspicious", "awake", "balance", "basin", "bat", "bath", "bed", "bee",
		"befitting", "believe", "beneficial", "best", "bikes", "birds", "black",
		"blue", "blush", "boat", "book", "bottle", "bouncy", "brains", "brass",
		"brave", "bravo", "breezy", "brown", "brunch", "bubble", "business",
		"cabbage", "cactus", "cake", "calm", "camera", "capable", "card",
		"caring", "cats", "cause", "celery", "cheerful", "cheese", "cherry",
		"chess", "chicken", "circle", "clean", "clover", "club", "coach",
		"collect", "colorful", "comfortable", "complete", "connect",
		"conscious", "cooperative", "cows", "crayon", "cuddly", "cute", "daily",
		"dance", "dapper", "dashing", "dazzling", "debonair", "decisive",
		"delicate", "delicious", "delight", "delightful", "design", "dinner",
		"dinosaurs", "discovery", "dock", "doggo", "donkey", "drawer", "dress",
		"drink", "drum", "dry", "duck", "dynamic", "earth", "eggs", "eight",
		"elated", "elegant", "enchanted", "enchanting", "encourage", "enjoy",
		"enormous", "entertain", "enthusiastic", "equal", "escape", "excellent",
		"excite", "exciting", "exist", "expect", "expert", "exuberant", "fairy",
		"familiar", "fancy", "fantastic", "farm", "fascinating", "feeling",
		"fez", "first", "five", "fixed", "float", "flood", "flower", "fluffy",
		"food", "fork", "frequent", "friend", "friendly", "frog", "fruit",
		"future", "futuristic", "garrulous", "geese", "ghost", "giants",
		"gifted", "gigantic", "giraffe", "glib", "glorious", "gorgeous",
		"grape", "grass", "grateful", "gratuity", "gray", "green", "grin",
		"groovy", "guide", "guitar", "hair", "haircut", "hand", "handsomely",
		"happy", "harbor", "harmonious", "hat", "heal", "heat", "heavenly",
		"hilarious", "hobbies", "honey", "horse", "hospitable", "hottub", "hug",
		"humor", "humorous", "hungry", "illustrious", "impartial", "imported",
		"improve", "impulse", "incredible", "inform", "instruct", "instrument",
		"interesting", "internal", "introduce", "invincible", "island", "jazzy",
		"jellyfish", "joke", "jolly", "joyous", "kind", "kindhearted", "kiss",
		"kitteh", "knit", "knowledge", "ladybug", "lamp", "language", "laugh",
		"learn", "lettuce", "library", "light", "like", "liquid", "listen",
		"lively", "lizard", "love", "love", "loving", "lunch", "magenta",
		"magical", "magnificent", "mailbox", "majestic", "marvelous", "melodic",
		"milk", "mint", "mitten", "morning", "moustache", "mouth",
		"mysterious", "neighborly", "nest", "nifty", "oatmeal", "obtainable",
		"ocean", "orange", "pancake", "panoramic", "pants", "partner", "party",
		"pastoral", "peaceful", "pencil", "perfect", "person", "pet", "pets",
		"pickle", "pie", "piquant", "pizza", "placid", "plants", "play",
		"playground", "pleasant", "pleasure", "port", "porter", "position",
		"possible", "potato", "precious", "print", "profuse", "public",
		"pupper", "purple", "puzzle", "quaint", "quartz", "queen", "quiet",
		"rabbit", "radiate", "rainstorm", "rainy", "reading", "real", "red",
		"reflective", "rejoice", "respect", "responsible", "rest", "rhyme",
		"ritzy", "robin", "romantic", "rose", "round", "route", "safe", "sail",
		"sand", "savory", "science", "scientific", "scintillating", "scrabble",
		"sea", "seal", "seashore", "serious", "share", "shiny", "ship",
		"silent", "silk", "silly", "sincere", "skillful", "sleep", "sleepy",
		"smile", "snail", "soak", "soft", "solid", "song", "songs", "soothe",
		"sophisticated", "soup", "sparkling", "special", "spectacular",
		"spiffy", "splendid", "spooky", "spoon", "square", "squeal", "squirrel",
		"starboard", "stimulating", "stitch", "story", "succeed", "sun",
		"superb", "supreme", "surprise", "swanky", "sweater", "sweet", "swim",
		"table", "talented", "tasty", "team", "teeth", "terrific", "thankful",
		"thirsty", "thoughtful", "three", "throne", "thumb", "tiara", "ticket",
		"tiger", "tomato", "toothbrush", "toothpaste", "trail", "train",
		"tranquil", "tree", "two", "ubiquitous", "umbrella", "underwear",
		"unite", "unpack", "upbeat", "vacation", "verdant", "verse",
		"victorious", "view", "violet", "volcano", "walk", "warm", "water",
		"weather", "week", "welcome", "whimsical", "whirl", "whispering",
		"white", "witty", "wolves", "wonder", "wonderful", "word", "writing",
		"yarn", "year", "yellow", "yummy", "zealous", "zebra", "zesty", "zippy",
		"zombie"
	]
		
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/user endpoints
		let userRoutes = app.grouped("api", "v3", "user")
		
		// open access endpoints
		userRoutes.post("create", use: createHandler)
		
		// endpoints available only when logged in
		let tokenAuthGroup = addTokenCacheAuthGroup(to: userRoutes)
		tokenAuthGroup.get("whoami", use: whoamiHandler)
		tokenAuthGroup.post("verify", use: verifyHandler)
		tokenAuthGroup.post("password", use: passwordHandler)
		tokenAuthGroup.post("username", use: usernameHandler)
		tokenAuthGroup.post(userIDParam, "username", use: usernameHandler)
		tokenAuthGroup.post("add", use: addHandler)
	   
		tokenAuthGroup.on(.POST, "image", body: .collect(maxSize: "30mb"), use: imageHandler)
		tokenAuthGroup.post("image", "remove", use: imageRemoveHandler)
		tokenAuthGroup.delete("image", use: imageRemoveHandler)
		tokenAuthGroup.delete(userIDParam, "image", use: imageRemoveHandler)
		
		tokenAuthGroup.get("profile", use: profileHandler)
		tokenAuthGroup.post("profile", use: profileUpdateHandler)
		tokenAuthGroup.post(userIDParam, "profile", use: profileUpdateHandler)
		
		tokenAuthGroup.get("alertwords", use: alertwordsHandler)
		tokenAuthGroup.post("alertwords", "add", alertwordParam, use: alertwordsAddHandler)
		tokenAuthGroup.post("alertwords", "remove", alertwordParam, use: alertwordsRemoveHandler)
	
		tokenAuthGroup.get("mutewords", use: mutewordsHandler)
		tokenAuthGroup.post("mutewords", "add", mutewordParam, use: mutewordsAddHandler)
		tokenAuthGroup.post("mutewords", "remove", mutewordParam, use: mutewordsRemoveHandler)

		tokenAuthGroup.get("notes", use: notesHandler)
	}
	
	// MARK: - Open Access Handlers
	
	/// `POST /api/v3/user/create`
	///
	/// Creates a new `User` account. Does not log the new user in. Route is open access.
	///
	/// A  `CreatedUserData` structure is returned on success, containing the new user's ID,
	/// username and a generated recovery key.
	///
	/// - Note: The `CreatedUserData.recoveryKey` is a random phrase used to recover an account
	///   in the case of a forgotten password. While it can be stored by a client, that
	///   essentially defeats its purpose (presumably the password would also already be
	///   stored). The *intended client use* is that it is displayed to the user upon successful
	///   creation, and the user is *encouraged to take a screenshot or write it down before
	///   proceeding*.
	///
	/// - Parameter requestBody: `UserCreateData`
	/// - Throws: 400 error if the username is an invalid format. 409 errpr if the username is
	///   not available.
	/// - Returns: `CreatedUserData` containing the newly created user's ID, username, and a
	///   recovery key string.
	func createHandler(_ req: Request) async throws -> Response {
		// see `UserCreateData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserCreateData.self, fromBodyOf: req)
		// check for existing username so we can return 409 Conflict status instead
		// of the default super-unfriendly 500 for unique constraint violation
		if let _ = try await User.query(on: req.db).filter(\.$username, .custom("ilike"), data.username).first() {
			throw Abort(.conflict, reason: "username '\(data.username)' is not available")
		}
		
		// Reg Codes may be delivered in user's emails as "ABC DEF", but the normalized form is lowercase, no spaces.
		// Note: We don't check the reg code against the table until we're inside the transaction
		guard let normalizedRegCode = data.verification?.lowercased().replacingOccurrences(of: " ", with: ""),
				normalizedRegCode.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil, normalizedRegCode.count == 6 else {
			throw Abort(.badRequest, reason: "Malformed verification code. Verification code must be 6 alphanumeric letters; spaces optional.")
		}
						
		// create user
		let recoveryKey = try UserController.generateRecoveryKey(on: req)
		let normalizedKey = recoveryKey.lowercased().replacingOccurrences(of: " ", with: "")
		let recoveryHash = try Bcrypt.hash(normalizedKey)
		let passwordHash = try req.password.hash(data.password)
		let user = User(username: data.username, password: passwordHash, recoveryKey: recoveryHash,
				verification: nil, parent: nil, accessLevel: .verified)
						
		// wrap in a transaction to ensure each user connects to a unique reg code
		try await req.db.transaction { database in
			guard let dbRegCode = try await RegistrationCode.query(on: database).filter(\.$code == normalizedRegCode).first() else {
				throw Abort(.badRequest, reason: "No match for registration code")
			}
			guard dbRegCode.user == nil else {
			   throw Abort(.conflict, reason: "registration code has already been used")
			}
			user.verification = dbRegCode.code
			try await user.save(on: database)
			dbRegCode.$user.id = try user.requireID()
			try await dbRegCode.save(on: database)
		}
		try await req.userCache.updateUser(user.requireID())
		// return user data as .created
		let createdUserData = try CreatedUserData(userID: user.requireID(), username: user.username, recoveryKey: recoveryKey)
		let response = Response(status: .created)
		try response.content.encode(createdUserData)
		return response
	}
	
	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.
		
	/// `POST /api/v3/user/verify`
	///
	/// Changes a `User.accessLevel` from `.unverified` to `.verified` on successful submission
	/// of a registration code. User must be logged in. 
	/// 
	/// NOTE: previously it was possible to create an account and NOT provide a Registration Code, creating an account with an access level of .unverified. We 
	/// now require a registration code to create an account and all accounts are therefore already verified at creation time, meaning this method is not currently useful.
	///
	/// - Parameter requestBody: `UserVerifyData`
	/// - Throws: 400 error if the user is already verified or the registration code is not
	///   a valid one. 409 error if the registration code has already been allocated to
	///   another user.
	/// - Returns: HTTP status 200 on success.
	func verifyHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let data = try ValidatingJSONDecoder().decode(UserVerifyData.self, fromBodyOf: req)
		let normalizedCode = data.verification.lowercased().replacingOccurrences(of: " ", with: "")
		// update models and return 200
		try await req.db.transaction { database in
			let user = try await cacheUser.getUser(on: database)
			// abort if user is already verified
			guard user.verification == nil else {
				throw Abort(.badRequest, reason: "user is already verified")
			}
			// see `UserVerifyData.validations()`
			guard let dbRegCode = try await RegistrationCode.query(on: req.db).filter(\.$code == normalizedCode).first() else {
				throw Abort(.badRequest, reason: "registration code not found")
			}
			// abort if code is already used
			guard dbRegCode.user == nil else {
			   throw Abort(.conflict, reason: "registration code has already been used")
			}
			// update registrationCode
			dbRegCode.$user.id = cacheUser.userID
			try await dbRegCode.save(on: database)
			// update user
			user.accessLevel = .verified
			user.verification = dbRegCode.code
			try await user.save(on: database)
		}
		return .ok
	}
	
	/// `POST /api/v3/user/add`
	///
	/// Adds a new `User` sub-account to the current user's primary account. You can create a new sub account while logged in 
	/// on a sub account, but the new account is an sub of the primary account--there's no nesting or tree structure.
	/// 
	/// This method does not log in the newly created user. Users are limited to `Settings.shared.maxAlternateAccounts` 
	/// alts, which is 6 by default.
	///
	/// An `AddedUserData` structure is returned on success, containing the new user's ID
	/// and username.
	///
	/// - Note: API v3 supports a sub-account model, rather than the creation of individual
	///   accounts for multiple identities in prior versions. A sub-account inherits its parent
	///   user's `.accessLevel`, `.recoveryKey` and `.verification` values. Each `User`
	///   requires use of its own Bearer Authentication token and must log in individually;
	///   multiple accounts can all be simultaneously logged in.
	///
	/// - Parameter requestBody: `UserCreateData`
	/// - Throws: 400 error if the username is an invalid format or password is not at least
	///   6 characters. 403 error if the user is banned or currently quarantined. 409 errpr if
	///   the username is not available.
	/// - Returns: `AddedUserData` containing the newly created user's ID and username.
	func addHandler(_ req: Request) async throws -> Response {
		let user = try await req.auth.require(UserCacheData.self).getUser(on: req.db)
		// see `UserCreateData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserCreateData.self, fromBodyOf: req)
		// only upstanding citizens need apply--'validated' user level, not tmep-quarantined.
		try user.guardCanCreateContent(customErrorString: "user not currently permitted to create sub-account")
		let parentID = try user.$parent.id ?? user.requireID()
		let altAccountCount = try await User.query(on: req.db).filter(\.$parent.$id == parentID).count()
		let parentAccount = try await user.parentAccount(on: req)
		guard altAccountCount <= Settings.shared.maxAlternateAccounts else {
			throw Abort(.badRequest, reason: "Maximum number of alternate accounts reached.")
		}
		// check if existing username
		let existingUser = try await User.query(on: req.db).filter(\.$username, .custom("ilike"), data.username).first()
		guard existingUser == nil else {
			throw Abort(.conflict, reason: "username '\(data.username)' is not available")
		}
		// if user has a parent, sub-account inherits, else this account is parent
		let passwordHash = try Bcrypt.hash(data.password)
		// sub-account inherits .accessLevel, .recoveryKey and .verification
		let subAccount = User(
				username: data.username,
				password: passwordHash,
				recoveryKey: user.recoveryKey,
				verification: user.verification,
				parent: parentAccount,
				accessLevel: user.accessLevel)
		try await subAccount.save(on: req.db)
		let subAccountID = try subAccount.requireID()
		try await req.userCache.updateUser(subAccountID)
		// return user data as .created
		let addedUserData = AddedUserData(userID: subAccountID, username: subAccount.username)
		let response = Response(status: .created)
		try response.content.encode(addedUserData)
		return response
	}
	
	/// `GET /api/v3/user/whoami`
	///
	/// Returns the current user's `.id`, `.username` and whether they're currently logged in.
	///
	/// - Returns: `CurrentUserData` containing the current user's ID, username and logged in status.
	func whoamiHandler(_ req: Request) throws -> CurrentUserData {
		let user = try req.auth.require(UserCacheData.self)
		let currentUserData = CurrentUserData(userID: user.userID, username: user.username,
				// if there's a BasicAuthorization header, not logged in
				isLoggedIn: req.headers.basicAuthorization != nil ? false : true)
		return currentUserData
	}
	
	/// `POST /api/v3/user/password`
	///
	/// Updates a user's password to the supplied value, encrypted.
	///
	/// - Parameter requestBody: `UserPasswordData` struct containing the user's desired password.
	/// - Throws: 400 error if the supplied password is not at least 6 characters. 403 error
	///   if the user is a `.client`.
	/// - Returns: 201 Created on success.
	func passwordHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try await req.auth.require(UserCacheData.self).getUser(on: req.db)
		// clients are hard-coded
		guard user.accessLevel != .client else {
			throw Abort(.forbidden, reason: "password change would break a client")
		}
		// see `UserPasswordData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserPasswordData.self, fromBodyOf: req)
		guard try Bcrypt.verify(data.currentPassword, created: user.password) else {
			throw Abort(.badRequest, reason: "Existing password doesn't match; cannot set new password")
		}
		// encrypt, then update user
		let passwordHash = try Bcrypt.hash(data.newPassword)
		user.password = passwordHash
		try await user.save(on: req.db)
		return .created
	}
	
	/// `POST /api/v3/user/username`
	/// `POST /api/v3/user/:userID/username`				-- moderator use
	///
	/// Changes a user's username to the supplied value, if possible. `/api/v3/user/username` allows a user to change their own username,
	/// while `/api/v3/user/:userID/username` allows moderators to change the username of the indicated user.
	///
	/// - Parameter requestBody: `UserUsernameData` containing the user's desired new username.
	/// - Throws: 400 error if the username is an invalid format.
	///   403 error if you change username more than once per 20 hours (to prevent abuse). Or if the user is a `.client`.
	///   409 error if the username is not available.
	/// - Returns: 201 Created on success.
	func usernameHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let user = try await cacheUser.getUser(on: req.db)
		var targetUserID = cacheUser.userID
		if let targetUserIDString = req.parameters.get(userIDParam.paramString) {
			guard let targetID = UUID(uuidString: targetUserIDString) else {
				throw Abort(.badRequest, reason: "Could not make user ID parameter into a UUID")
			}
			targetUserID = targetID
		}
		// Bail if the request includes a targetUserID parameter but the parameter's invalid or isn't a valid userID.
		// Do not fall back to the 'change your own username' case.
		guard let targetUser = try await User.find(targetUserID, on: req.db) else {
			throw Abort(.badRequest, reason: "Could not find user with userID \(targetUserID.uuidString)")
		}
		try user.guardCanEditProfile(ofUser: targetUser)
		try guardNotSpecialAccount(targetUser)
		// clients are hard-coded
		guard targetUser.accessLevel != .client else {
			throw Abort(.forbidden, reason: "username change would break a client")
		}
		// see `UserUsernameData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserUsernameData.self, fromBodyOf: req)
		// check for existing username
		guard try await User.query(on: req.db).filter(\.$username, .custom("ilike"), data.username).first() == nil else {
			throw Abort(.conflict, reason: "username '\(data.username)' is not available")
		}
		// Check for recent name change; throw if the user has a profileEdit in the last 20 hours where the username doesn't match.
		if targetUser.id == user.id {
			let twentyHoursAgo = Date() - 3600.0 * 20.0
			let profileEdits = try await ProfileEdit.query(on: req.db).filter(\.$user.$id == targetUser.requireID())
					.filter(\.$createdAt > twentyHoursAgo).all()
			for edit in profileEdits {
				if edit.profileData?.header?.username != targetUser.username {
					throw Abort(.forbidden, reason: "Only one name change allowed per day.")
				}
			}
		}
		// record update for accountability
		let oldProfileEdit = try ProfileEdit(target: targetUser, editor: user)
		try await oldProfileEdit.save(on: req.db)
		targetUser.username = data.username
		targetUser.buildUserSearchString()
		try await targetUser.save(on: req.db)
		try await req.userCache.updateUser(targetUser.requireID())
		await targetUser.logIfModeratorAction(.edit, user: cacheUser, on: req)
		return .created
	}
	

// MARK: - Profile
	/// `POST /api/v3/user/image`
	///
	/// Sets the user's profile image to the `ImageUploadData` uploaded in the HTTP body. 
	/// 
	/// - If the `ImageUploadData` contains image data in the `image` member, that data is processed, saved, and set to user's new image
	/// - If the `ImageUploadData` contains a filename in the `filename` member, the user's avatar is set to that image file on the server. 
	/// We don't check whether the file exists.
	/// - If both members are nil, the user's avatar image is set to nil, which will cause the default image be returned.
	///
	/// - Parameter requestBody: `ImageUploadData` payload in the HTTP body.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `UserHeader` containing the generated image identifier string.
	func imageHandler(_ req: Request) async throws -> UserHeader {
		let user = try await req.auth.require(UserCacheData.self).getUser(on: req.db)
		try user.guardCanEditProfile()
		let data = try req.content.decode(ImageUploadData.self)
		// get generated filename
		let newImageName = try await processImage(data: data.image, usage: .userProfile, on: req) ?? data.filename
		// Save a thumbnail of existing image if there was one and we're changing it.
		if let existingImage = user.userImage, !existingImage.isEmpty, existingImage != newImageName {
			// create ProfileEdit record
			let profileEdit = try ProfileEdit(target: user, editor: user)
			// archive thumbnail
			DispatchQueue.global(qos: .background).async {
				self.archiveImage(existingImage, on: req)
			}
			try await profileEdit.save(on: req.db)
		}
		// Set new image
		user.userImage = newImageName
		user.profileUpdatedAt = Date()
		try await user.save(on: req.db)
		let userCacheData = try await req.userCache.updateUser(user.requireID())
		return userCacheData.makeHeader()
	}
	
	/// `POST /api/v3/user/image/remove`
	/// `DELETE /api/v3/user/image`
	/// `DELETE /api/v3/user/:userID/image`				 
	///
	/// Removes the user's profile image from their `User` object. This generally reverts their user avatar image to a default or auto-generated image. 
	/// 
	/// The third form, that takes a userID in the URL path, is for moderators only.
	///
	/// - Parameter userID: in URL path. Only for the third form of the URL path, which is moderator-only.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: 204 No Content on success.
	func imageRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let user = try await cacheUser.getUser(on: req.db)
		var targetUser = user
		if let targetUserIDString = req.parameters.get(userIDParam.paramString) {
			guard let targetUserID = UUID(uuidString: targetUserIDString), 
					let foundUser = try await User.find(targetUserID, on: req.db) else {
				throw Abort(.badRequest, reason: "Could not find user with userID \(targetUserIDString)")
			}
			targetUser = foundUser
		}
		try user.guardCanEditProfile(ofUser: targetUser)
		if let existingImage = targetUser.userImage, !existingImage.isEmpty {
			// create ProfileEdit record
			let profileEdit = try ProfileEdit(target: targetUser, editor: user)
			// archive thumbnail
			DispatchQueue.global(qos: .background).async {
				return self.archiveImage(existingImage, on: req)
			}
			try await profileEdit.save(on: req.db)
			// remove image from profile
			targetUser.userImage = nil
			targetUser.profileUpdatedAt = Date()
			try await targetUser.save(on: req.db)
			try await req.userCache.updateUser(targetUser.requireID())
			await targetUser.logIfModeratorAction(.delete, user: cacheUser, on: req)
		}
		return .noContent
	}
	
	/// `GET /api/v3/user/profile`
	///
	/// Retrieves the user's own profile data for editing, as a `ProfilePublicData` object.
	///
	/// - Note: The `.header.username` and `.header.displayName` properties of the returned object
	///   are for display convenience only. A username must be changed using the
	///   `POST /api/v3/user/username` endpoint. 
	///
	/// - Throws: 403 error if the user is banned. A 5xx response should be reported as a likely
	///   bug, please and thank you.
	/// - Returns: `ProfilePublicData` containing the editable properties of the profile.
	func profileHandler(_ req: Request) async throws -> ProfilePublicData {
		let user = try await req.auth.require(UserCacheData.self).getUser(on: req.db)
		return try ProfilePublicData(user: user, note: nil, requesterAccessLevel: user.accessLevel)
	}
	
	/// `POST /api/v3/user/profile`
	/// `POST /api/v3/user/:userID/profile` 				- for moderator use
	///
	/// Updates the user's profile.
	///
	/// - Note: All fields of the `UserProfileUploadData` structure being submitted **must** be
	///   present. While the properties of the profile itself are optional, the
	///   submitted values all *replace* the existing propety values. Submitting a value of `""`
	///   resets its respective profile property to `nil`.
	///
	/// - Parameter userID: in URL path. Only for the second form of the URL path, which is moderator-only.
	/// - Parameter requestBody: `UserProfileUploadData`
	/// - Throws: 403 error if the user is banned.
	/// - Returns: `ProfilePublicData` containing the updated editable properties of the profile.
	func profileUpdateHandler(_ req: Request) async throws -> ProfilePublicData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let user = try await cacheUser.getUser(on: req.db)
		var targetUser = user
		if let targetUserIDString = req.parameters.get(userIDParam.paramString) {
			guard let targetUserID = UUID(uuidString: targetUserIDString), 
					let foundUser = try await User.find(targetUserID, on: req.db) else {
				throw Abort(.badRequest, reason: "Could not find user with userID \(targetUserIDString)")
			}
			targetUser = foundUser
		}
		try user.guardCanEditProfile(ofUser: targetUser)
		let data = try ValidatingJSONDecoder().decode(UserProfileUploadData.self, fromBodyOf: req)
		// record update for accountability
		let oldProfileEdit = try ProfileEdit(target: targetUser, editor: user)
		try await oldProfileEdit.save(on: req.db)
		
		// update fields, nil if no value supplied
		targetUser.about = data.about?.isEmpty == true ? nil : data.about
		targetUser.displayName = data.displayName?.isEmpty == true ? nil : data.displayName
		targetUser.email = data.email?.isEmpty == true ? nil : data.email
		targetUser.homeLocation = data.homeLocation?.isEmpty == true ? nil : data.homeLocation
		targetUser.message = data.message?.isEmpty == true ? nil : data.message
		targetUser.preferredPronoun = data.preferredPronoun?.isEmpty == true ? nil : data.preferredPronoun
		targetUser.realName = data.realName?.isEmpty == true ? nil : data.realName
		targetUser.roomNumber = data.roomNumber?.isEmpty == true ? nil : data.roomNumber
			
		// build .userSearch value
		targetUser.buildUserSearchString()
			
		try await targetUser.save(on: req.db)
		try await req.userCache.updateUser(targetUser.requireID())
		await targetUser.logIfModeratorAction(.edit, user: cacheUser, on: req)
		return try ProfilePublicData(user: targetUser, note: nil, requesterAccessLevel: user.accessLevel)
	}

// MARK: - Alertwords   
	/// `POST /api/v3/user/alertwords/add/:alertword_string`
	///
	/// Adds a string to the user's "Alert Keywords" barrel. The string is lowercased and stripped of punctuation before being added.
	///
	/// - Parameter STRING: In URL path. The alert word to watch for.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `AlertKeywordData` containing the updated contents of the barrel.
	func alertwordsAddHandler(_ req: Request) async throws -> KeywordData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(alertwordParam.paramString)?.lowercased() else {
			throw Abort(.badRequest, reason: "No alert word to add found in request.")
		}
		let cleanedParams = Twarrt.buildCleanWordsArray(parameter)
		guard cleanedParams.count <= 1 else {
			throw Abort(.badRequest, reason: "Can only add one new alert word at a time.")
		}
		guard let cleanParam = cleanedParams.first, cleanParam.count > 3 else {
			throw Abort(.badRequest, reason: "Cannot set alerts on very short or very common words")
		}
		let  alertword = try await AlertWord.query(on: req.db).filter(\.$word == cleanParam).first() ?? AlertWord(cleanParam)
		try await alertword.save(on: req.db)
		try await AlertWordPivot(alertword: alertword, userID: cacheUser.userID).save(on: req.db)
		let keywordPivots = try await AlertWordPivot.query(on: req.db).filter(\.$user.$id == cacheUser.userID).with(\.$alertword).all()
		let keywords = keywordPivots.map { $0.alertword.word }
		return KeywordData(keywords: keywords.sorted())
	}
	
	/// `GET /api/v3/user/alertwords`
	///
	/// Returns a list of the user's current alert keywords in `AlertKeywordData` barrel format.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `AlertKeywordData` containing the current alert keywords as an array of strings.
	func alertwordsHandler(_ req: Request) async throws -> KeywordData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let keywordPivots = try await AlertWordPivot.query(on: req.db).filter(\.$user.$id == cacheUser.userID).with(\.$alertword).all()
		let keywords = keywordPivots.map { $0.alertword.word }
		return KeywordData(keywords: keywords)
	}
	
	/// `POST /api/v3/user/alertwords/remove/STRING`
	///
	/// Removes a string from the user's "Alert Keywords" barrel.
	///
	/// - Parameter STRING: In URL path. The alert word to remove from the alertword list.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `AlertKeywordData` containing the updated contents of the barrel.
	func alertwordsRemoveHandler(_ req: Request) async throws -> KeywordData {
		let user = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(alertwordParam.paramString)?.lowercased() else {
			throw Abort(.badRequest, reason: "No alert word to remove found in request.")
		}
		var pivots = try await AlertWordPivot.query(on: req.db).filter(\.$user.$id == user.userID).with(\.$alertword).all()
		if let removePivot = pivots.first(where: { $0.alertword.word == parameter }) {
			let alertWord = removePivot.alertword
			try await removePivot.delete(on: req.db)
			pivots.removeAll { $0.id == removePivot.id }
			if try await alertWord.$users.$pivots.query(on: req.db).count() == 0 {
				try await alertWord.delete(on: req.db)
				try await req.redis.removeAlertword(parameter)
			}
		}
		let keywords = pivots.map { $0.alertword.word }
		return KeywordData(keywords: keywords.sorted())
	}

// MARK: - Blocks
// MARK: - Muted Users
// MARK: - Mutewords
	/// `POST /api/v3/user/mutewords/add/STRING`
	///
	/// Adds a string to the user's "Muted Keywords" barrel.
	///
	/// - Parameter STRING: In URL path. The muteword to add.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MuteKeywordData` containing the updated contents of the barrel.
	func mutewordsAddHandler(_ req: Request) async throws -> KeywordData {
		let user = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(mutewordParam.paramString)?.lowercased() else {
			throw Abort(.badRequest, reason: "No mute word to add found in request.")
		}
		let cleanedParams = Twarrt.buildCleanWordsArray(parameter)
		guard cleanedParams.count <= 1 else {
			throw Abort(.badRequest, reason: "Can only add one new mute word at a time.")
		}
		guard let cleanParam = cleanedParams.first, cleanParam.count > 3 else {
			throw Abort(.badRequest, reason: "Cannot mute on very short or very common words")
		}
		// Get all the mutewords for this user, since we'll need them for the return value
		let mutewordRecords = try await MuteWord.query(on: req.db).filter(\.$user.$id == user.userID).all()
		var mutewords = mutewordRecords.map { $0.word }
		if !mutewords.contains(cleanParam) {
			let newMuteword = MuteWord(cleanParam, userID: user.userID)
			try await newMuteword.save(on: req.db)
			try await req.userCache.updateUser(user.userID)
			mutewords.append(cleanParam)
		}
		let muteKeywordData = KeywordData(keywords: mutewords.sorted())
		return muteKeywordData
	}
	
	/// `GET /api/v3/user/mutewords`
	///
	/// Returns a list of the user's currently muted keywords in named-list  `MuteKeywordData` format.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MuteKeywordData` containing the current muting keywords as an array of  strings.
	func mutewordsHandler(_ req: Request) async throws -> KeywordData {
		let user = try req.auth.require(UserCacheData.self)
		let mutewordRecords = try await MuteWord.query(on: req.db).filter(\.$user.$id == user.userID).all()
		let mutewords = mutewordRecords.map { $0.word }
		return KeywordData(keywords: mutewords.sorted())
	}
	
	/// `POST /api/v3/user/mutewords/remove/STRING`
	///
	/// Removes a string from the user's "Muted Keywords" barrel.
	///
	/// - Parameter STRING: In URL path. The muteword to remove.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MuteKeywordData` containing the updated contents of the barrel.
	func mutewordsRemoveHandler(_ req: Request) async throws -> KeywordData {
		let user = try req.auth.require(UserCacheData.self)
		guard let parameter = req.parameters.get(mutewordParam.paramString)?.lowercased() else {
			throw Abort(.badRequest, reason: "No mute word to remove found in request.")
		}
		let cleanedParams = Twarrt.buildCleanWordsArray(parameter)
		guard cleanedParams.count <= 1, let cleanParam = cleanedParams.first else {
			throw Abort(.badRequest, reason: "Can only remove one mute word at a time.")
		}
		// Get all the mutewords for this user, since we'll need them for the return value
		var mutewordRecords = try await MuteWord.query(on: req.db).filter(\.$user.$id == user.userID).all()
		if let foundRecord = mutewordRecords.first(where: { $0.word == cleanParam }) {
			try await foundRecord.delete(on: req.db)
			try await req.userCache.updateUser(user.userID)
			mutewordRecords.removeAll { $0.word == cleanParam }
		}
		let mutewords = mutewordRecords.map { $0.word }
		let muteKeywordData = KeywordData(keywords: mutewords.sorted())
		return muteKeywordData
	}		
		
	/// `GET /api/v3/user/notes`
	///
	/// Retrieves all `UserNote>s owned by the current user, as an array of `NoteData` objects.
	///
	/// The `NoteData` object is intended to be display friendly, including fields for
	/// potential sorting, the ID of the profile which can be linked to, and the profile's user
	/// in the familiar .displayedName format. The .noteID is included as well to support
	/// editing of notes outside of a profile-viewing context.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: An array of  `NoteData` containing all of the user's notes.
	func notesHandler(_ req: Request) async throws -> [NoteData] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get all notes, and for each note, the user the note's written about.
		guard let user = try await User.find(cacheUser.userID, on: req.db) else {
			throw Abort(.internalServerError, reason: "Could not find User in db, but found it in cache.")
		}
		let notes = try await user.$notes.query(on: req.db).with(\.$noteSubject).all()
		// create array for return
		let notesData: [NoteData] = try notes.map { try NoteData(note: $0, targetUser: $0.noteSubject) }
		return notesData
	}
	
	// MARK: - Helper Functions
		
	/// Generates a recovery key of 3 words randomly chosen from `words` array.
	///
	/// - Parameter req: The incoming `Request`, provided automatically.
	/// - Throws: 500 error if the randomizer fails.
	/// - Returns: A recoveryKey string.
	static func generateRecoveryKey(on req: Request) throws -> String {
		guard let word1 = words.randomElement(),
			let word2 = words.randomElement(),
			let word3 = words.randomElement() else {
				throw Abort(.internalServerError, reason: "could not generate recovery key")
		}
		let recoveryKey = word1 + " " + word2 + " " + word3
		return recoveryKey
	}
}

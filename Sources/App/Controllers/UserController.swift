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
        
    /// The `BarrelType`s that a user may retrieve using endpoints in this controller.
    static let userBarrelTypes: [BarrelType] = [
        .keywordAlert,
        .keywordMute,
        .seamonkey,
        .userBlock,
        .userMute,
        .userWords
    ]

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
        "milk", "mint", "mitten", "monkey", "morning", "moustache", "mouth",
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
		let tokenAuthGroup = addTokenAuthGroup(to: userRoutes)
        tokenAuthGroup.post("verify", use: verifyHandler)
        tokenAuthGroup.post("image", use: imageHandler)
        tokenAuthGroup.post("image", "remove", use: imageRemoveHandler)
        tokenAuthGroup.delete("image", use: imageRemoveHandler)
        tokenAuthGroup.delete(":target_user", "image", use: imageRemoveHandler)
        tokenAuthGroup.get("profile", use: profileHandler)
        tokenAuthGroup.post("profile", use: profileUpdateHandler)
        tokenAuthGroup.post(":target_user", "profile", use: profileUpdateHandler)
        tokenAuthGroup.get("whoami", use: whoamiHandler)
        tokenAuthGroup.post("add", use: addHandler)
        tokenAuthGroup.get("alertwords", use: alertwordsHandler)
        tokenAuthGroup.post("alertwords", "add", alertwordParam, use: alertwordsAddHandler)
        tokenAuthGroup.post("alertwords", "remove", alertwordParam, use: alertwordsRemoveHandler)
        tokenAuthGroup.post("barrel", use: createBarrelHandler)
        tokenAuthGroup.get("barrels", use: barrelsHandler)
        tokenAuthGroup.get("barrels", "seamonkey", use: seamonkeyBarrelsHandler)
        tokenAuthGroup.get("barrels", barrelIDParam, use: barrelHandler)
        tokenAuthGroup.post("barrels", barrelIDParam, "add", ":string", use: barrelAddHandler)
        tokenAuthGroup.post("barrels", barrelIDParam, "delete", use: deleteBarrelHandler)
        tokenAuthGroup.post("barrels", barrelIDParam, "remove", ":string", use: barrelRemoveHandler)
        tokenAuthGroup.post("barrels", barrelIDParam, "rename", ":barrel_name", use: renameBarrelHandler)
        tokenAuthGroup.get("blocks", use: blocksHandler)
        tokenAuthGroup.get("mutes", use: mutesHandler)
        tokenAuthGroup.get("mutewords", use: mutewordsHandler)
        tokenAuthGroup.post("mutewords", "add", mutewordParam, use: mutewordsAddHandler)
        tokenAuthGroup.post("mutewords", "remove", mutewordParam, use: mutewordsRemoveHandler)
        tokenAuthGroup.get("notes", use: notesHandler)
        tokenAuthGroup.post("password", use: passwordHandler)
        tokenAuthGroup.post("username", use: usernameHandler)
        tokenAuthGroup.post(":target_user", "username", use: usernameHandler)
    }
    
    // MARK: - Open Access Handlers
    
    /// `POST /api/v3/user/create`
    ///
    /// Creates a new `User` account. Does not log the new user in. Route is open access.
    ///
    /// A  <doc:CreatedUserData> structure is returned on success, containing the new user's ID,
    /// username and a generated recovery key.
    ///
    /// - Note: The `CreatedUserData.recoveryKey` is a random phrase used to recover an account
    ///   in the case of a forgotten password. While it can be stored by a client, that
    ///   essentially defeats its purpose (presumably the password would also already be
    ///   stored). The *intended client use* is that it is displayed to the user upon successful
    ///   creation, and the user is *encouraged to take a screenshot or write it down before
    ///   proceeding*.
    ///
    /// - Parameter requestBody: <doc:UserCreateData>
    /// - Throws: 400 error if the username is an invalid format. 409 errpr if the username is
    ///   not available.
    /// - Returns: <doc:CreatedUserData> containing the newly created user's ID, username, and a
    ///   recovery key string.
    func createHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        // see `UserCreateData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserCreateData.self, fromBodyOf: req)
        // check for existing username so we can return 409 Conflict status instead
        // of the default super-unfriendly 500 for unique constraint violation
        return User.query(on: req.db).filter(\.$username, .custom("ilike"), data.username).first().throwingFlatMap { (existingUser) in
			// abort if name is already taken
			guard existingUser == nil else {
				throw Abort(.conflict, reason: "username '\(data.username)' is not available")
			}
			
			// create recovery key
			var recoveryKey = ""
			_ = try UserController.generateRecoveryKey(on: req).map { (resolvedKey) in
				recoveryKey = resolvedKey
			}
			let normalizedKey = recoveryKey.lowercased().replacingOccurrences(of: " ", with: "")
			
			// create user
			let passwordHash = try req.password.hash(data.password)
			let recoveryHash = try Bcrypt.hash(normalizedKey)
			let user = User(username: data.username, password: passwordHash, recoveryKey: recoveryHash,
					verification: nil, parent: nil, accessLevel: .unverified)
			
			// We don't need a reg code to make a user, but a malformed code is an error.
			var normalizedCode = data.verification?.lowercased().replacingOccurrences(of: " ", with: "")
			if normalizedCode?.count == 0 {
				normalizedCode = nil
			}
			if let code = normalizedCode {
				guard code.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil && code.count == 6 else {
					throw Abort(.badRequest, reason: "Malformed verification code. Verification code " +
							"must be 6 alphanumeric letters; spaces optional.")
				}
			}
			
			// ACTUALLY, no reg code is an error now
			guard let _ = normalizedCode else {
				throw Abort(.badRequest, reason: "Registration Code required to create account.")
			}
			
			// wrap in a transaction to ensure each user has an associated profile
			return req.db.transaction { (database) in
				var result: EventLoopFuture<RegistrationCode?>
				if let code = normalizedCode {
					result = RegistrationCode.query(on: database).filter(\.$code == code).first()
				}
				else {
					result = database.eventLoop.future(nil)
				}
				return result.throwingFlatMap { (regCode) in
					// normalizedCode is from request body, regCode is from RegistrationCode table lookup
					if normalizedCode != nil {
						guard let registrationCode = regCode else {
							throw Abort(.badRequest, reason: "registration code not found")
						}
						guard registrationCode.user == nil else {
						   throw Abort(.conflict, reason: "registration code has already been used")
						}
						user.accessLevel = .verified
						user.verification = registrationCode.code
					}
					return user.save(on: database).throwingFlatMap {
						var saveRegCode: EventLoopFuture<Void> = database.eventLoop.future()
						if let registrationCode = regCode {
							registrationCode.$user.id = try user.requireID()
							saveRegCode = registrationCode.save(on: database)
						}
						
						// initialize default barrels and profile with our new user.
						let barrels = self.createDefaultBarrels(for: user, on: database)
						return database.eventLoop.flatten([barrels, saveRegCode])
					}
				}
			}
			.throwingFlatMap {
				return try req.userCache.updateUser(user.requireID()).flatMapThrowing { (_) in
					// return user data as .created
					let createdUserData = try CreatedUserData(userID: user.requireID(), username: user.username, recoveryKey: recoveryKey)
					let response = Response(status: .created)
					try response.content.encode(createdUserData)
					return response
				}
			}
		}
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
        
    /// `POST /api/v3/user/verify`
    ///
    /// Changes a `User.accessLevel` from `.unverified` to `.verified` on successful submission
    /// of a registration code. User must be logged in.
    ///
    /// - Parameter requestBody: <doc:UserVerifyData>
    /// - Throws: 400 error if the user is already verified or the registration code is not
    ///   a valid one. 409 error if the registration code has already been allocated to
    ///   another user.
    /// - Returns: HTTP status 200 on success.
    func verifyHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // abort if user is already verified
        guard user.verification == nil else {
            throw Abort(.badRequest, reason: "user is already verified")
        }
        // see `UserVerifyData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserVerifyData.self, fromBodyOf: req)
        let normalizedCode = data.verification.lowercased().replacingOccurrences(of: " ", with: "")
        return RegistrationCode.query(on: req.db)
				.filter(\.$code == normalizedCode)
				.first()
				.unwrap(or: Abort(.badRequest, reason: "registration code not found"))
				.throwingFlatMap { (registrationCode) in
			// abort if code is already used
			guard registrationCode.user == nil else {
			   throw Abort(.conflict, reason: "registration code has already been used")
			}
			// update models and return 200
			return req.db.transaction { (database) in
				// update registrationCode
				registrationCode.$user.id = userID
				return registrationCode.save(on: database).flatMap {
					// update user
					user.accessLevel = .verified
					user.verification = registrationCode.code
					return user.save(on: database).transform(to: .ok)
				}
			}
        }
    }
    
    /// `POST /api/v3/user/add`
    ///
    /// Adds a new `User` sub-account to the current user's primary account. You can create a new sub account while logged in 
	/// on a sub account, but the new account is an sub of the primary account--there's no nesting or tree structure.
	/// 
	/// This method does not log in the newly created user. Users are limited to `Settings.shared.maxAlternateAccounts` 
	/// alts, which is 6 by default.
    ///
    /// An <doc:AddedUserData> structure is returned on success, containing the new user's ID
    /// and username.
    ///
    /// - Note: API v3 supports a sub-account model, rather than the creation of individual
    ///   accounts for multiple identities in prior versions. A sub-account inherits its parent
    ///   user's `.accessLevel`, `.recoveryKey` and `.verification` values. Each `User`
    ///   requires use of its own Bearer Authentication token and must log in individually;
    ///   multiple accounts can all be simultaneously logged in.
    ///
    /// - Parameter requestBody: <doc:UserCreateData>
    /// - Throws: 400 error if the username is an invalid format or password is not at least
    ///   6 characters. 403 error if the user is banned or currently quarantined. 409 errpr if
    ///   the username is not available.
    /// - Returns: <doc:AddedUserData> containing the newly created user's ID and username.
    func addHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        // see `UserCreateData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserCreateData.self, fromBodyOf: req)
        // only upstanding citizens need apply--'validated' user level, not tmep-quarantined.
        try user.guardCanCreateContent(customErrorString: "user not currently permitted to create sub-account")
        let parentID = try user.$parent.id ?? user.requireID()
        return try User.query(on: req.db).filter(\.$parent.$id == parentID).count()
        		.and(user.parentAccount(on: req)).throwingFlatMap { (altAccountCount, parentAccount) in
        	guard altAccountCount <= Settings.shared.maxAlternateAccounts else {
        		throw Abort(.badRequest, reason: "Maximum number of alternate accounts reached.")
        	}
			// check if existing username
			return User.query(on: req.db).filter(\.$username, .custom("ilike"), data.username).first().throwingFlatMap { existingUser in
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
				return req.db.transaction { (database) in
					return subAccount.save(on: database).transform(to: subAccount).addModelID().flatMap { (newAccount, newAccountID) in
						// initialize default barrels
						return self.createDefaultBarrels(for: newAccount, on: database).transform(to: newAccount)
					}
				}.throwingFlatMap { newAccount in
					let newAccountID = try newAccount.requireID()
					return req.userCache.updateUser(newAccountID).flatMapThrowing { (cacheData) -> Response in
						// return user data as .created
						let addedUserData = AddedUserData(userID: newAccountID, username: newAccount.username)
						let response = Response(status: .created)
						try response.content.encode(addedUserData)
						return response
					}
				}
			}
		}
    }
    
    /// `GET /api/v3/user/whoami`
    ///
    /// Returns the current user's `.id`, `.username` and whether they're currently logged in.
	///
    /// - Returns: <doc:CurrentUserData> containing the current user's ID, username and logged in status.
    func whoamiHandler(_ req: Request) throws -> EventLoopFuture<CurrentUserData> {
        let user = req.auth.get(User.self)
        // well, we have to unwrap somewhere
        guard let me = user else {
            throw Abort(.internalServerError, reason: "this is seriously not possible")
        }
        let currentUserData = try CurrentUserData(
            userID: me.requireID(),
            username: me.username,
            // if there's a BasicAuthorization header, not logged in
            isLoggedIn: req.headers.basicAuthorization != nil ? false : true
        )
        return req.eventLoop.future(currentUserData)
    }
    
    /// `POST /api/v3/user/password`
    ///
    /// Updates a user's password to the supplied value, encrypted.
    ///
    /// - Parameter requestBody: <doc:UserPasswordData> struct containing the user's desired password.
    /// - Throws: 400 error if the supplied password is not at least 6 characters. 403 error
    ///   if the user is a `.client`.
    /// - Returns: 201 Created on success.
    func passwordHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
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
        return user.save(on: req.db).transform(to: .created)
    }
    
    /// `POST /api/v3/user/username`
    /// `POST /api/v3/user/ID/username`				-- moderator use
    ///
    /// Changes a user's username to the supplied value, if possible. 
    ///
    /// - Parameter requestBody: <doc:UserUsernameData> containing the user's desired new username.
    /// - Throws: 400 error if the username is an invalid format. 403 error if the user is a
    ///   `.client`. 409 errpr if the username is not available.
    /// - Returns: 201 Created on success.
    func usernameHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let targetUserID = req.parameters.get("target_user", as: UUID.self)
		return User.find(targetUserID, on: req.db).throwingFlatMap { foundTargetUser in
			// If the request includes a targetUserID but we couldn't find them--bail. Otherwise `user` will be removing
			// their own profile image, which is not what they intended.
			guard targetUserID == nil || foundTargetUser != nil else {
				throw Abort(.badRequest, reason: "Could not find user with userID \(targetUserID?.uuidString ?? "")")
			}
			// In the moderation route, foundTargetUser != nil and (usually) foundTargetUser != user. 
			// If a user is editing their own image, foundTargetUser == nil.
			let targetUser = foundTargetUser ?? user
			try user.guardCanEditProfile(ofUser: targetUser)
			// clients are hard-coded
			guard targetUser.accessLevel != .client else {
				throw Abort(.forbidden, reason: "username change would break a client")
			}
			// see `UserUsernameData.validations()`
			let data = try ValidatingJSONDecoder().decode(UserUsernameData.self, fromBodyOf: req)
			// check for existing username
			return User.query(on: req.db)
					.filter(\.$username, .custom("ilike"), data.username)
					.first()
					.throwingFlatMap { (existingUser) in
				// abort if name is already taken
				guard existingUser == nil else {
					throw Abort(.conflict, reason: "username '\(data.username)' is not available")
				}
				// record update for accountability
				let oldProfileEdit = try ProfileEdit(target: targetUser, editor: user)
				_ = oldProfileEdit.save(on: req.db)

				targetUser.username = data.username
				targetUser.buildUserSearchString()
				return targetUser.save(on: req.db).flatMapThrowing {
					try req.userCache.updateUser(targetUser.requireID())
					return .created
				}
			}
		}
    }
    

// MARK: - Profile
    /// `POST /api/v3/user/image`
    ///
    /// Sets the user's profile image to the <doc:ImageUploadData> uploaded in the HTTP body. 
	/// 
	/// - If the <doc:ImageUploadData> contains image data in the `image` member, that data is processed, saved, and set to user's new image
	/// - If the <doc:ImageUploadData> contains a filename in the `filename` member, the user's avatar is set to that image file on the server. 
	/// We don't check whether the file exists.
	/// - If both members are nil, the user's avatar image is set to nil, which will cause the default image be returned.
    ///
    /// - Parameter requestBody: <doc:ImageUploadData> payload in the HTTP body.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:UserHeader> containing the generated image identifier string.
    func imageHandler(_ req: Request) throws -> EventLoopFuture<UserHeader> {
        let user = try req.auth.require(User.self)
        try user.guardCanEditProfile()
        let data = try req.content.decode(ImageUploadData.self)
        // get generated filename
        return processImage(data: data.image, usage: .userProfile, on: req).throwingFlatMap { filename in
			let newImageName = filename ?? data.filename
			// Save a thumbnail of existing image if there was one and we're changing it.
			if let existingImage = user.userImage, !existingImage.isEmpty, existingImage != newImageName {
				// create ProfileEdit record
				let profileEdit = try ProfileEdit(target: user, editor: user)
				// archive thumbnail
				DispatchQueue.global(qos: .background).async {
					self.archiveImage(existingImage, on: req)
				}
				return profileEdit.save(on: req.db).transform(to: newImageName)
			}
			return req.eventLoop.future(newImageName) 
		}
		.flatMap { (filename: String?) in
			// Set new image
			user.userImage = filename
			user.profileUpdatedAt = Date()
			return user.save(on: req.db).throwingFlatMap {
				return try req.userCache.updateUser(user.requireID()).map { userCacheData in
					return userCacheData.makeHeader()
				}
			}
		}
    }
    
    /// `POST /api/v3/user/image/remove`
    /// `DELETE /api/v3/user/image`
	/// `DELETE /api/v3/user/ID/image`				 
    ///
    /// Removes the user's profile image from their `User` object. This generally reverts their user avatar image to a default or auto-generated image. 
	/// 
	/// The third form, that takes a userID in the URL path, is for moderators only.
    ///
    /// - Parameter userID: in URL path. Only for the third form of the URL path, which is moderator-only.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: 204 No Content on success.
    func imageRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let targetUserID = req.parameters.get("target_user", as: UUID.self)
		return User.find(targetUserID, on: req.db).throwingFlatMap { foundTargetUser in
			// If the request includes a targetUserID but we couldn't find them--bail. Otherwise `user` will be removing
			// their own profile image, which is not what they intended.
			guard targetUserID == nil || foundTargetUser != nil else {
				throw Abort(.badRequest, reason: "Could not find user with userID \(targetUserID?.uuidString ?? "")")
			}
			// In the moderation route, foundTargetUser != nil and (usually) foundTargetUser != user. 
			// If a user is editing their own image, foundTargetUser == nil.
			let targetUser = foundTargetUser ?? user
			try user.guardCanEditProfile(ofUser: targetUser)
			if let existingImage = targetUser.userImage, !existingImage.isEmpty {
				// create ProfileEdit record
				let profileEdit = try ProfileEdit(target: targetUser, editor: user)
				// archive thumbnail
				DispatchQueue.global(qos: .background).async {
					return self.archiveImage(existingImage, on: req)
				}
				return profileEdit.save(on: req.db).flatMap { (_) in
					// remove image from profile
					targetUser.userImage = nil
					targetUser.profileUpdatedAt = Date()
					return targetUser.save(on: req.db).flatMapThrowing {
						try req.userCache.updateUser(targetUser.requireID())
						targetUser.logIfModeratorAction(.delete, user: user, on: req)
						return .noContent
					}
				}
			}
			// no existing image
			return req.eventLoop.future(.noContent)
		}
    }
    
    /// `GET /api/v3/user/profile`
    ///
    /// Retrieves the user's own profile data for editing, as a <doc:ProfilePublicData> object.
	///
    /// - Note: The `.header.username` and `.header.displayName` properties of the returned object
    ///   are for display convenience only. A username must be changed using the
    ///   `POST /api/v3/user/username` endpoint. 
    ///
    /// - Throws: 403 error if the user is banned. A 5xx response should be reported as a likely
    ///   bug, please and thank you.
    /// - Returns: <doc:ProfilePublicData> containing the editable properties of the profile.
    func profileHandler(_ req: Request) throws -> ProfilePublicData {
        let user = try req.auth.require(User.self)
        return try ProfilePublicData(user: user, note: nil, requesterAccessLevel: user.accessLevel)
    }
    
    /// `POST /api/v3/user/profile`
	/// `POST /api/v3/user/ID/profile` 				- for moderator use
    ///
    /// Updates the user's profile.
	///
    /// - Note: All fields of the <doc:UserProfileUploadData> structure being submitted **must** be
    ///   present. While the properties of the profile itself are optional, the
    ///   submitted values all *replace* the existing propety values. Submitting a value of `""`
    ///   resets its respective profile property to `nil`.
    ///
    /// - Parameter userID: in URL path. Only for the second form of the URL path, which is moderator-only.
    /// - Parameter requestBody: <doc:UserProfileUploadData>
    /// - Throws: 403 error if the user is banned.
    /// - Returns: <doc:ProfilePublicData> containing the updated editable properties of the profile.
    func profileUpdateHandler(_ req: Request) throws -> EventLoopFuture<ProfilePublicData> {
        let user = try req.auth.require(User.self)
        let targetUserID = req.parameters.get("target_user", as: UUID.self)
		return User.find(targetUserID, on: req.db).throwingFlatMap { foundTargetUser in
			// If the request includes a targetUserID but we couldn't find them--bail. Otherwise `user` will be removing
			// their own profile image, which is not what they intended.
			guard targetUserID == nil || foundTargetUser != nil else {
				throw Abort(.badRequest, reason: "Could not find user with userID \(targetUserID?.uuidString ?? "")")
			}
			// In the moderation route, foundTargetUser != nil and (usually) foundTargetUser != user. 
			// If a user is editing their own image, foundTargetUser == nil.
			let targetUser = foundTargetUser ?? user
			try user.guardCanEditProfile(ofUser: targetUser)
			let data = try ValidatingJSONDecoder().decode(UserProfileUploadData.self, fromBodyOf: req)
			
			// record update for accountability
			let oldProfileEdit = try ProfileEdit(target: targetUser, editor: user)
			_ = oldProfileEdit.save(on: req.db)
		
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
			
			return targetUser.save(on: req.db).flatMapThrowing {
				try req.userCache.updateUser(targetUser.requireID())
				targetUser.logIfModeratorAction(.edit, user: user, on: req)
				return try ProfilePublicData(user: targetUser, note: nil, requesterAccessLevel: user.accessLevel)
			}
		}
    }

// MARK: - Alertwords   
    /// `POST /api/v3/user/alertwords/add/STRING`
    ///
    /// Adds a string to the user's "Alert Keywords" barrel. The string is lowercased and stripped of punctuation before being added.
    ///
    /// - Parameter STRING: In URL path. The alert word to watch for.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:AlertKeywordData> containing the updated contents of the barrel.
    func alertwordsAddHandler(_ req: Request) throws -> EventLoopFuture<AlertKeywordData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let param = req.parameters.get(alertwordParam.paramString)
        guard let parameter = param  else {
        	throw Abort(.badRequest, reason: "No alert word to add found in request.")
        }
		let cleanedParams = Twarrt.buildCleanWordsArray(parameter)
        guard cleanedParams.count <= 1 else {
        	throw Abort(.badRequest, reason: "Can only add one new alert word at a time.")
        }
        guard let cleanParam = cleanedParams.first, cleanParam.count > 3 else {
        	throw Abort(.badRequest, reason: "Cannot set alerts on very short or very common words")
        }
        // Get alertwords barrel. Create a dummy one if the user doesn't already have one.
        // We don't need to save it since that will happen when the user adds a word to it.
        return user.getBookmarkBarrel(of: .keywordAlert, on: req.db)
				.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .keywordAlert)).flatMap { barrel in
			// add string
			var alertWords = barrel.userInfo["alertWords"] ?? []
			alertWords.append(cleanParam)
			barrel.userInfo.updateValue(alertWords.sorted(), forKey: "alertWords")
			return barrel.save(on: req.db).flatMap { (_) in
				return req.redis.zincrby(1.0, element: cleanParam, in: "alertwords")
						.and(addAlertwordForUser(cleanParam, userID: userID, on: req)).flatMap { _ in			
					// return sorted list
					let alertKeywordData = AlertKeywordData(name: barrel.name, keywords: alertWords.sorted())
					// update cache
					return req.userCache.updateUser(userID).transform(to: alertKeywordData)
				}
			}
        }
    }
    
    /// `GET /api/v3/user/alertwords`
    ///
    /// Returns a list of the user's current alert keywords in <doc:AlertKeywordData> barrel format.
    ///
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:AlertKeywordData> containing the current alert keywords as an array of strings.
    func alertwordsHandler(_ req: Request) throws -> EventLoopFuture<AlertKeywordData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // Get alertwords barrel. Create a dummy one if the user doesn't already have one.
        // We don't need to save it since that will happen when the user adds a word to it.
        return Barrel.query(on: req.db)
				.filter(\.$ownerID == userID)
				.filter(\.$barrelType == .keywordAlert)
				.first()
				.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .keywordAlert))
				.map { (barrel) in
			// return as AlertKeywordData
			let alertKeywordData = AlertKeywordData(name: barrel.name, keywords: barrel.userInfo["alertWords"] ?? [])
			return alertKeywordData
        }
    }
    
    /// `POST /api/v3/user/alertwords/remove/STRING`
    ///
    /// Removes a string from the user's "Alert Keywords" barrel.
    ///
    /// - Parameter STRING: In URL path. The alert word to remove from the alertword list.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:AlertKeywordData> containing the updated contents of the barrel.
    func alertwordsRemoveHandler(_ req: Request) throws -> EventLoopFuture<AlertKeywordData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let param = req.parameters.get(alertwordParam.paramString)
        guard let parameter = param?.lowercased() else {
        	throw Abort(.badRequest, reason: "No alert word to remove found in request.")
        }
        // get alertwords barrel
        return user.getBookmarkBarrel(of: .keywordAlert, on: req.db)
				.unwrap(or: Abort(.internalServerError, reason: "alert keywords barrel not found"))
				.throwingFlatMap { barrel in
			// remove string
			var alertWords = barrel.userInfo["alertWords"] ?? []
			guard let index = alertWords.firstIndex(of: parameter) else {
				throw Abort(.badRequest, reason: "'\(parameter)' is not in barrel")
			}
			alertWords.remove(at: index)
			barrel.userInfo.updateValue(alertWords.sorted(), forKey: "alertWords")
			return barrel.save(on: req.db).flatMap {
				return req.redis.zincrby(-1.0, element: parameter, in: "alertwords").flatMap { newScore in
					// Set of users that have an alertword		
					_ = removeAlertwordForUser(parameter, userID: userID, on: req).transform(to: 0)
					// return sorted list
					let alertKeywordData = AlertKeywordData(name: barrel.name, keywords: alertWords.sorted())
					// update cache
					return req.userCache.updateUser(userID).transform(to: alertKeywordData)
				}
			}
		}
    }

// MARK: - Barrels
    /// `POST /api/v3/user/barrel`
    ///
    /// Creates a new user-owned `Barrel` based on the contents of the supplied <doc:BarrelCreateData>.
    ///
    /// The <doc:BarrelCreateData> must contain a `.name`, the other two fields are optional. If
    /// seeding the barrel with UUIDs, only the `.uuidList` should be present. If seeding the
    /// barrel with strings, only the `.stringList` should be present. If neither are provided,
    /// the barrel is created as a UUID barrel of type `.seamonkey`.
    ///
    /// - Important: Do not send an empty array of strings in the `.stringList` field unless
    ///   the barrel is intended as a string list. Omit the field entirely from the structure
    ///   when submitting the request.
    ///
    /// The returned <doc:BarrelData> struct will always contain the barrel's name and an
    /// initialzed array of <doc:SeaMonkey> (it will be empty if no seed UUIDs were supplied). If
    /// the barrel is of type `.userWords`, a `.stringList` value will also be returned. The
    /// presence or non-presence of this value is the client's cue as to what type of barrel
    /// this is.
    ///
    /// - Parameter requestBody: <doc:BarrelCreateData> struct containing the barrel name and any seed UUIDs or
    ///     seed string array.
    /// - Returns: <doc:BarrelData> containing the newly created barrel's data contents.
    func createBarrelHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        // see `BarrelCreateData.validations()`
		let data = try ValidatingJSONDecoder().decode(BarrelCreateData.self, fromBodyOf: req)
        // initialize barrel
        let barrel = try Barrel(ownerID: user.requireID(),
				// if no .stringList, it's a barrel of monkeys
				barrelType: data.stringList == nil ? .seamonkey : .userWords,
				name: data.name,
				modelUUIDs: [],
				userInfo: [:])
        // if .userWords, set userInfo key:value, else update modelUUIDs if any
        switch barrel.barrelType {
            case .userWords:
                if let strings = data.stringList {
                    barrel.userInfo.updateValue(strings, forKey: "userWords")
            }
            default:
                if let uuids = data.uuidList {
                    barrel.modelUUIDs = uuids
            }
        }
        return barrel.save(on: req.db).flatMap { (_) in
            // create SeaMonkeys from any UUIDs
            return User.query(on: req.db)
					.filter(\.$id ~~ barrel.modelUUIDs)
					.sort(\.$username, .ascending)
					.all()
					.flatMapThrowing { (users) in
				// return as BarrelData, with 201 response
				let barrelData = try BarrelData(barrel: barrel, users: users)
				let response = Response(status: .created)
				try response.content.encode(barrelData)
				return response
            }
        }
    }
    
    /// `POST /api/v3/user/barrels/ID/delete`
    ///
    /// Deletes the specified `Barrel`.
    ///
    /// - Parameter barrelID: In URL path. The barrel to delete.
    /// - Throws: 400 error if the barrel type is not supported by the endpoint. 403 error if
    ///   the barrel is not owned by the user. 404 or 500 error if the specified ID value is
    ///   invalid.
    /// - Returns: 204 NoContent on successful deletion.
    func deleteBarrelHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get barrel
        return Barrel.findFromParameter(barrelIDParam, on: req).throwingFlatMap { barrel in
			guard try barrel.ownerID == user.requireID() else {
				throw Abort(.forbidden, reason: "user is not owner of barrel")
			}
			// only user types can be retrieved here
			let userTypes: [BarrelType] = [.seamonkey, .userWords]
			guard userTypes.contains(barrel.barrelType) else {
				throw Abort(.badRequest,reason: "'\(barrel.barrelType)' barrel cannot be deleted")
			}
			// delete and return 204
			return barrel.delete(on: req.db).transform(to: .noContent)
        }
    }

    /// `POST /api/v3/user/barrels/ID/add/STRING`
    ///
    /// Adds an item (either UUID or String) to the specified `Barrel`.
    ///
    /// - Note: This endpoint can only be used to add to a user-owned `Barrel` of type
    ///   `.seamonkey` or `.userWords`. All other types have their own dedicated endpoints for
    ///   content modification.
    ///
    /// - Parameter barrelID: In URL path. The target barrel.
    /// - Parameter STRING: In URL path. The value to add to the barrel.
    /// - Throws: 400 error if the barrel type is not supported by the endpoint. 403 error if
    ///   the barrel is not owned by the user. 404 or 500 error if the specified ID value is
    ///   invalid.
    /// - Returns: <doc:BarrelData> containing the updated contents of the barrel.
    func barrelAddHandler(_ req: Request) throws -> EventLoopFuture<BarrelData> {
        let user = try req.auth.require(User.self)
		let userID = try user.requireID()
        let param = req.parameters.get("string")
        guard let parameter = param else {
        	throw Abort(.badRequest, reason: "No string to barrel found in request.")
        }
        // get barrel
        return Barrel.findFromParameter(barrelIDParam, on: req).addModelID().throwingFlatMap { (barrel, barrelID) in
			guard barrel.ownerID == userID else {
				throw Abort(.forbidden, reason: "user is not owner of barrel")
			}
			// only user-created types can be added to here
			let userTypes: [BarrelType] = [.seamonkey, .userWords]
			guard userTypes.contains(barrel.barrelType) else {
				throw Abort(.badRequest, reason: "'\(barrel.barrelType)' barrel cannot be modified with this endpoint")
			}
			// get parameter
			switch barrel.barrelType {
				// add UUID if valid user.id
				case .seamonkey:
					guard let uuid = UUID(parameter) else {
						throw Abort(.badRequest, reason: "parameter '\(parameter)' is not a UUID")
					}
					_ = User.find(uuid, on: req.db)
						.unwrap(or: Abort(.badRequest, reason: "'\(uuid)' is not a valid user ID"))
					barrel.modelUUIDs.append(uuid)
				// else add string
				default:
					var userWords = barrel.userInfo["userWords"] ?? []
					userWords.append(parameter)
					barrel.userInfo.updateValue(userWords.sorted(), forKey: "userWords")
			}
			return barrel.save(on: req.db).flatMap { (_) in
				// return as BarrelData
				var barrelData = BarrelData(barrelID: barrelID, name: barrel.name, seamonkeys: [], stringList: [])
				// populate .stringList
				switch barrel.barrelType {
					case .userWords:
						barrelData.stringList = barrel.userInfo["userWords"]
					default:
						barrelData.stringList = nil
				}
				// populate .seamonkeys
				return User.query(on: req.db)
						.filter(\.$id ~~ barrel.modelUUIDs)
						.sort(\.$username, .ascending)
						.all()
						.flatMapThrowing { (users) in
					barrelData.seamonkeys = try users.map { try UserHeader(user: $0) }
					return barrelData
				}
			}
        }
    }
    
    /// `POST /api/v3/user/barrels/ID/remove/STRING`
    ///
    /// Removes an item (either UUID or String) from the specified `Barrel`.
    ///
    /// - Note: This endpoint can only be used to remove from a user-owned `Barrel` of type
    ///   `.seamonkey` or `.userWords`. All other types have their own dedicated endpoints for
    ///   content modification.
    ///
    /// - Parameter barrelID: In URL path. The target barrel.
    /// - Parameter STRING: In URL path. The value to remove from the barrel.
    /// - Throws: 400 error if the barrel type is not supported by the endpoint. 403 error if
    ///   the barrel is not owned by the user. 404 or 500 error if the specified ID value is
    ///   invalid.
    /// - Returns: <doc:BarrelData> containing the updated contents of the barrel.
    func barrelRemoveHandler(_ req: Request) throws -> EventLoopFuture<BarrelData> {
        let user = try req.auth.require(User.self)
        let param = req.parameters.get("string")
        guard let parameter = param else {
        	throw Abort(.badRequest, reason: "No alert word to add found in request.")
        }
        // get barrel
        return Barrel.findFromParameter(barrelIDParam, on: req).addModelID().flatMap { (barrel, barrelID) in
			do {
            guard try barrel.ownerID == user.requireID() else {
                throw Abort(.forbidden, reason: "user is not owner of barrel")
            }
            // only user types can be added to here
            let userTypes: [BarrelType] = [.seamonkey, .userWords]
            guard userTypes.contains(barrel.barrelType) else {
                throw Abort(
                    .badRequest,
                    reason: "'\(barrel.barrelType)' barrel cannot be modified with this endpoint"
                )
            }
            // get parameter
            switch barrel.barrelType {
                // remove UUID if found
                case .seamonkey:
                    guard let uuid = UUID(parameter) else {
                        throw Abort(.badRequest, reason: "parameter '\(parameter)' is not a UUID")
                    }
                    guard let index = barrel.modelUUIDs.firstIndex(of: uuid) else {
                        throw Abort(.badRequest, reason: "'\(uuid)' is not in barrel")
                    }
                    barrel.modelUUIDs.remove(at: index)
                // else remove string if found
                default:
                    var userWords = barrel.userInfo["userWords"] ?? []
                    guard let index = userWords.firstIndex(of: parameter) else {
                        throw Abort(.badRequest, reason: "'\(parameter)' is not in barrel")
                    }
                    userWords.remove(at: index)
                    barrel.userInfo.updateValue(userWords.sorted(), forKey: "userWords")
            }
            return barrel.save(on: req.db).flatMap { (_) in
                // return as BarrelData
                var barrelData = BarrelData(
                    barrelID: barrelID,
                    name: barrel.name,
                    seamonkeys: [],
                    stringList: []
                )
                // populate .stringList
                switch barrel.barrelType {
                    case .userWords:
                        barrelData.stringList = barrel.userInfo["userWords"]
                    default:
                        barrelData.stringList = nil
                }
                // populate .seamonkeys
                let uuids = barrel.modelUUIDs
                return User.query(on: req.db)
                    .filter(\.$id ~~ uuids)
                    .sort(\.$username, .ascending)
                    .all()
                    .flatMapThrowing { (users) in
                        barrelData.seamonkeys = try users.map { try UserHeader(user: $0) }
                        return barrelData
                }
            }
			}
			catch {
				return req.eventLoop.makeFailedFuture(error)
			}
        }
    }

    /// `POST /api/v3/user/barrels/ID/rename/STRING`
    ///
    /// Renames the specified `Barrel`.
    ///
	/// - Parameter barrelID: In URL path. The target barrel.
	/// - Parameter STRING: In URL path. The new name for the barrel.
    /// - Throws: 400 error if the barrel type is not supported by the endpoint. 403 error if
    ///   the barrel is not owned by the user. 404 or 500 error if the specified ID value is
    ///   invalid.
    /// - Returns: <doc:BarrelData> containing the updated barrel data.
    func renameBarrelHandler(_ req: Request) throws -> EventLoopFuture<BarrelData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		let param = req.parameters.get("barrel_name")
        guard let newBarrelName = param else {
        	throw Abort(.badRequest, reason: "No barrel name found in request.")
        }
        // get barrel
        return Barrel.findFromParameter(barrelIDParam, on: req).addModelID().flatMap { (barrel, barrelID) in
            guard barrel.ownerID == userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user is not owner of barrel"))
            }
            // only user types can be renamed
            let userTypes: [BarrelType] = [.seamonkey, .userWords]
            guard userTypes.contains(barrel.barrelType) else {
                return req.eventLoop.makeFailedFuture(
                		Abort(.badRequest, reason: "'\(barrel.barrelType)' barrel cannot be renamed"))
            }
            // get parameter
            barrel.name = newBarrelName
            return barrel.save(on: req.db).flatMap { (_) in
                // return as BarrelData
                var barrelData = BarrelData(
                    barrelID: barrelID,
                    name: barrel.name,
                    seamonkeys: [],
                    stringList: []
                )
                // populate .stringList
                switch barrel.barrelType {
                    case .userWords:
                        barrelData.stringList = barrel.userInfo["userWords"]
                    default:
                        barrelData.stringList = nil
                }
                // populate .seamonkeys
                return User.query(on: req.db)
						.filter(\.$id ~~ barrel.modelUUIDs)
						.sort(\.$username, .ascending)
						.all()
						.flatMapThrowing { (users) in
					barrelData.seamonkeys = try users.map { try UserHeader(user: $0) }
					return barrelData
                }
            }
        }
    }

    /// `GET /api/v3/user/barrels/ID`
    ///
    /// Returns the specified `Barrel`'s data as <doc:BarrelData>.
    ///
    /// - Parameter barrelID: In URL path. The target barrel.
    /// - Throws: 400 error if the barrel type is not supported by the endpoint. 403 error if
    ///   the barrel is not owned by the user. 404 or 500 error if the specified ID value is
    ///   invalid.
    /// - Returns: <doc:BarrelData> containing the barrel's ID, name, and contents.
    func barrelHandler(_ req: Request) throws -> EventLoopFuture<BarrelData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get barrel
        return Barrel.findFromParameter(barrelIDParam, on: req).addModelID().flatMap { (barrel, barrelID) in
            guard barrel.ownerID == userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user is not owner of barrel"))
            }
            // only user types can be retrieved here
            let userTypes = UserController.userBarrelTypes
            guard userTypes.contains(barrel.barrelType) else {
                return req.eventLoop.makeFailedFuture(Abort( .badRequest,
                    reason: "'\(barrel.barrelType)' barrel cannot be retrieved by this endpoint"))
            }
            // retrun as BarrelData
            var barrelData = BarrelData(barrelID: barrelID, name: barrel.name, seamonkeys: [], stringList: [])
            // populate .stringList
            switch barrel.barrelType {
                case .keywordAlert:
                    barrelData.stringList = barrel.userInfo["alertWords"]
                case .keywordMute:
                    barrelData.stringList = barrel.userInfo["muteWords"]
                case .userWords:
                    barrelData.stringList = barrel.userInfo["userWords"]
                default:
                    barrelData.stringList = nil
            }
            // populate .seamonkeys
            return User.query(on: req.db)
					.filter(\.$id ~~ barrel.modelUUIDs)
					.sort(\.$username, .ascending)
					.all()
					.flatMapThrowing { (users) in
				barrelData.seamonkeys = try users.map { try UserHeader(user: $0) }
				return barrelData
            }
        }
    }

    /// `GET /api/v3/user/barrels`
    ///
    /// Returns a list of all the user's barrels.
    ///
    /// - Note: This does not return *all* barrels for which the user is the `ownerID`, just
    ///   the default barrels and any .seamonkey or .userWords types they have created.
    ///
    /// - Returns: An array of <doc:BarrelListData> containing the barrel IDs and names.
    func barrelsHandler(_ req: Request) throws -> EventLoopFuture<[BarrelListData]> {
        let user = try req.auth.require(User.self)
        // get user's barrels, sorted by name
        let userTypes = UserController.userBarrelTypes
        return try Barrel.query(on: req.db)
				.filter(\.$ownerID == user.requireID())
				.filter(\.$barrelType ~~ userTypes)
				.sort(\.$name, .ascending)
				.all()
				.flatMapThrowing { (barrels) in
			// apply .barrelType sort
			let sortedBarrels = barrels.sorted(by: { $0.barrelType < $1.barrelType })
			// return as BarrelListData
			return try sortedBarrels.map {
				try BarrelListData(barrelID: $0.requireID(), name: $0.name)
			}
        }
    }

    /// `GET /api/v3/user/barrels/seamonkey`
    ///
    /// Returns a list of all the user's `.seamonkey` type barrels.
    ///
    /// - Note: While it can have other uses, this is primarily intended to provide easy
    ///   access to user-defined filters on public content and recipient groups when
    ///   initiating a `SeaMailThread`.
    ///
    /// - Returns: An array of <doc:BarrelListData> containing the barrel IDs and names.
    func seamonkeyBarrelsHandler(_ req: Request) throws -> EventLoopFuture<[BarrelListData]> {
        let user = try req.auth.require(User.self)
        // get user's seamonkey barrels, sorted by name
        return try Barrel.query(on: req.db)
				.filter(\.$ownerID == user.requireID())
				.filter(\.$barrelType == .seamonkey)
				.sort(\.$name, .ascending)
				.all()
				.flatMapThrowing { (barrels) in
			// convert to BarrelListData and return
			return try barrels.map {
				try BarrelListData(barrelID: $0.requireID(), name: $0.name)
			}
        }
    }

// MARK: - Blocks
    /// `GET /api/v3/user/blocks`
    ///
    /// Returns a list of the user's currently blocked users in <doc:BlockedUserData> format.
    /// If the user is a sub-account, the parent user's blocks are returned.
    ///
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:BlockedUserData> containing the currently blocked users as an array of <doc:UserHeader>.
    func blocksHandler(_ req: Request) throws -> EventLoopFuture<BlockedUserData> {
        let user = try req.auth.require(User.self)
        // if sub-account, we want parent's blocks
        let barrelUserID = try user.parentAccountID()
		// get blocks barrel
		return Barrel.query(on: req.db)
				.filter(\.$ownerID == barrelUserID)
				.filter(\.$barrelType == .userBlock)
				.first()
				.map { barrel in
			if let blockBarrel = barrel {
				// return as BlockedUserData
				let blockedUserHeaders = req.userCache.getHeaders(blockBarrel.modelUUIDs).sorted { $0.username < $1.username }
				return BlockedUserData(name: blockBarrel.name, blockedUsers: blockedUserHeaders)
			}
			else {
				return BlockedUserData(name: "Blocked Users", blockedUsers: [])
			}
        }
    }
    
// MARK: - Muted Users
    /// `GET /api/v3/user/mutes`
    ///
    /// Returns a list of the user's currently muted users in `MutedUserData` format.
    ///
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:MutedUserData> containing the currently muted users as an array of <doc:SeaMonkey>.
    func mutesHandler(_ req: Request) throws -> EventLoopFuture<MutedUserData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // Retrieve mutes barrel. Create a dummy one if the user doesn't already have one.
        // We don't need to save it since that will happen when the user adds a word to it.
        return try Barrel.query(on: req.db)
				.filter(\.$ownerID == user.requireID())
				.filter(\.$barrelType == .userMute)
				.first()
				.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .userMute))
				.map { (barrel) in
			// return as MutedUserData
			let mutedUserHeaders = req.userCache.getHeaders(barrel.modelUUIDs).sorted { $0.username < $1.username }
			return MutedUserData(name: barrel.name, mutedUsers: mutedUserHeaders)
        }
    }

// MARK: - Mutewords
	/// `POST /api/v3/user/mutewords/add/STRING`
	///
	/// Adds a string to the user's "Muted Keywords" barrel.
	///
	/// - Parameter STRING: In URL path. The muteword to add.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:MuteKeywordData> containing the updated contents of the barrel.
    func mutewordsAddHandler(_ req: Request) throws -> EventLoopFuture<MuteKeywordData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let param = req.parameters.get(mutewordParam.paramString)
        guard let parameter = param else {
        	throw Abort(.badRequest, reason: "No mute word to add found in request.")
        }
        // Get mutewords barrel. Create a dummy one if the user doesn't already have one.
        // We don't need to save it since that will happen when the user adds a word to it.
        return try Barrel.query(on: req.db)
				.filter(\.$ownerID == user.requireID())
				.filter(\.$barrelType == .keywordMute)
				.first()
				.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .keywordMute))
				.flatMap { (barrel) in
			// add string
			var muteWords = barrel.userInfo["muteWords"] ?? []
			muteWords.append(parameter)
			barrel.userInfo.updateValue(muteWords.sorted(), forKey: "muteWords")
			return barrel.save(on: req.db).flatMap { (_) in
				// return sorted list
				let muteKeywordData = MuteKeywordData(name: barrel.name, keywords: muteWords.sorted())
				return req.userCache.updateUser(userID).transform(to: muteKeywordData)
			}
        }
    }
    
	/// `GET /api/v3/user/mutewords`
	///
	/// Returns a list of the user's currently muted keywords in named-list  <doc:MuteKeywordData> format.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:MuteKeywordData> containing the current muting keywords as an array of  strings.
    func mutewordsHandler(_ req: Request) throws -> EventLoopFuture<MuteKeywordData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // Get mutewords barrel. Create a dummy one if the user doesn't already have one.
        // We don't need to save it since that will happen when the user adds a word to it.
        return try Barrel.query(on: req.db)
				.filter(\.$ownerID == user.requireID())
				.filter(\.$barrelType == .keywordMute)
				.first()
				.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .keywordMute))
				.map { (barrel) in
			// return as MuteKeywordData
			let muteKeywordData = MuteKeywordData(name: barrel.name, keywords: barrel.userInfo["muteWords"] ?? [])
			return muteKeywordData
        }
    }
    
	/// `POST /api/v3/user/mutewords/remove/STRING`
	///
	/// Removes a string from the user's "Muted Keywords" barrel.
	///
	/// - Parameter STRING: In URL path. The muteword to remove.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: <doc:MuteKeywordData> containing the updated contents of the barrel.
    func mutewordsRemoveHandler(_ req: Request) throws -> EventLoopFuture<MuteKeywordData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let param = req.parameters.get(mutewordParam.paramString)
        guard let parameter = param else {
        	throw Abort(.badRequest, reason: "No mute word to remove found in request.")
        }
        // get barrel
        return try Barrel.query(on: req.db)
				.filter(\.$ownerID == user.requireID())
				.filter(\.$barrelType == .keywordMute)
				.first()
				.unwrap(or: Abort(.internalServerError, reason: "muted keywords barrel not found"))
				.flatMap { (barrel) in
			// remove string
			var muteWords = barrel.userInfo["muteWords"] ?? []
			guard let index = muteWords.firstIndex(of: parameter) else {
				return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "'\(parameter)' is not in barrel"))
			}
			_ = muteWords.remove(at: index)
			barrel.userInfo.updateValue(muteWords.sorted(), forKey: "muteWords")
			return barrel.save(on: req.db).flatMap { (_) in
				// return sorted list
				let muteKeywordData = MuteKeywordData(name: barrel.name, keywords: muteWords.sorted())
				return req.userCache.updateUser(userID).transform(to: muteKeywordData)
			}
        }
    }
        
    /// `GET /api/v3/user/notes`
    ///
    /// Retrieves all <doc:UserNote>s owned by the current user, as an array of <doc:NoteData> objects.
    ///
    /// The <doc:NoteData> object is intended to be display friendly, including fields for
    /// potential sorting, the ID of the profile which can be linked to, and the profile's user
    /// in the familiar .displayedName format. The .noteID is included as well to support
    /// editing of notes outside of a profile-viewing context.
    ///
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: An array of  <doc:NoteData> containing all of the user's notes.
    func notesHandler(_ req: Request) throws -> EventLoopFuture<[NoteData]> {
        // FIXME: account for blocks, banned user
        let user = try req.auth.require(User.self)
        // get all notes, and for each note, the user the note's written about.
        return user.$notes.query(on: req.db).with(\.$noteSubject).with(\.$noteSubject).all().flatMapThrowing { (notes) in
            // create array for return
			let notesData: [NoteData] = try notes.map { try NoteData(note: $0, targetUser: $0.noteSubject) }
            return notesData
		}
    }
    
    // MARK: - Helper Functions
        
    /// Create the default `Barrel`s for a user: blocked users, muted users, alert keywords and
    /// muted keywords. A `.userBlock` barrel is only created for primary accounts; a sub-account
    /// is covered by its parent's block list.
    ///
    /// - Parameters:
    ///   - user: The owning `User` of the default barrels.
    ///   - req: The incoming request `Container` of the calling handler.
    /// - Returns: Void.
    func createDefaultBarrels(for user: User, on db: Database) -> EventLoopFuture<Void> {
		do {
			var barrels: [EventLoopFuture<Barrel>] = .init()
			let alertKeywordsBarrel = try Barrel(
				ownerID: user.requireID(),
				barrelType: .keywordAlert,
				name: "Alert Keywords"
			)
			alertKeywordsBarrel.userInfo.updateValue([], forKey: "alertWords")
			barrels.append(alertKeywordsBarrel.save(on: db).transform(to: alertKeywordsBarrel))
			// sub-accounts don't own block lists, they're covered by the parent's
			if user.parent == nil {
				let blocksBarrel = try Barrel(
					ownerID: user.requireID(),
					barrelType: .userBlock,
					name: "Blocked Users"            )
				barrels.append(blocksBarrel.save(on: db).transform(to: blocksBarrel))
			}
			let mutesBarrel = try Barrel(
				ownerID: user.requireID(),
				barrelType: .userMute,
				name: "Muted Users"
			)
			barrels.append(mutesBarrel.save(on: db).transform(to: mutesBarrel))
			let muteKeywordsBarrel = try Barrel(
				ownerID: user.requireID(),
				barrelType: .keywordMute,
				name: "Muted Keywords"
			)
			muteKeywordsBarrel.userInfo.updateValue([], forKey: "muteWords")
			barrels.append(muteKeywordsBarrel.save(on: db).transform(to: muteKeywordsBarrel))
			// resolve futures, return void
			return barrels.flatten(on: db.eventLoop).transform(to: ())
		}
		catch {
			return db.eventLoop.makeFailedFuture(error)
		}
    }

    /// Generates a recovery key of 3 words randomly chosen from `words` array.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 500 error if the randomizer fails.
    /// - Returns: A recoveryKey string.
    static func generateRecoveryKey(on req: Request) throws -> EventLoopFuture<String> {
        guard let word1 = words.randomElement(),
            let word2 = words.randomElement(),
            let word3 = words.randomElement() else {
                throw Abort(.internalServerError, reason: "could not generate recovery key")
        }
        let recoveryKey = word1 + " " + word2 + " " + word3
        return req.eventLoop.future(recoveryKey)
    }
}

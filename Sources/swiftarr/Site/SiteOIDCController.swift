import Vapor
import Fluent
import JWT
import Crypto

// Reference the OAuthClientData from OAuthControllerStructs.swift

// Response structure for redirects
fileprivate struct RedirectResponse: Content {
	var redirectTo: String
}

struct SiteOIDCController: SiteControllerUtils {
	func registerRoutes(_ app: Application) throws {
		// Create a dedicated CORS configuration for OIDC routes
		let oidcCorsConfig = CORSMiddleware.Configuration(
			allowedOrigin: .all,
			allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
			allowedHeaders: [
				.accept, .authorization, .contentType, .origin, .xRequestedWith, .userAgent, .accessControlAllowOrigin,
			],
		)
		let oidcCorsMiddleware = CORSMiddleware(configuration: oidcCorsConfig)
		
		// Authorization endpoint needs session middleware
		let authRoutes = app.grouped([
			oidcCorsMiddleware, // Apply CORS middleware first
			app.sessions.middleware,
			UserCacheData.SessionAuth(),
			Token.authenticator(),
			UserCacheData.TokenAuthenticator()
		])
		
		// OIDC authorization consent page
		authRoutes.get("oidc", "authorize", use: authorizeHandler)
		authRoutes.post("oidc", "authorize", use: authorizePostHandler)
	}
	
	// GET /oidc/authorize - Display authorization consent page OR handle the authorization directly
	func authorizeHandler(_ req: Request) async throws -> Response {
		// Extract all the OAuth parameters from the query string
		guard let clientID = req.query[String.self, at: "client_id"],
			  let redirectURI = req.query[String.self, at: "redirect_uri"],
			  let responseType = req.query[String.self, at: "response_type"] else {
			throw Abort(.badRequest, reason: "Missing required parameters")
		}
		
		// Check if the user is authenticated
		let authenticatedUser: Any
		if let userCache = req.auth.get(UserCacheData.self) {
			authenticatedUser = userCache
		} else if let user = req.auth.get(User.self) {
			authenticatedUser = user
		} else {
			// If not authenticated, store the URL and redirect to login
			let fullURI = req.url.string
			req.session.data["returnAfterLogin"] = fullURI
			// For GET requests, use traditional 303 redirect
			return req.redirect(to: "/login")
		}
		
		req.logger.debug("OIDC Consent - Attempting to fetch client with ID: \(clientID)")
		
		// First try direct database lookup as a fallback
		let allClients = try await OAuthClient.query(on: req.db).all()
		req.logger.debug("OIDC Consent - Found \(allClients.count) total clients in the database")
		
		// Try to find a matching client by clientId field
		guard let oauthClient = allClients.first(where: { $0.clientId == clientID }) else {
			req.logger.error("OIDC Consent - No matching client found with ID: \(clientID)")
			throw Abort(.badRequest, reason: "Invalid OAuth client - client not found")
		}
		
		req.logger.debug("OIDC Consent - Found client directly: \(oauthClient.name) with ID: \(oauthClient.clientId)")
		
		// Convert to OAuthClientData
		let client = try OAuthClientData(oauthClient)
		
		// Validate the redirect URI is allowed for this client
		let allowedRedirects = oauthClient.redirectURIs.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		guard allowedRedirects.contains(redirectURI) else {
			throw Abort(.badRequest, reason: "Invalid redirect URI")
		}
		
		// Get scope (optional with default)
		let scope = req.query[String.self, at: "scope"] ?? "openid"
		
		// Get state (optional parameter but recommended)
		let state = req.query[String.self, at: "state"]
		
		// Get optional PKCE and nonce parameters
		let codeChallenge = req.query[String.self, at: "code_challenge"]
		let codeChallengeMethod = req.query[String.self, at: "code_challenge_method"] ?? "plain"
		let nonce = req.query[String.self, at: "nonce"]
		
		// Check if requested scope is allowed for this client
		let requestedScopes = scope.split(separator: " ").map(String.init)
		let allowedScopes = oauthClient.scopes.split(separator: " ").map(String.init)
		
		// Validate each requested scope against allowed scopes
		do {
			try validateScopes(requested: requestedScopes, allowed: allowedScopes)
		} catch let error as ScopeValidationError {
			// Build error redirect with proper OAuth error parameters
			var components = URLComponents(string: redirectURI)!
			var queryItems = components.queryItems ?? []
			queryItems.append(URLQueryItem(name: "error", value: "invalid_scope"))
			queryItems.append(URLQueryItem(name: "error_description", value: error.description))
			if let state = state {
				queryItems.append(URLQueryItem(name: "state", value: state))
			}
			components.queryItems = queryItems
			
			// For GET requests, use traditional 303 redirect
			return req.redirect(to: components.string ?? redirectURI)
		}
		
		// Check if there's an existing grant for this user and client with the same or broader scopes
		let userID: UUID
		if let userCache = authenticatedUser as? UserCacheData {
			userID = userCache.userID
		} else if let user = authenticatedUser as? User {
			userID = try user.requireID()
		} else {
			userID = try await getUserID(from: authenticatedUser, on: req.db)
		}
		
		let clientID_UUID = try oauthClient.requireID()
		
		// Look for an existing grant
		let grants = try await OAuthGrant.query(on: req.db)
			.filter(\OAuthGrant.$client.$id == clientID_UUID)
			.filter(\OAuthGrant.$user.$id == userID)
			.all()
			
		if let existingGrant = grants.first {
			req.logger.debug("OIDC Consent - Found existing grant for user \(userID) and client \(clientID)")
			
			// Check if the existing grant covers all the requested scopes
			if existingGrant.coversScopes(scope) {
				req.logger.debug("OIDC Consent - Existing grant covers all requested scopes, auto-approving")
				
				// Process the authorization code directly
				return try await processAuthorization(req, client: oauthClient, userID: userID, 
					redirectURI: redirectURI, responseType: responseType, scope: scope, 
					state: state, codeChallenge: codeChallenge, codeChallengeMethod: codeChallengeMethod, nonce: nonce)
			}
			
			req.logger.debug("OIDC Consent - Existing grant doesn't cover all requested scopes, showing consent page")
		}
		
		// We've already parsed the scopes earlier for validation
		
		// Create context for the view
		struct OAuthConsentContext: Encodable {
			var trunk: TrunkContext
			var client: OAuthClientData
			var scopes: [String]
			var scopeDetails: [ScopeDetail]
			var queryParams: String
			
			struct ScopeDetail: Encodable {
				var id: String
				var displayName: String
				var description: String
			}
			
			init(_ req: Request, client: OAuthClientData, scopes: [String]) throws {
				trunk = .init(req, title: "Authorize Application", tab: .none)
				self.client = client
				self.scopes = scopes
				
				// Convert scope strings to ScopeDetail objects
				self.scopeDetails = scopes.compactMap { scopeString in
					if let scope = OAuthScope(rawValue: scopeString) {
						return ScopeDetail(
							id: scope.rawValue,
							displayName: scope.displayName,
							description: scope.description
						)
					}
					return nil
				}
				
				// Reconstruct the original query parameters to preserve them for the form submission
				var components = URLComponents()
				var queryItems: [URLQueryItem] = []
				
				if let clientID = req.query[String.self, at: "client_id"] {
					queryItems.append(URLQueryItem(name: "client_id", value: clientID))
				}
				if let redirectURI = req.query[String.self, at: "redirect_uri"] {
					queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectURI))
				}
				if let responseType = req.query[String.self, at: "response_type"] {
					queryItems.append(URLQueryItem(name: "response_type", value: responseType))
				}
				if let state = req.query[String.self, at: "state"] {
					queryItems.append(URLQueryItem(name: "state", value: state))
				}
				if let scope = req.query[String.self, at: "scope"] {
					queryItems.append(URLQueryItem(name: "scope", value: scope))
				}
				if let codeChallenge = req.query[String.self, at: "code_challenge"] {
					queryItems.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
				}
				if let codeChallengeMethod = req.query[String.self, at: "code_challenge_method"] {
					queryItems.append(URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod))
				}
				if let nonce = req.query[String.self, at: "nonce"] {
					queryItems.append(URLQueryItem(name: "nonce", value: nonce))
				}
				
				components.queryItems = queryItems
				self.queryParams = components.query ?? ""
			}
		}
		
		let ctx = try OAuthConsentContext(req, client: client, scopes: requestedScopes)
		// Render the view and encode it as a response
		let futureResponse = req.view.render("oidc/authorize", ctx).encodeResponse(for: req)
		// Wait for the future to complete
		let response = try await futureResponse.get()
		
		return response
	}
	
	// POST /oidc/authorize - Process authorization consent decision
	func authorizePostHandler(_ req: Request) async throws -> Response {
		// Extract decision from form
		struct AuthorizeFormData: Content {
			var decision: String // "accept" or "decline"
			var queryParams: String // Original query parameters
		}
		
		let formData = try req.content.decode(AuthorizeFormData.self)
		
		// Parse the query parameters
		var components = URLComponents()
		components.query = formData.queryParams
		let queryItems = components.queryItems ?? []
		
		// Extract parameters from query components
		func getQueryParam(_ name: String) -> String? {
			return queryItems.first(where: { $0.name == name })?.value
		}
		
		guard let clientID = getQueryParam("client_id"),
			  let redirectURI = getQueryParam("redirect_uri"),
			  let responseType = getQueryParam("response_type") else {
			throw Abort(.badRequest, reason: "Missing required parameters")
		}
		
		// Extract other parameters
		let state = getQueryParam("state")
		let scope = getQueryParam("scope") ?? "openid"
		let codeChallenge = getQueryParam("code_challenge")
		let codeChallengeMethod = getQueryParam("code_challenge_method") ?? "plain"
		let nonce = getQueryParam("nonce")
		
		// Check user's decision
		if formData.decision == "accept" {
			// User accepted, proceed with authorization
			
			// Get the authenticated user
			let authenticatedUser: Any
			if let userCache = req.auth.get(UserCacheData.self) {
				authenticatedUser = userCache
			} else if let user = req.auth.get(User.self) {
				authenticatedUser = user
			} else {
				throw Abort(.unauthorized, reason: "User authentication required")
			}
			
			// Get the OAuth client
			let oauthClients = try await OAuthClient.query(on: req.db)
				.filter(\OAuthClient.$clientId == clientID)
				.all()
				
			guard let oauthClient = oauthClients.first else {
				throw Abort(.badRequest, reason: "Invalid client")
			}
			
			// Check if requested scope is allowed for this client
			let requestedScopes = scope.split(separator: " ").map(String.init)
			let allowedScopes = oauthClient.scopes.split(separator: " ").map(String.init)
			
			// Validate each requested scope against allowed scopes
			do {
				try validateScopes(requested: requestedScopes, allowed: allowedScopes)
			} catch let error as ScopeValidationError {
				// Build error redirect with proper OAuth error parameters
				var components = URLComponents(string: redirectURI)!
				var queryItems = components.queryItems ?? []
				queryItems.append(URLQueryItem(name: "error", value: "invalid_scope"))
				queryItems.append(URLQueryItem(name: "error_description", value: error.description))
				if let state = state {
					queryItems.append(URLQueryItem(name: "state", value: state))
				}
				components.queryItems = queryItems
				
				// For GET requests, use traditional 303 redirect
				return req.redirect(to: components.string ?? redirectURI)
			}
			
			// Get the user ID
			let userID: UUID
			if let userCache = authenticatedUser as? UserCacheData {
				userID = userCache.userID
			} else if let user = authenticatedUser as? User {
				userID = try user.requireID()
			} else {
				userID = try await getUserID(from: authenticatedUser, on: req.db)
			}
			
			let clientID_UUID = try oauthClient.requireID()
			
			// Store the grant in the database
			// First check if a grant already exists for this client-user pair
			let grants = try await OAuthGrant.query(on: req.db)
				.filter(\OAuthGrant.$client.$id == clientID_UUID)
				.filter(\OAuthGrant.$user.$id == userID)
				.all()
				
			if let existingGrant = grants.first {
				// Update the existing grant with the new scopes (merge them)
				let existingScopes = Set(existingGrant.scopes.split(separator: " ").map { String($0) })
				let newScopes = Set(scope.split(separator: " ").map { String($0) })
				let mergedScopes = existingScopes.union(newScopes)
				
				existingGrant.scopes = mergedScopes.joined(separator: " ")
				try await existingGrant.save(on: req.db)
				
				req.logger.debug("OIDC Consent - Updated existing grant for user \(userID) and client \(clientID) with scopes: \(existingGrant.scopes)")
			} else {
				// Create a new grant
				let grant = OAuthGrant(clientID: clientID_UUID, userID: userID, scopes: scope)
				try await grant.save(on: req.db)
				
				req.logger.debug("OIDC Consent - Created new grant for user \(userID) and client \(clientID) with scopes: \(scope)")
			}
			
			// Process the authorization directly
			let response = try await processAuthorization(req, client: oauthClient, userID: userID, 
				redirectURI: redirectURI, responseType: responseType, scope: scope, 
				state: state, codeChallenge: codeChallenge, codeChallengeMethod: codeChallengeMethod, nonce: nonce)
			return response
			
		} else {
			// User declined, redirect with access_denied error
			var redirectComponents = URLComponents(string: redirectURI)!
			var redirectQueryItems = redirectComponents.queryItems ?? []
			redirectQueryItems.append(URLQueryItem(name: "error", value: "access_denied"))
			redirectQueryItems.append(URLQueryItem(name: "error_description", value: "The user declined to authorize the client"))
			if let state = state {
				redirectQueryItems.append(URLQueryItem(name: "state", value: state))
			}
			redirectComponents.queryItems = redirectQueryItems
			
			// If user declines, we redirect to the client's redirect URI with the error
			// Create JSON response with redirectTo URL instead of actual redirect
			let redirectResponse = RedirectResponse(redirectTo: redirectComponents.string ?? redirectURI)
			return try await redirectResponse.encodeResponse(for: req)
		}
	}
	
	// Process the authorization directly without redirecting to the API
	func processAuthorization(_ req: Request, client: OAuthClient, userID: UUID,
		redirectURI: String, responseType: String, scope: String, 
		state: String?, codeChallenge: String?, codeChallengeMethod: String?, nonce: String?) async throws -> Response {
		
		// Determine if this is a POST request (from authorizePostHandler) or a GET request (from authorizeHandler)
		let isPostRequest = req.method == .POST
		
		// Handle different response types
		switch responseType {
		case "code":
			// Authorization code flow
			// Generate an authorization code
			let code = UUID().uuidString
			
			// Store the code in the database
			let oauthCode = OAuthCode(
				code: code,
				clientID: try client.requireID(),
				userID: userID,
				redirectURI: redirectURI,
				scopes: scope,
				codeChallenge: codeChallenge,
				codeChallengeMethod: codeChallengeMethod,
				expiresAt: Date().addingTimeInterval(600), // 10 minutes expiration
				nonce: nonce
			)
			
			try await oauthCode.save(on: req.db)
			
			// Redirect back to the client with the code
			var components = URLComponents(string: redirectURI)!
			var queryItems = components.queryItems ?? []
			queryItems.append(URLQueryItem(name: "code", value: code))
			if let state = state {
				queryItems.append(URLQueryItem(name: "state", value: state))
			}
			components.queryItems = queryItems
			
			if isPostRequest {
				// If this is from the POST handler, return JSON with redirectTo
				req.logger.debug("OIDC Auth - Generated authorization code and returning JSON with redirect URL")
				let redirectResponse = RedirectResponse(redirectTo: components.string ?? redirectURI)
				return try await redirectResponse.encodeResponse(for: req)
			} else {
				// If this is from the GET handler (auto-grant), use 303 redirect
				req.logger.debug("OIDC Auth - Generated authorization code and redirecting client")
				return req.redirect(to: components.string ?? redirectURI)
			}
			
		case "token", "id_token", "id_token token", "code token", "code id_token", "code id_token token":
			// Implicit flow or hybrid flow - not fully implemented yet
			var components = URLComponents(string: redirectURI)!
			var queryItems = components.queryItems ?? []
			queryItems.append(URLQueryItem(name: "error", value: "unsupported_response_type"))
			queryItems.append(URLQueryItem(name: "error_description", value: "Implicit and hybrid flows are not yet supported"))
			if let state = state {
				queryItems.append(URLQueryItem(name: "state", value: state))
			}
			components.queryItems = queryItems
			
			if isPostRequest {
				// If this is from the POST handler, return JSON with redirectTo
				let redirectResponse = RedirectResponse(redirectTo: components.string ?? redirectURI)
				return try await redirectResponse.encodeResponse(for: req)
			} else {
				// If this is from the GET handler, use 303 redirect
				return req.redirect(to: components.string ?? redirectURI)
			}
			
		default:
			// Invalid response type
			var components = URLComponents(string: redirectURI)!
			var queryItems = components.queryItems ?? []
			queryItems.append(URLQueryItem(name: "error", value: "unsupported_response_type"))
			queryItems.append(URLQueryItem(name: "error_description", value: "Response type '\(responseType)' is not supported"))
			if let state = state {
				queryItems.append(URLQueryItem(name: "state", value: state))
			}
			components.queryItems = queryItems
			
			if isPostRequest {
				// If this is from the POST handler, return JSON with redirectTo
				let redirectResponse = RedirectResponse(redirectTo: components.string ?? redirectURI)
				return try await redirectResponse.encodeResponse(for: req)
			} else {
				// If this is from the GET handler, use 303 redirect
				return req.redirect(to: components.string ?? redirectURI)
			}
		}
	}
}

// MARK: - Helper Methods
extension SiteOIDCController {
	/// Helper method to extract user ID from any auth source (UserCacheData or User)
	func getUserID(from auth: Any, on db: FluentKit.Database) async throws -> UUID {
		if let userCache = auth as? UserCacheData {
			return userCache.userID
		} else if let user = auth as? User {
			return try user.requireID()
		} else if let username = auth as? String {
			// If we somehow got a string (username), try to look up the user
			let users = try await User.query(on: db)
				.filter(\User.$username == username)
				.all()
				
			if let cachedUser = users.first {
				return try cachedUser.requireID()
			}
		}
		
		throw Abort(.internalServerError, reason: "Could not determine user ID")
	}
}

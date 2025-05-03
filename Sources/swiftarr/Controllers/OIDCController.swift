import Foundation
import Vapor
import Fluent
import JWT
import Crypto
import JOSE

// Define a custom client credentials authenticator
struct OAuthClientAuthenticator: BasicAuthenticator {
	typealias User = OAuthClient
	
	func authenticate(basic: BasicAuthorization, for request: Request) -> EventLoopFuture<Void> {
		OAuthClient.query(on: request.db)
			.filter(\.$clientId == basic.username)
			.filter(\.$clientSecret == basic.password)
			.filter(\.$isEnabled == true)
			.first()
			.map { client in
				if let client = client {
					request.auth.login(client)
				}
			}
	}
}

/// The collection of `/oidc/*` route endpoints and handler functions related
/// to OpenID Connect (OIDC) functionality.
///
/// This controller implements the necessary endpoints for this application to act as an
/// OpenID Connect Identity Provider (IDP).
struct OIDCController: APIRouteCollection {
	
	// MARK: - Route Registration
	
	func registerRoutes(_ app: Application) throws {
		// convenience route group for all /oidc endpoints
		let oidcRoutes = app.grouped("oidc")
		
		// OpenID Connect discovery endpoint (no auth required)
		// The standard requires this endpoint at /.well-known/openid-configuration
		// so let's register both at the API path and at the root
		oidcRoutes.get(".well-known", "openid-configuration", use: openIDConfigurationHandler)
		app.get(".well-known", "openid-configuration", use: openIDConfigurationHandler)
		
		// Add debugging endpoint to check session/auth state
		let debugGroup = oidcRoutes.grouped(app.sessions.middleware)
		debugGroup.get("debug", use: debugHandler)
		
		// OAuth 2.0 / OIDC standard endpoints
		// Note: The authorize endpoint is now handled by SiteOIDCController
		oidcRoutes.post("token", use: tokenHandler)
		oidcRoutes.get("userinfo", use: userInfoHandler)
		oidcRoutes.post("userinfo", use: userInfoHandler)
		oidcRoutes.get("jwks", use: jwksHandler)
		
		// Client lookup endpoint for the site interface
		let clientParam = PathComponent(":client_id")
		oidcRoutes.get("client", clientParam, use: clientLookupHandler)
		app.logger.info("OIDC Routes - Registered client lookup endpoint: /oidc/client/:client_id")
		
		// Token introspection and revocation endpoints (client auth required)
		let clientAuthGroup = oidcRoutes.grouped(OAuthClientAuthenticator())
		clientAuthGroup.post("introspect", use: introspectHandler)
		clientAuthGroup.post("revoke", use: revokeHandler)
	}
	
	/// `GET /oidc/client/:client_id`
	///
	/// Retrieves client information by client ID for the site interface
	///
	/// - Parameter req: The HTTP request containing the client_id parameter
	/// - Returns: Client information or a 404 if the client doesn't exist
	func clientLookupHandler(_ req: Request) async throws -> OAuthClient {
		guard let clientID = req.parameters.get("client_id") else {
			req.logger.error("OIDC Debug - Client lookup missing client_id parameter")
			throw Abort(.badRequest, reason: "Missing client ID parameter")
		}
		
		req.logger.debug("OIDC Debug - Looking up client with ID: \(clientID)")
		
		// First try to list all clients to see what's available
		let allClients = try await OAuthClient.query(on: req.db).all()
		req.logger.debug("OIDC Debug - Found \(allClients.count) total clients in the database")
		
		for client in allClients {
			req.logger.debug("OIDC Debug - Client: \(client.name), ID: \(client.clientId), Enabled: \(client.isEnabled)")
		}
		
		// Look up the client
		let clientQuery = OAuthClient.query(on: req.db)
			.filter(\.$clientId == clientID)
		
		let matchingClients = try await clientQuery.all()
		req.logger.debug("OIDC Debug - Found \(matchingClients.count) clients matching ID: \(clientID)")
		
		// Add enabled filter
		guard let client = try await OAuthClient.query(on: req.db)
			.filter(\.$clientId == clientID)
			.filter(\.$isEnabled == true)
			.first() else {
			req.logger.error("OIDC Debug - Client \(clientID) not found or not enabled")
			throw Abort(.notFound, reason: "Client not found or not enabled")
		}
		
		req.logger.debug("OIDC Debug - Successfully found client: \(client.name) with ID: \(client.clientId)")
		return client
	}
	
	/// Debug endpoint to check authentication state
	/// GET /oidc/debug
	func debugHandler(_ req: Request) async throws -> Response {
		// Debug information
		let authenticatedUser = req.auth.get(UserCacheData.self)
		let authenticatedUserAlt = req.auth.get(User.self)
		
		// Session data
		let token = req.session.data["token"]
		let hasToken = token != nil
		let userID = req.session.data["userID"]
		let userName = req.session.data["username"]
		let headerAuth = req.headers.bearerAuthorization?.token ?? "none"
		let returnAfterLogin = req.session.data["returnAfterLogin"]
		
		// Create response data
		var debugInfo: [String: String] = [
			"session_has_token": "\(hasToken)",
			"session_token": token ?? "none",
			"session_user_id": userID ?? "none",
			"session_username": userName ?? "none",
			"session_return_after_login": returnAfterLogin ?? "none",
			"header_auth": headerAuth,
			"user_cache_data_auth": "\(authenticatedUser != nil)",
			"user_auth": "\(authenticatedUserAlt != nil)"
		]
		
		// Add more detailed user info if available
		if let user = authenticatedUser {
			debugInfo["user_cache_username"] = user.username
			debugInfo["user_cache_access_level"] = "\(user.accessLevel)"
			debugInfo["user_cache_user_id"] = "\(user.userID)"
		}
		
		if let user = authenticatedUserAlt {
			debugInfo["user_username"] = user.username
			debugInfo["user_access_level"] = "\(user.accessLevel)"
			if let userId = user.id {
				debugInfo["user_id"] = "\(userId)"
			}
		}
		
		// Add all session data for complete visibility
		// SessionData doesn't have a keys property, so we'll dump what we know
		debugInfo["session_has_return_url"] = "\(req.session.data["returnAfterLogin"] != nil)"
		
		// Add action parameter handling
		if let action = req.query[String.self, at: "action"] {
			if action == "logout" {
				req.session.destroy()
				debugInfo["action_performed"] = "Session destroyed"
			}
		}
		
		// Create response
		let response = Response(status: .ok)
		try response.content.encode(debugInfo)
		response.headers.contentType = .json
		return response
	}
	
	// MARK: - OpenID Connect Discovery
	
	/// `GET /.well-known/openid-configuration` or `/oidc/.well-known/openid-configuration`
	///
	/// Returns the OpenID Connect discovery document that describes the OIDC provider's configuration.
	/// This allows OIDC clients to automatically discover and use this server's configuration.
	///
	/// - Parameter req: The HTTP request
	/// - Returns: A Response with pretty-printed JSON describing this server's OIDC capabilities
	func openIDConfigurationHandler(_ req: Request) async throws -> Response {
		// Get base URL for the server to use in the configuration
		let baseURL = Settings.shared.canonicalServerURLComponents.string ?? "http://localhost:8081"
		let issuer = baseURL
		
		// Get available scopes from the enum
		let availableScopes = OAuthScope.allCases.map { $0.rawValue }.sorted()
		
		// Create the configuration with sorted arrays for stable output
		let config = OpenIDConfiguration(
			issuer: issuer,
			authorizationEndpoint: "\(baseURL)/oidc/authorize",
			tokenEndpoint: "\(baseURL)/oidc/token",
			userinfoEndpoint: "\(baseURL)/oidc/userinfo",
			jwksUri: "\(baseURL)/oidc/jwks",
			registrationEndpoint: nil, // Not implemented
			scopesSupported: availableScopes, // Use the scopes from our enum
			responseTypesSupported: ["code", "code id_token", "code token", "code token id_token", "id_token", "token", "token id_token"].sorted(),
			grantTypesSupported: ["authorization_code", "implicit", "refresh_token"].sorted(),
			subjectTypesSupported: ["public"].sorted(),
			idTokenSigningAlgValuesSupported: ["RS256"].sorted(),
			tokenEndpointAuthMethodsSupported: ["client_secret_basic", "client_secret_post"].sorted(),
			claimsSupported: ["email", "iss", "name", "picture", "preferred_username", "sub"].sorted(),
			codeChallengeMethodsSupported: ["S256", "plain"].sorted(),
			introspectionEndpoint: "\(baseURL)/oidc/introspect",
			revocationEndpoint: "\(baseURL)/oidc/revoke"
		)
		
		// Create a custom response with pretty-printed JSON
		let response = Response(status: .ok)
		response.headers.contentType = .json
		
		// Create a pretty-printing encoder
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		
		// Encode and set the body
		response.body = .init(data: try encoder.encode(config))
		
		return response
	}
	
	// MARK: - OAuth2/OIDC Core Endpoints
	
	/// `GET /oidc/authorize` is now handled by SiteOIDCController
	/// This API endpoint is no longer used
	
	/// `POST /oidc/token`
	///
	/// Handles token requests for the authorization code flow, refresh token flow,
	/// and client credentials flow.
	///
	/// - Parameter req: The HTTP request containing the token request
	/// - Returns: A TokenResponse containing access token, refresh token, and ID token if applicable
	func tokenHandler(_ req: Request) async throws -> TokenResponse {
		// Parse the token request
		guard let grantType = try? req.content.get(String.self, at: "grant_type") else {
			throw Abort(.badRequest, reason: "Missing grant_type parameter")
		}
		
		// Get client authentication
		let clientID: String?
		let clientSecret: String?
		
		if let basicAuth = req.headers.basicAuthorization {
			clientID = basicAuth.username
			clientSecret = basicAuth.password
		} else {
			clientID = try? req.content.get(String.self, at: "client_id")
			clientSecret = try? req.content.get(String.self, at: "client_secret")
		}
		
		guard let clientID = clientID else {
			throw Abort(.unauthorized, reason: "Client authentication required")
		}
		
		// Validate the client
		guard let client = try await OAuthClient.query(on: req.db)
			.filter(\.$clientId == clientID)
			.filter(\.$isEnabled == true)
			.first() else {
			throw Abort(.unauthorized, reason: "Invalid client")
		}
		
		// If client is confidential, validate the client secret
		if client.isConfidential {
			guard let clientSecret = clientSecret, client.clientSecret == clientSecret else {
				throw Abort(.unauthorized, reason: "Invalid client credentials")
			}
		}
		
		// Handle different grant types
		switch grantType {
		case "authorization_code":
			// Authorization code grant - exchange a code for tokens
			// Get required parameters
			guard let code = try? req.content.get(String.self, at: "code"),
				  let redirectURI = try? req.content.get(String.self, at: "redirect_uri") else {
				throw Abort(.badRequest, reason: "Missing required parameters for authorization_code grant")
			}
			
			// Optional PKCE code verifier
			let codeVerifier = try? req.content.get(String.self, at: "code_verifier")
			
			// Validate the authorization code
			guard let authCode = try await OAuthCode.query(on: req.db)
				.filter(\.$code == code)
				.filter(\.$isUsed == false)
				.with(\.$client)
				.with(\.$user)
				.first() else {
				throw Abort(.badRequest, reason: "Invalid authorization code")
			}
			
			// Check if the code has expired
			guard authCode.expiresAt > Date() else {
				// Mark the code as used to prevent replay attacks
				authCode.isUsed = true
				try await authCode.save(on: req.db)
				throw Abort(.badRequest, reason: "Authorization code has expired")
			}
			
			// Verify the client ID matches
			guard authCode.client.id == client.id else {
				throw Abort(.badRequest, reason: "Authorization code was not issued to this client")
			}
			
			// Verify the redirect URI matches
			guard authCode.redirectURI == redirectURI else {
				throw Abort(.badRequest, reason: "Redirect URI mismatch")
			}
			
			// Verify PKCE code challenge if provided
			if let codeChallenge = authCode.codeChallenge, let challengeMethod = authCode.codeChallengeMethod {
				guard let verifier = codeVerifier else {
					throw Abort(.badRequest, reason: "Code verifier required")
				}
				
				// Verify the code challenge based on the method
				var derivedChallenge: String
				if challengeMethod == "S256" {
					// SHA-256 hash of the code verifier
					let verifierData = Data(verifier.utf8)
					let hash = SHA256.hash(data: verifierData)
					derivedChallenge = Data(hash).base64URLEncodedString()
				}
				else {
					// Plain method - direct comparison
					derivedChallenge = verifier
				}
				
				guard derivedChallenge == codeChallenge else {
					throw Abort(.badRequest, reason: "Code verifier validation failed")
				}
			}
			
			// Mark the code as used
			authCode.isUsed = true
			try await authCode.save(on: req.db)
			
			// Generate tokens
			let accessToken = try OIDCHelper.generateSecureRandomString(length: 32)
			let refreshToken = try OIDCHelper.generateSecureRandomString(length: 32)
			
			// Log the access token for debugging
			req.logger.debug("Generated access token (auth code flow): \(accessToken)")
			
			// Calculate token expiration times
			let accessTokenLifetime: TimeInterval = 3600 // 1 hour
			let refreshTokenLifetime: TimeInterval = 2592000 // 30 days
			
			// Create and save the token
			let oauthToken = OAuthToken(
				accessToken: accessToken,
				refreshToken: refreshToken,
				clientID: try client.requireID(),
				userID: try authCode.user.requireID(),
				scopes: authCode.scopes,
				expiresAt: Date().addingTimeInterval(accessTokenLifetime),
				refreshTokenExpiresAt: Date().addingTimeInterval(refreshTokenLifetime)
			)
			try await oauthToken.save(on: req.db)
			
			// Generate ID Token if openid scope was requested
			var idToken: String? = nil
			if authCode.scopes.contains("openid") {
				struct IDTokenPayload: JWTPayload, Sendable {
					// Standard OpenID Connect claims
					let iss: String      // Issuer - URL of the token issuer
					let sub: String      // Subject - User identifier
					let aud: String      // Audience - Client ID
					let exp: Date        // Expiration time
					let iat: Date        // Issued at time
					let auth_time: Date? // Time when authentication occurred
					let nonce: String?   // Value used to associate client session with ID token
					let acr: String?     // Authentication context class reference
					let azp: String?     // Authorized party - client ID when different from audience
					
					// Optional claims based on requested scopes
					let name: String?             // Full name
					let preferred_username: String? // Username
					let email: String?            // Email address
					let email_verified: Bool?     // Whether email has been verified
					let picture: String?          // URL of profile picture
					
					// Required by JWT to verify the token
					func verify(using signer: JWTSigner) throws {
						// Verify that the token hasn't expired
						guard exp > Date() else {
							throw Abort(.unauthorized, reason: "Token has expired")
						}
					}
				}
				
				// Get base URL for the server to use as issuer
				let baseURL = Settings.shared.canonicalServerURLComponents.string ?? "http://localhost:8081"
				
				let userId = try authCode.user.requireID().uuidString
				
				// Determine if we have profile claims
				let includeProfile = authCode.scopes.contains("profile")
				let includeEmail = authCode.scopes.contains("email")
				
				// Create the user profile picture URL if available
				let pictureURL: String?
				if includeProfile, let userImage = authCode.user.userImage {
					pictureURL = "\(baseURL)/api/v3/image/user/\(userImage)"
				} else {
					pictureURL = nil
				}
				
				// Create payload with all standard OIDC claims
				let payload = IDTokenPayload(
					iss: baseURL,
					sub: userId,
					aud: client.clientId,
					exp: Date().addingTimeInterval(accessTokenLifetime),
					iat: Date(),
					auth_time: Date(), // Use current time as authentication time
					nonce: authCode.nonce,
					acr: "1",          // Basic authentication level
					azp: client.clientId,
					name: includeProfile ? authCode.user.displayName : nil,
					preferred_username: includeProfile ? authCode.user.username : nil,
					email: includeEmail ? authCode.user.email : nil,
					email_verified: includeEmail ? false : nil, // We don't verify emails currently
					picture: pictureURL
				)
				
				// Sign the token with our RSA key
				idToken = try await OIDCHelper.signToken(payload)
				
				// Log the token for debugging purposes
				req.logger.debug("Generated ID token (auth code flow): \(idToken ?? "nil")")
			}
			
			// Return the token response
			return TokenResponse(
				accessToken: accessToken,
				tokenType: "Bearer",
				expiresIn: Int(accessTokenLifetime),
				refreshToken: refreshToken,
				idToken: idToken,
				scope: authCode.scopes
			)
			
		case "refresh_token":
			// Refresh token grant - use a refresh token to get a new access token
			guard let refreshToken = try? req.content.get(String.self, at: "refresh_token") else {
				throw Abort(.badRequest, reason: "Missing refresh_token parameter")
			}
			
			// Validate the refresh token
			guard let token = try await OAuthToken.query(on: req.db)
				.filter(\.$refreshToken == refreshToken)
				.filter(\.$isRevoked == false)
				.with(\.$client)
				.with(\.$user)
				.first() else {
				throw Abort(.badRequest, reason: "Invalid refresh token")
			}
			
			// Check if the refresh token has expired
			guard let refreshTokenExpiresAt = token.refreshTokenExpiresAt,
				  refreshTokenExpiresAt > Date() else {
				// Mark the token as revoked
				token.isRevoked = true
				try await token.save(on: req.db)
				throw Abort(.badRequest, reason: "Refresh token has expired")
			}
			
			// Verify the client ID matches
			guard token.client.id == client.id else {
				throw Abort(.badRequest, reason: "Refresh token was not issued to this client")
			}
			
			// Generate new tokens
			let newAccessToken = UUID().uuidString
			let newRefreshToken = UUID().uuidString
			
			// Log the tokens for debugging
			req.logger.debug("Generated access token (refresh token flow): \(newAccessToken)")
			
			// Calculate token expiration times
			let accessTokenLifetime: TimeInterval = 3600 // 1 hour
			
			// Update token with new values
			token.accessToken = newAccessToken
			token.refreshToken = newRefreshToken
			token.expiresAt = Date().addingTimeInterval(accessTokenLifetime)
			// Keep the same refresh token expiration
			
			try await token.save(on: req.db)
			
			// Generate ID Token if openid scope was requested
			var idToken: String? = nil
			if token.scopes.contains("openid") {
				struct IDTokenPayload: JWTPayload, Sendable {
					// Standard OpenID Connect claims
					let iss: String      // Issuer - URL of the token issuer
					let sub: String      // Subject - User identifier
					let aud: String      // Audience - Client ID
					let exp: Date        // Expiration time
					let iat: Date        // Issued at time
					let auth_time: Date? // Time when authentication occurred
					let acr: String?     // Authentication context class reference
					let azp: String?     // Authorized party - client ID when different from audience
					
					// Optional claims based on requested scopes
					let name: String?             // Full name
					let preferred_username: String? // Username
					let email: String?            // Email address
					let email_verified: Bool?     // Whether email has been verified
					let picture: String?          // URL of profile picture
					
					// Required by JWT to verify the token
					func verify(using signer: JWTSigner) throws {
						// Verify that the token hasn't expired
						guard exp > Date() else {
							throw Abort(.unauthorized, reason: "Token has expired")
						}
					}
				}
				
				// Get base URL for the server to use as issuer
				let baseURL = Settings.shared.canonicalServerURLComponents.string ?? "http://localhost:8081"
				
				let userId = try token.user.requireID().uuidString
				
				// Determine if we have profile claims
				let includeProfile = token.scopes.contains("profile")
				let includeEmail = token.scopes.contains("email")
				
				// Create the user profile picture URL if available
				let pictureURL: String?
				if includeProfile, let userImage = token.user.userImage {
					pictureURL = "\(baseURL)/api/v3/image/user/\(userImage)"
				} else {
					pictureURL = nil
				}
				
				// Create payload with all standard OIDC claims
				let payload = IDTokenPayload(
					iss: baseURL,
					sub: userId,
					aud: client.clientId,
					exp: Date().addingTimeInterval(accessTokenLifetime),
					iat: Date(),
					auth_time: Date(), // Use current time as authentication time
					acr: "1",          // Basic authentication level
					azp: client.clientId,
					name: includeProfile ? token.user.displayName : nil,
					preferred_username: includeProfile ? token.user.username : nil,
					email: includeEmail ? token.user.email : nil,
					email_verified: includeEmail ? false : nil, // We don't verify emails currently
					picture: pictureURL
				)
				
				// Sign the token with our RSA key
				idToken = try await OIDCHelper.signToken(payload)
				
				// Log the token for debugging purposes
				req.logger.debug("Generated ID token (refresh token flow): \(idToken ?? "nil")")
			}
			
			// Return the token response
			return TokenResponse(
				accessToken: newAccessToken,
				tokenType: "Bearer",
				expiresIn: Int(accessTokenLifetime),
				refreshToken: newRefreshToken,
				idToken: idToken,
				scope: token.scopes
			)
			
		case "client_credentials":
			// Client credentials grant (client acting on its own behalf, not as a user)
			// This grant type is only for confidential clients
			guard client.isConfidential else {
				throw Abort(.badRequest, reason: "Client credentials grant is only for confidential clients")
			}
			
			// Get optional scope parameter
			let scope = (try? req.content.get(String.self, at: "scope")) ?? "openid"
			
			// Check if requested scope is allowed for this client
			let requestedScopes = scope.split(separator: " ").map(String.init)
			let allowedScopes = client.scopes.split(separator: " ").map(String.init)
			
			// Validate the requested scopes
			try validateScopes(requested: requestedScopes, allowed: allowedScopes)
			
			// Generate tokens
			let accessToken = UUID().uuidString
			
			// Log the token for debugging
			req.logger.debug("Generated access token (client credentials flow): \(accessToken)")
			
			// Calculate token expiration times
			let accessTokenLifetime: TimeInterval = 3600 // 1 hour
			
			// For client credentials flow, we need a system user to associate with the token
			// Try to find a suitable system user
			var systemUser = try await User.query(on: req.db)
				.filter(\.$username == "system")
				.first()
			
			// If system user not found, try micro_karaoke user
			if systemUser == nil {
				systemUser = try await User.query(on: req.db)
					.filter(\.$username == "micro_karaoke")
					.first()
			}
			
			// If still not found, try admin user
			if systemUser == nil {
				systemUser = try await User.query(on: req.db)
					.filter(\.$username == "admin")
					.first()
			}
			
			guard let user = systemUser else {
				throw Abort(.internalServerError, reason: "No suitable system user found for client credentials flow")
			}
			
			// Create and save the token
			let oauthToken = OAuthToken(
				accessToken: accessToken,
				clientID: try client.requireID(),
				userID: try user.requireID(),
				scopes: scope,
				expiresAt: Date().addingTimeInterval(accessTokenLifetime)
			)
			try await oauthToken.save(on: req.db)
			
			// Return the token response
			return TokenResponse(
				accessToken: accessToken,
				tokenType: "Bearer",
				expiresIn: Int(accessTokenLifetime),
				refreshToken: nil, // No refresh token for client credentials
				idToken: nil,      // No ID token for client credentials
				scope: scope
			)
			
		default:
			throw Abort(.badRequest, reason: "Unsupported grant type")
		}
	}
	
	/// `GET/POST /oidc/userinfo`
	///
	/// Returns claims about the authenticated user.
	///
	/// - Parameter req: The HTTP request with a Bearer token
	/// - Returns: UserInfo claims for the authenticated user
	func userInfoHandler(_ req: Request) async throws -> Response {
		// Parse the Authorization header for the Bearer token
		guard let bearerAuth = req.headers.bearerAuthorization else {
			throw Abort(.unauthorized, reason: "Missing Bearer token")
		}
		
		// Validate the access token
		guard let token = try await OAuthToken.query(on: req.db)
			.filter(\.$accessToken == bearerAuth.token)
			.filter(\.$isRevoked == false)
			.with(\.$user)
			.first() else {
			throw Abort(.unauthorized, reason: "Invalid token")
		}
		
		// Check if the token has expired
		if token.expiresAt < Date() {
			throw Abort(.unauthorized, reason: "Token expired")
		}
		
		// Check if the token has the required scopes
		let tokenScopes = token.scopes.split(separator: " ").map(String.init)
		guard tokenScopes.contains("openid") else {
			throw Abort(.forbidden, reason: "Token does not have openid scope")
		}
		
		// Build the user info response based on the scopes
		var userInfo: [String: String] = [
			"sub": token.user.id?.uuidString ?? ""
		]
		
		if tokenScopes.contains("profile") {
			userInfo["name"] = token.user.username
			userInfo["preferred_username"] = token.user.username
			// Add more profile claims if available
		}
		
		if tokenScopes.contains("email") && token.user.email != nil {
			userInfo["email"] = token.user.email
			userInfo["email_verified"] = "false" // We don't verify emails currently
		}
		
		// Return the user info as JSON
		let response = Response(status: .ok)
		try response.content.encode(userInfo)
		response.headers.contentType = .json
		return response
	}
	
	/// `GET /oidc/jwks`
	///
	/// Returns the JSON Web Key Set containing the public keys used to verify the signatures
	/// of JWT tokens issued by this server.
	///
	/// - Parameter req: The HTTP request
	/// - Returns: A JWKS structure with the server's public keys
	func jwksHandler(_ req: Request) async throws -> Response {
		// Return the JWK Set with the server's public keys for verifying JWTs
		let response = Response(status: .ok)
		response.headers.contentType = .json
		
		// Create a pretty-printing encoder with sorted keys
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		
		// Get the JWKS data through our helper method
		let jwks = await OIDCHelper.getJWKS()
		
		// Encode and set the body
		response.body = .init(data: try encoder.encode(jwks))
		
		return response
	}
	
	// MARK: - Token Introspection and Revocation
	
	/// `POST /oidc/introspect`
	///
	/// Implements the OAuth 2.0 Token Introspection endpoint (RFC 7662).
	/// Allows clients to determine the state and validity of an access token or refresh token.
	///
	/// - Parameter req: The HTTP request containing the token to introspect
	/// - Returns: Introspection response with token metadata
	func introspectHandler(_ req: Request) async throws -> Response {
		// Get authenticated client from auth middleware
		guard req.auth.get(OAuthClient.self) != nil else {
			throw Abort(.unauthorized, reason: "Client authentication required")
		}
		
		// Get token from request
		guard let token = try? req.content.get(String.self, at: "token") else {
			throw Abort(.badRequest, reason: "Missing token parameter")
		}
		
		// Token type hint would be used in a full implementation
		// _ = try? req.content.get(String.self, at: "token_type_hint")
		
		// Check if it's an access token first
		let oauthToken = try await OAuthToken.query(on: req.db)
			.filter(\.$accessToken == token)
			.with(\.$user)
			.with(\.$client)
			.first()
		
		// Build the introspection response
		struct IntrospectionResponse: Content {
			var active: Bool
			var clientId: String?
			var username: String?
			var scope: String?
			var sub: String?
			var exp: Int?
			var iat: Int?
			var tokenType: String?
			
			enum CodingKeys: String, CodingKey {
				case active
				case clientId = "client_id"
				case username
				case scope
				case sub
				case exp
				case iat
				case tokenType = "token_type"
			}
		}
		
		var response = IntrospectionResponse(active: false)
		
		if let oauthToken = oauthToken, !oauthToken.isRevoked {
			let isExpired = oauthToken.expiresAt < Date()
			response.active = !isExpired
			
			if !isExpired {
				response.clientId = oauthToken.client.clientId
				response.username = oauthToken.user.username
				response.scope = oauthToken.scopes
				response.sub = oauthToken.user.id?.uuidString
				response.exp = Int(oauthToken.expiresAt.timeIntervalSince1970)
				response.iat = Int(oauthToken.createdAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
				response.tokenType = "bearer"
			}
		}
		
		// Create and configure the response
		let httpResponse = Response(status: .ok)
		try httpResponse.content.encode(response)
		httpResponse.headers.contentType = .json
		return httpResponse
	}
	
	/// `POST /oidc/revoke`
	///
	/// Implements the OAuth 2.0 Token Revocation endpoint (RFC 7009).
	/// Allows clients to revoke an access token or refresh token.
	///
	/// - Parameter req: The HTTP request containing the token to revoke
	/// - Returns: 200 OK status code regardless of whether the token existed
	func revokeHandler(_ req: Request) async throws -> HTTPStatus {
		// Get authenticated client from auth middleware
		guard req.auth.get(OAuthClient.self) != nil else {
			throw Abort(.unauthorized, reason: "Client authentication required")
		}
		
		// Get token from request
		guard let token = try? req.content.get(String.self, at: "token") else {
			throw Abort(.badRequest, reason: "Missing token parameter")
		}
		
		// Token type hint would be used in a full implementation
		// _ = try? req.content.get(String.self, at: "token_type_hint")
		
		// Try to find the token
		if let oauthToken = try await OAuthToken.query(on: req.db)
			.filter(\.$accessToken == token)
			.first() {
			
			// Revoke the token
			oauthToken.isRevoked = true
			try await oauthToken.save(on: req.db)
		}
		
		// Always return 200 OK as per the RFC, regardless of whether the token existed
		return .ok
	}
}

// MARK: - Supporting Structures

// Custom error for scope validation failures
struct ScopeValidationError: Error, CustomStringConvertible {
	let invalidScope: String
	
	var description: String {
		return "Requested scope '\(invalidScope)' is not allowed for this client"
	}
}

/// Validates that all requested scopes are in the list of allowed scopes
/// - Parameters:
///   - requested: Array of requested scope strings
///   - allowed: Array of allowed scope strings
/// - Throws: ScopeValidationError if any requested scope is not allowed
func validateScopes(requested: [String], allowed: [String]) throws {
	for requestedScope in requested {
		guard allowed.contains(requestedScope) else {
			throw ScopeValidationError(invalidScope: requestedScope)
		}
	}
}

// Base64URL encoding extension is now defined in OIDCHelper.swift

/// Structure representing the OpenID Connect Discovery Document
struct OpenIDConfiguration: Content {
	let issuer: String
	let authorizationEndpoint: String
	let tokenEndpoint: String
	let userinfoEndpoint: String
	let jwksUri: String
	let registrationEndpoint: String?
	let scopesSupported: [String]
	let responseTypesSupported: [String]
	let grantTypesSupported: [String]
	let subjectTypesSupported: [String]
	let idTokenSigningAlgValuesSupported: [String]
	let tokenEndpointAuthMethodsSupported: [String]
	let claimsSupported: [String]
	let codeChallengeMethodsSupported: [String]
	let introspectionEndpoint: String
	let revocationEndpoint: String
	
	enum CodingKeys: String, CodingKey {
		case issuer
		case authorizationEndpoint = "authorization_endpoint"
		case tokenEndpoint = "token_endpoint"
		case userinfoEndpoint = "userinfo_endpoint"
		case jwksUri = "jwks_uri"
		case registrationEndpoint = "registration_endpoint"
		case scopesSupported = "scopes_supported"
		case responseTypesSupported = "response_types_supported"
		case grantTypesSupported = "grant_types_supported"
		case subjectTypesSupported = "subject_types_supported"
		case idTokenSigningAlgValuesSupported = "id_token_signing_alg_values_supported"
		case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
		case claimsSupported = "claims_supported"
		case codeChallengeMethodsSupported = "code_challenge_methods_supported"
		case introspectionEndpoint = "introspection_endpoint"
		case revocationEndpoint = "revocation_endpoint"
	}
}

/// Structure for an OAuth 2.0 token response
struct TokenResponse: Content {
	let accessToken: String
	let tokenType: String
	let expiresIn: Int
	let refreshToken: String?
	let idToken: String?
	let scope: String
	
	enum CodingKeys: String, CodingKey {
		case accessToken = "access_token"
		case tokenType = "token_type"
		case expiresIn = "expires_in"
		case refreshToken = "refresh_token"
		case idToken = "id_token"
		case scope
	}
}

import Vapor

extension SiteAdminController {
    // MARK: - OAuth Client Management Handlers
    
    // GET /admin/oauth
    // Shows a list of all registered OAuth clients
    func oauthClientsHandler(_ req: Request) async throws -> View {
        let response = try await apiQuery(req, endpoint: "/admin/oauth/clients")
        let clientsWithGrants = try response.content.decode([OAuthClientDataWithGrants].self)
        
        struct OAuthClientsContext: Encodable {
            var trunk: TrunkContext
            var clientsWithGrants: [OAuthClientDataWithGrants]
            
            init(_ req: Request, clientsWithGrants: [OAuthClientDataWithGrants]) throws {
                trunk = .init(req, title: "OAuth Clients", tab: .admin)
                self.clientsWithGrants = clientsWithGrants
            }
        }
        
        let ctx = try OAuthClientsContext(req, clientsWithGrants: clientsWithGrants)
        return try await req.view.render("admin/oauth/clients", ctx)
    }
    
    // GET /admin/oauth/client/create
    // Shows a form to create a new OAuth client
    func oauthClientCreateHandler(_ req: Request) async throws -> View {
        struct ScopeInfo: Encodable {
            var id: String
            var name: String
            var description: String
        }
        
        struct OAuthClientCreateContext: Encodable {
            var trunk: TrunkContext
            var scopes: [ScopeInfo]
            
            init(_ req: Request) throws {
                trunk = .init(req, title: "Create OAuth Client", tab: .admin)
                
                // Get all available scopes with their display names and descriptions
                self.scopes = OAuthScope.allCases.map { scope in
                    ScopeInfo(
                        id: scope.rawValue,
                        name: scope.displayName,
                        description: scope.description
                    )
                }
            }
        }
        
        let ctx = try OAuthClientCreateContext(req)
        return try await req.view.render("admin/oauth/client-create", ctx)
    }
    
    // POST /admin/oauth/client/create
    // Handles form submission for creating a new OAuth client
    func oauthClientCreatePostHandler(_ req: Request) async throws -> Response {
        struct OAuthClientFormContent: Content {
            var name: String
            var description: String
            var website: String
            var privacyPolicyUrl: String?
            var logoUrl: String?
            var backgroundUrl: String?
            var redirectURIs: String
            var grantTypes: [String]
            var responseTypes: [String]
            var scopes: [String]
            var isConfidential: Bool
        }
        
        let formData = try req.content.decode(OAuthClientFormContent.self)
        
        let redirectURIs = formData.redirectURIs
            .split(separator: "\n")
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        
        let apiData = OAuthClientCreateData(
            name: formData.name,
            description: formData.description,
            website: formData.website,
            privacyPolicyUrl: formData.privacyPolicyUrl,
            logoUrl: formData.logoUrl,
            backgroundUrl: formData.backgroundUrl,
            redirectURIs: redirectURIs,
            grantTypes: formData.grantTypes,
            responseTypes: formData.responseTypes,
            scopes: formData.scopes,
            isConfidential: formData.isConfidential
        )
        
        try await apiQuery(req, endpoint: "/admin/oauth/client/create", method: .POST, encodeContent: apiData)
        
        return req.redirect(to: "/admin/oauth")
    }
    
    // GET /admin/oauth/client/:oauth_client_id
    // Shows details for a specific OAuth client
    func oauthClientViewHandler(_ req: Request) async throws -> View {
        guard let clientID = req.parameters.get(oauthClientIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing client ID parameter")
        }
        
        let response = try await apiQuery(req, endpoint: "/admin/oauth/client/\(clientID)")
        let client = try response.content.decode(OAuthClientData.self)
        
        // Get grant count for this client
        let grantCountResponse = try await apiQuery(req, endpoint: "/admin/oauth/client/\(clientID)/grants/count")
        let grantCount = try grantCountResponse.content.decode(Int.self)
        
        struct ScopeInfo: Encodable {
            var id: String
            var name: String
            var description: String
        }
        
        struct OAuthClientViewContext: Encodable {
            var trunk: TrunkContext
            var client: OAuthClientData
            var grantCount: Int
            var scopes: [ScopeInfo]
            
            init(_ req: Request, client: OAuthClientData, grantCount: Int) throws {
                trunk = .init(req, title: "OAuth Client: \(client.name)", tab: .admin)
                self.client = client
                self.grantCount = grantCount
                
                // Get all available scopes with their display names and descriptions
                self.scopes = OAuthScope.allCases.map { scope in
                    ScopeInfo(
                        id: scope.rawValue,
                        name: scope.displayName,
                        description: scope.description
                    )
                }
            }
        }
        
        let ctx = try OAuthClientViewContext(req, client: client, grantCount: grantCount)
        return try await req.view.render("admin/oauth/client-view", ctx)
    }
    
    // POST /admin/oauth/client/:oauth_client_id/update
    // Handles form submission for updating an OAuth client
    func oauthClientUpdatePostHandler(_ req: Request) async throws -> Response {
        guard let clientID = req.parameters.get(oauthClientIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing client ID parameter")
        }
        
        struct OAuthClientUpdateFormContent: Content {
            var name: String
            var description: String
            var website: String
            var privacyPolicyUrl: String?
            var logoUrl: String?
            var backgroundUrl: String?
            var redirectURIs: String
            var grantTypes: [String]
            var responseTypes: [String]
            var scopes: [String]
            var isConfidential: Bool
            var isEnabled: Bool
        }
        
        let formData = try req.content.decode(OAuthClientUpdateFormContent.self)
        
        let redirectURIs = formData.redirectURIs
            .split(separator: "\n")
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        
        let apiData = OAuthClientUpdateData(
            name: formData.name,
            description: formData.description,
            website: formData.website,
            privacyPolicyUrl: formData.privacyPolicyUrl,
            logoUrl: formData.logoUrl,
            backgroundUrl: formData.backgroundUrl,
            redirectURIs: redirectURIs,
            grantTypes: formData.grantTypes,
            responseTypes: formData.responseTypes,
            scopes: formData.scopes,
            isConfidential: formData.isConfidential,
            isEnabled: formData.isEnabled
        )
        
        try await apiQuery(req, endpoint: "/admin/oauth/client/\(clientID)/update", method: .POST, encodeContent: apiData)
        
        return req.redirect(to: "/admin/oauth/client/\(clientID)")
    }
    
    // POST /admin/oauth/client/:oauth_client_id/delete
    // Deletes an OAuth client
    func oauthClientDeletePostHandler(_ req: Request) async throws -> Response {
        guard let clientID = req.parameters.get(oauthClientIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing client ID parameter")
        }
        
        try await apiQuery(req, endpoint: "/admin/oauth/client/\(clientID)/delete", method: .POST)
        
        return req.redirect(to: "/admin/oauth")
    }
}
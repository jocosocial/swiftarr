import Fluent
import Vapor

/// Migration to create the OAuth client, authorization code, token, and grants tables.
/// This is the complete OAuth schema migration, combining what was previously split
/// across multiple migrations.
struct CreateOAuthSchema: AsyncMigration {
    
    func prepare(on database: Database) async throws {
        // Create the OAuth clients table
        try await database.schema(OAuthClient.schema)
            .id()
            .field("client_id", .string, .required)
            .field("client_secret", .string, .required)
            .field("name", .string, .required)
            .field("description", .string)
            .field("website", .string)
            .field("privacy_policy_url", .string)         // Added field
            .field("logo_url", .string)                   // Added field
            .field("background_url", .string)             // Added field
            .field("redirect_uris", .string, .required)
            .field("grant_types", .string, .required)
            .field("response_types", .string, .required)
            .field("scopes", .string, .required)
            .field("is_confidential", .bool, .required)
            .field("is_enabled", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "client_id")
            .create()
        
        // Create the OAuth authorization codes table
        try await database.schema(OAuthCode.schema)
            .id()
            .field("code", .string, .required)
            .field("client_id", .uuid, .required, .references(OAuthClient.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("redirect_uri", .string, .required)
            .field("scopes", .string, .required)
            .field("code_challenge", .string)
            .field("code_challenge_method", .string)
            .field("expires_at", .datetime, .required)
            .field("is_used", .bool, .required)
            .field("nonce", .string)
            .field("created_at", .datetime)
            .unique(on: "code")
            .create()
        
        // Create the OAuth tokens table
        try await database.schema(OAuthToken.schema)
            .id()
            .field("access_token", .string, .required)
            .field("refresh_token", .string)
            .field("client_id", .uuid, .required, .references(OAuthClient.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("scopes", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("refresh_token_expires_at", .datetime)
            .field("is_revoked", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "access_token")
            .create()
        
        // Create the OAuth grants table
        try await database.schema("oauth_grants")
            .id()
            .field("client_id", .uuid, .required, .references("oauth_clients", "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references("user", "id", onDelete: .cascade))
            .field("scopes", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "client_id", "user_id")
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("oauth_grants").delete()
        try await database.schema(OAuthToken.schema).delete()
        try await database.schema(OAuthCode.schema).delete()
        try await database.schema(OAuthClient.schema).delete()
    }
}
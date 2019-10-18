import FluentPostgreSQL
import Vapor
import Authentication
import Redis

/// Called before your application initializes.
public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws {

    /// run API on port 8081 by default and set a 10MB hard limit on file size
    services.register {
        container -> NIOServerConfig in
        .default(port: 8081, maxBodySize: 10_000_000)
    }

    /// register providers first
    try services.register(FluentPostgreSQLProvider())
    try services.register(AuthenticationProvider())
    try services.register(RedisProvider())

    /// register routes to the router
    let router = EngineRouter.default()
    try routes(router)
    services.register(router, as: Router.self)

    /// register middleware
    var middlewares = MiddlewareConfig()
    // middlewares.use(FileMiddleware.self) // serves files from `Public/` directory
    middlewares.use(ErrorMiddleware.self) // catches errors and converts to HTTP response
    services.register(middlewares)

    /// configure PostgreSQL connection

    /// configure Redis connection
    
    /// register databases
    var databases = DatabasesConfig()
    services.register(databases)

    /// configure migrations
    var migrations = MigrationConfig()
    services.register(migrations)
}

import Fluent
import Vapor

/// Where to get a `ClientApp` on a given platform.
struct ClientAppLink: Codable, Sendable, Equatable {
	var platform: ClientAppPlatform
	/// A URL for the app's store page/website. A path-only value like "/" means "this server".
	var url: String
}

/// A client application for Twitarr that we suggest users download. Shown in the web UI's "Client Apps" page and
/// returned by `GET /api/v3/admin/clients`.
///
/// - See Also: [ClientAppData](ClientAppData) the DTO for returning info on ClientApps.
/// - See Also: [ClientAppUploadData](ClientAppUploadData) the DTO for mutating ClientApps.
/// - See Also: [CreateClientAppSchema](CreateClientAppSchema) the Migration for creating the ClientApp table in the database.
final class ClientApp: Model, @unchecked Sendable {
	static let schema = "client_app"

	// MARK: Properties

	/// The client app's ID.
	@ID(key: .id) var id: UUID?

	/// Display name of the app.
	@Field(key: "name") var name: String

	/// A short description of the app.
	@Field(key: "app_description") var appDescription: String

	/// Filename of the app's icon in the image store.
	@OptionalField(key: "image") var image: String?

	/// Who builds the app.
	@Field(key: "developer") var developer: String

	/// Used to order apps in lists.
	@Field(key: "sort_name") var sortName: String

	/// One entry per platform the app is available on. The app's `platforms` are derived from this.
	@Field(key: "links") var links: [ClientAppLink]

	/// Optional linkage to one of the known `SwiftarrClientApp` values. Not shown to users.
	@OptionalField(key: "swiftarr_client") var swiftarrClient: SwiftarrClientApp?

	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	// MARK: Initialization

	// Used by Fluent
	init() {}

	init(name: String, description: String, image: String?, developer: String, sortName: String? = nil,
			links: [ClientAppLink], swiftarrClient: SwiftarrClientApp? = nil) {
		self.name = name
		self.appDescription = description
		self.image = image
		self.developer = developer
		self.sortName = sortName ?? name
		self.links = links
		self.swiftarrClient = swiftarrClient
	}

	var platforms: [ClientAppPlatform] {
		var seen = Set<ClientAppPlatform>()
		return links.map { $0.platform }.filter { seen.insert($0).inserted }
	}
}

struct CreateClientAppSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("client_app")
			.id()
			.field("name", .string, .required)
			.field("app_description", .string, .required)
			.field("image", .string)
			.field("developer", .string, .required)
			.field("sort_name", .string, .required)
			.field("links", .array(of: .json), .required)
			.field("swiftarr_client", .string)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("client_app").delete()
	}
}

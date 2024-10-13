import Fluent
import Vapor
import FluentSQL

/// A photo to be shown in the photo stream. Currently, photo stream photos:
///	- are non-editable and non-deletable by the author
///	- may be deleted by moderators. The 'locked' state may be applied as well, but does nothing.
///	
final class StreamPhoto: Model {
	static let schema = "streamphoto"
	
	// MARK: Properties

	// The ID of the StreamPhoto record. Monotonically increasing, but photos may be soft-deleted by moderation.
	@ID(custom: "id") var id: Int?

	/// The filename for the image. Use with the ImageController methods in `/api/v3/images/**`
	@Field(key: "image") var image: String
	
	/// Where on the boat the photo was taken. Optional. One of boatLocation or atEvent should be non-nil.
	@OptionalField(key: "boat_location") var boatLocation: PhotoStreamBoatLocation?
	
	/// The time the image was taken, as reported by the client upon upload. Should be within a minute of `createdAt`, but maybe not if we allow photo capture while ashore?
	@Field(key: "capture_time") var captureTime: Date

	/// Moderators can set several statuses on streamPhotos that modify visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations

	/// The `User`  who submitted the picture..
	@Parent(key: "author") var author: User
	
	/// The event where the photo was taken, if any.
	@OptionalParent(key: "at_event") var atEvent: Event?

	// Used by Fluent
	init() {}
	
	init(image: String, captureTime: Date, user: UserCacheData, atEvent: Event? = nil, boatLocation: PhotoStreamBoatLocation? = nil) {
		self.image = image
		self.captureTime = captureTime
		self.$author.id = user.userID
		self.moderationStatus = .normal
		if let event = atEvent {
			self.$atEvent.id = event.id
		}
		self.boatLocation = boatLocation
	}
}

extension StreamPhoto: Reportable {
	var reportType: ReportType { .streamPhoto }

	var authorUUID: UUID { $author.id }

	var autoQuarantineThreshold: Int { Settings.shared.postAutoQuarantineThreshold }
}

struct CreateStreamPhotoSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("streamphoto")
			.field("id", .int, .identifier(auto: true))
			.field("image", .string, .required)
			.field("boat_location", .string)
			.field("capture_time", .datetime, .required)
			.field("mod_status", modStatusEnum, .required)
			.field("created_at", .datetime)
			.field("deleted_at", .datetime)
			.field("author", .uuid, .required, .references("user", "id"))
			.field("at_event", .uuid, .references("event", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("streamphoto").delete()
	}
}

// Changes atEvent to be set to null when the associated event is deleted.
struct StreamPhotoSchemaV2: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("streamphoto")
			.foreignKey("at_event", references: "event", "id", onDelete: .setNull)
			.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("streamphoto")
			.foreignKey("at_event", references: "event", "id", onDelete: .noAction)
			.update()
	}
}


/// Areas on the ship used for tagging PhotoStream photos. This list purposefully avoids using room names specific to the Nieuw Amsterdam
/// (the ship we generally sail on each year), and is purposefully a bit vague. 
public enum PhotoStreamBoatLocation: String, Content, CaseIterable {
	case mainStage = "Main Stage"
	case secondState = "Second Stage"
	case mainDining = "Main Dining"
	case specialtyDining = "Specialty Dining"
	case poolArea = "Pool Area"
	case onBoat = "On Boat"
	case ashore = "Ashore"

// A long list of Nieuw Amsterdam specific place names. I decided against this list both because it's too long and because
// it's tied to the specific boat.
//	case worldStage
//	case atrium
//	case casino
//	case billboardOnboard
//	case rollingStone
//	case pinnacleBar
//	case pinnacleGrill
//	case artGallery
//	case explorersLounge
//	case mainDining
//	case hudsonRoom
//	case library
//	case halfMoonRoom
//	case onboardShops
//	case oceanBar
//	case stateroom
//	case fitnessCenter
//	case spa
//	case lidoPool
//	case lidoBar
//	case diveIn
//	case lidoMarket
//	case canaletto
//	case newYorkPizza
//	case seaViewBar
//	case seaViewPool
//	case kidsClub
//	case highScore
//	case hangTen
//	case crowsNest
//	case tenForward
//	case artStudio
//	case gameRoom
//	case morimotoBySea
//	case tamarind
//	case sportCourt
}

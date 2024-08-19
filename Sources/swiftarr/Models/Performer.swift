import Fluent
import Vapor

/// An official performer or shadow event organizer on the cruise. Generally, official performers are those listed on the JoCo website.
/// Shadow Event organizers are people who are running shadow events on the official schedule.
/// 
/// The records for official performers are imported in bulk, but shadow event organizers can self-create a Perfomer profile and attach it to the
/// event(s) they're running. For shadow event organizers, their Performer profile MUST be linked to their user (as it's user-created content), and
/// a user cannot have different profiles for different events. Also, while official performers *usually* have relations to events on the schedule, they
/// don't need to. Shadow event organizers profiles must be created with a relation to the event they're running.
/// 
/// Because it's often the case that there's at least one late change to the official lineup, these models can be soft-deleted by admin, which
/// should be easier to manage than delete-on-update logic.This also gives the *technical* ability to list performers who weren't able to make it aboard. 
/// I haven't checked whether this is information we can actually provide--there may be contractual issues or something.
final class Performer: Model {
	static let schema = "performer"
	
	@ID(key: .id) var id: UUID?
	
	/// Individual or band name. This is the full name, even though `sortOrder` below is usually the last name.
	@Field(key: "name") var name: String

	/// Generally, the last name of the performer, although it could be the first non-'the' word if it's a band name. Should only be used for sorting. Should be uppercased.
	@Field(key: "sort_order") var sortOrder: String
	
	/// Shadow event organizers relate their Performer model to their User, therefore the User's pronouns field is theoretically available, but don't use it in the context of Performers.
	/// Also, official performers aren't associated with any user.
	@OptionalField(key: "pronouns") var pronouns: String?
	
	/// The bio string may contain Markdown, and can be up to 20000 characters.
	@OptionalField(key: "bio") var bio: String?
	
	/// Photo of the performer
	@OptionalField(key: "photo") var photo: String?
	
	/// Organization, Company or Band Name
	@OptionalField(key: "organization") var organization: String?
	
	/// Title, if any
	@OptionalField(key: "title") var title: String?
	
	/// Performer's website, if any
	@OptionalField(key: "website") var website: String?
	
	/// Performer's Facebook link, if any
	@OptionalField(key: "facebook_url") var facebookURL: String?
	
	/// Performer's X link, if any
	@OptionalField(key: "x_url") var xURL: String?
	
	/// Performer's Instagram link, if any
	@OptionalField(key: "instagram_url") var instagramURL: String?
	
	/// Performer's Youtube link, if any
	@OptionalField(key: "youtube_url") var youtubeURL: String?

	/// Which years the performer has attended/will attend JoCo, as an array of Ints in the range 2011...<current year>.
	@Field(key: "years_attended") var yearsAttended: [Int]
	
	/// TRUE if this is one of the JoCo official performers. FALSE if it's a shadow event organizer.
	@Field(key: "official_performer") var officialPerformer: Bool
	
	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations

	/// Will be nil for official performers. For shadow event organizers, this is the User that created the content.
	/// The Twitarr User that created a Performer Profile for their event is generally not shown in the UI.
	@OptionalParent(key: "user") var user: User?
	
	///
	@Siblings(through: EventPerformer.self, from: \.$performer, to: \.$event) var events: [Event]
}

struct CreatePerformerSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("performer")
			.id()
			.field("name", .string, .required)
			.field("sort_order", .string, .required)
			.field("pronouns", .string)
			.field("bio", .string)
			.field("photo", .string)
			.field("organization", .string)
			.field("title", .string)
			.field("website", .string)
			.field("facebook_url", .string)
			.field("x_url", .string)
			.field("instagram_url", .string)
			.field("youtube_url", .string)
			.field("years_attended", .array(of: .int), .required)
			.field("official_performer", .bool, .required)
			.field("deleted_at", .datetime)
			.field("user", .uuid, .references("user", "id"))
			.unique(on: "user", name: "one_performer_per_user")		// I believe this makes a `UNIQUE NULLS DISTINCT` type of constraint, 
																	// meaning multiple performers with no User will be okay.
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("performer").delete()
	}
}



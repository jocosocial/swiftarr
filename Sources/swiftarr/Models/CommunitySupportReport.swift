import Fluent
import Foundation
import Vapor

/// A report written up by a Community Support team member about something an attendee told them.
///
/// Deliberately *not* `Reportable` or `ContentFilterable`: these records aren't public user content, must never enter the moderator
/// report queue, and need no image uploads, alertword scanning, or mention processing. They're readable only by Community Support
/// role holders and TwitarrTeam and above.
///
/// - See Also: `CommunitySupportAction`, the append-only log of what the team did with each report.
final class CommunitySupportReport: Model, @unchecked Sendable {
	static let schema = "community_support_report"

	// MARK: Properties

	@ID(key: .id) var id: UUID?

	/// The name of the team member filing the report, as they want it to appear.
	@Field(key: "member_name") var memberName: String

	/// Name of the person who experienced or witnessed the thing being reported. Optional.
	@Field(key: "reporter_name") var reporterName: String

	/// Free-text handle for the reporter, for when they're not picked from the user list.
	@Field(key: "reporter_handle_text") var reporterHandleText: String

	@Field(key: "reporter_cabin") var reporterCabin: String

	/// Free-text name of the person the report is about.
	@Field(key: "subject_name") var subjectName: String

	@Field(key: "reporter_experienced") var reporterExperienced: Bool

	@Field(key: "reporter_witnessed") var reporterWitnessed: Bool

	/// Whether the reporter wants follow-up. Stored as a string; see `CommunitySupportReportIntent`.
	@Field(key: "intent") var intent: CommunitySupportReportIntent

	/// May JoCo Cruise contact the reporter about this?
	@Field(key: "may_contact") var mayContact: Bool

	/// Free text rather than a `Date`: people recounting an incident rarely have an exact timestamp. See `EventFeedback.attendance`
	/// for the same reasoning.
	@Field(key: "experience_time") var experienceTime: String

	@Field(key: "experience_location") var experienceLocation: String

	@Field(key: "experience_description") var experienceDescription: String

	@Field(key: "preferred_outcome") var preferredOutcome: String

	@Field(key: "lived_experiences") var livedExperiences: String

	/// See `CommunitySupportReportStatus`. Stored as a string.
	@Field(key: "status") var status: CommunitySupportReportStatus

	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	// MARK: Relations

	/// The team member who filed the report.
	@Parent(key: "author") var author: User

	/// The reporter, if they have an account and the team member picked it. Set to nil if that account is deleted.
	@OptionalParent(key: "reporter_id") var reporter: User?

	/// The person the report is about, if picked from the user list.
	@OptionalParent(key: "subject_id") var subject: User?

	/// The discussion thread in the private Community Support forum, if someone has started one. If the thread is deleted this goes
	/// back to nil and a new one can be started. Follows the precedent of `Event.forum`.
	@OptionalParent(key: "forum_id") var forum: Forum?

	/// The log entries about this report.
	@Children(for: \.$report) var actions: [CommunitySupportAction]

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Creates a report from a submitted form. A report whose intent is "information only" starts out as `.infoOnly`; anything else starts `.new`.
	init(author: UUID, data: CommunitySupportReportCreateData) {
		self.$author.id = author
		self.memberName = data.memberName
		self.reporterName = data.reporterName ?? ""
		self.$reporter.id = data.reporterUserID
		self.reporterHandleText = data.reporterHandleText ?? ""
		self.reporterCabin = data.reporterCabin ?? ""
		self.$subject.id = data.subjectUserID
		self.subjectName = data.subjectName ?? ""
		self.reporterExperienced = data.reporterExperienced
		self.reporterWitnessed = data.reporterWitnessed
		self.intent = data.intent
		self.mayContact = data.mayContact
		self.experienceTime = data.experienceTime
		self.experienceLocation = data.experienceLocation
		self.experienceDescription = data.experienceDescription
		self.preferredOutcome = data.preferredOutcome ?? ""
		self.livedExperiences = data.livedExperiences ?? ""
		self.status = data.intent == .infoOnly ? .infoOnly : .new
	}
}

extension CommunitySupportReport {
	/// The longest post text the forum accepts is 2048 characters (see `PostContentData.validations()`). Stay comfortably under it.
	static let discussionPostCharacterLimit = 2000

	/// A descriptive title for the report: "Name - Location - When", where the name is that of the person the report is about.
	/// That's the typed subject name, falling back to the linked account's username, then to "Unspecified" when neither was given.
	///
	/// - Parameter subjectUsername: The username of the linked subject account, if there is one. The model only has its ID, so the
	///   caller looks it up.
	func displayTitle(subjectUsername: String? = nil) -> String {
		let candidates = [subjectName, subjectUsername ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
		let name = candidates.first { !$0.isEmpty } ?? "Unspecified"
		return "\(name) - \(experienceLocation) - \(experienceTime)"
	}

	/// The title for the discussion thread started from this report: its `displayTitle`, cut to the 100 character forum title limit.
	func discussionTitle(subjectUsername: String? = nil) -> String {
		String(displayTitle(subjectUsername: subjectUsername).prefix(100))
	}

	/// The address of this report's page on the site, as a full URL on the server's canonical address.
	var reportURL: String {
		var components = Settings.shared.canonicalServerURLComponents
		components.path = "/communitysupport/report/\(id?.uuidString ?? "")"
		return components.string ?? components.path
	}

	/// The text of the first post of the discussion thread: a full copy of the report, ending with a link back to it.
	///
	/// Forum posts are limited in length and a report may not fit. When it doesn't, the free-text fields are cut down together
	/// (the longest are trimmed first) so that no field is dropped entirely, and a note points to the full report. The report
	/// table stays the record of truth.
	func discussionPostText() -> String {
		var fields: [(label: String, value: String)] = [
			("Filed by", memberName),
			("Reporter", reporterName),
			("Reporter handle", reporterHandleText),
			("Cabin", reporterCabin),
			("About", subjectName),
			("Experienced", reporterExperienced ? "yes" : "no"),
			("Witnessed", reporterWitnessed ? "yes" : "no"),
			("Intent", intent.label),
			("May contact", mayContact ? "yes" : "no"),
			("When", experienceTime),
			("Where", experienceLocation),
			("What happened", experienceDescription),
			("Preferred outcome", preferredOutcome),
			("Lived experiences", livedExperiences),
		]
		.filter { !$0.1.isEmpty }
		// A full URL, not a bare path: post text only turns full URLs into links, and for the server's own hostnames it
		// then shortens them to a relative link, so the link follows whichever address the reader is browsing from.
		let link = reportURL
		let truncationNote = "(Long fields were cut short.)"
		let footer = "\nFull report: \(link)"
		// The characters spent on labels, separators, footers, and one "…" per field that might get cut.
		let overhead = fields.reduce(0) { $0 + $1.label.count + 3 } + footer.count + truncationNote.count + fields.count
		let budget = max(Self.discussionPostCharacterLimit - overhead, 0)
		let total = fields.reduce(0) { $0 + $1.value.count }
		var truncated = false
		if total > budget {
			truncated = true
			// Find the largest per-field cap such that capping every field at that length fits the budget.
			var low = 0
			var high = fields.map { $0.value.count }.max() ?? 0
			while low < high {
				let mid = (low + high + 1) / 2
				if fields.reduce(0, { $0 + min($1.value.count, mid) }) <= budget {
					low = mid
				}
				else {
					high = mid - 1
				}
			}
			fields = fields.map { $0.value.count > low ? ($0.label, String($0.value.prefix(low)) + "…") : $0 }
		}
		var lines = fields.map { "\($0.label): \($0.value)" }
		if truncated {
			lines.append(truncationNote)
		}
		return lines.joined(separator: "\n") + footer
	}
}

struct CreateCommunitySupportReportSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("community_support_report")
			.id()
			.field("member_name", .string, .required)
			.field("reporter_name", .string, .required)
			.field("reporter_handle_text", .string, .required)
			.field("reporter_cabin", .string, .required)
			.field("subject_name", .string, .required)
			.field("reporter_experienced", .bool, .required)
			.field("reporter_witnessed", .bool, .required)
			.field("intent", .string, .required)
			.field("may_contact", .bool, .required)
			.field("experience_time", .string, .required)
			.field("experience_location", .string, .required)
			.field("experience_description", .string, .required)
			.field("preferred_outcome", .string, .required)
			.field("lived_experiences", .string, .required)
			.field("status", .string, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("author", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("reporter_id", .uuid, .references("user", "id", onDelete: .setNull))
			.field("subject_id", .uuid, .references("user", "id", onDelete: .setNull))
			.field("forum_id", .uuid, .references("forum", "id", onDelete: .setNull))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("community_support_report").delete()
	}
}

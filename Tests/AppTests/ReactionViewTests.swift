import Leaf
import XCTVapor
@testable import swiftarr

/// Exercises the common reaction partial through Leaf's parameterized template extension.
final class ReactionViewTests: XCTestCase {
	/// A single partial must render matching chip state for initial pages and WebSocket fragments.
	func testSharedReactionTemplate() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent().appendingPathComponent("Sources/swiftarr/Resources/Views")
		for file in ["reactionsView.html", "reactionChip.html"] {
			try FileManager.default.copyItem(at: views.appendingPathComponent(file), to: directory.appendingPathComponent(file))
		}
		let wrapper = "#extend(\"reactionsView\"):\n#export(\"viewer\", viewer)\n#export(\"reactionAuthor\", post.author.userID)\n#export(\"reactionPostID\", post.postID)\n#export(\"reactionPrefix\", \"/privateevent/post\")\n#export(\"reactionCount\", post.reactions)\n#export(\"reactionItems\"):\n#for(reaction in post.reactions):#extend(\"reactionChip\")#endfor\n#endexport\n#endextend"
		try wrapper.write(to: directory.appendingPathComponent("wrapper.html"), atomically: true, encoding: .utf8)
		let app = try await Application.make(.testing)
		do {
			app.directory.viewsDirectory = directory.path + "/"
			try SwiftarrConfigurator(app).configureLeaf(app)
			struct User: Encodable { let userID: String }
			struct Reaction: Encodable { let reaction: String; let users: [User] }
			struct Post: Encodable { let reactions: [Reaction]; let author: User; let postID: Int }
			struct Context: Encodable { let post: Post; let viewer: String }
			for viewer in ["author", "reactor"] {
				let context = Context(post: Post(reactions: [Reaction(reaction: "👍", users: [User(userID: "reactor")])], author: User(userID: "author"), postID: 42), viewer: viewer)
				let view = try await app.view.render("wrapper", context).get()
				let html = String(buffer: view.data)
				XCTAssertTrue(html.contains("/privateevent/post/42/react"))
				XCTAssertEqual(html.contains("data-open-reaction-picker"), viewer != "author")
				XCTAssertEqual(html.contains("reaction-chip-disabled"), viewer == "author")
				XCTAssertEqual(html.contains("aria-pressed=\"true\""), viewer == "reactor")
			}
		} catch {
			try await app.asyncShutdown()
			throw error
		}
		try await app.asyncShutdown()
	}
}

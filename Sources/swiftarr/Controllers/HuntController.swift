import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/hunt/*` route endpoints and handler functions related to Hunts and their Puzzles.
struct HuntController: APIRouteCollection {
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/hunt endpoints
		let huntRoutes = app.grouped("api", "v3", "hunts")

		let adminAuthGroup = huntRoutes.tokenRoutes(feature: .hunts, minAccess: .admin)
		adminAuthGroup.post("create", use: addHunt)
	}

	func addHunt(_ req: Request) async throws -> HTTPStatus {
		let data = try ValidatingJSONDecoder().decode(HuntCreateData.self, fromBodyOf: req)
		try await req.db.transaction { transaction in
			let hunt = try Hunt(title: data.title, description: data.description)
			try await hunt.create(on: transaction)
			for puzzle in data.puzzles {
				let puzzleModel = try Puzzle(hunt: hunt, title: puzzle.title, body: puzzle.body, answer: puzzle.answer, hints: puzzle.hints, unlockTime: puzzle.unlockTime ?? Date())
				try await puzzleModel.create(on: transaction)
			}
		}
		return .created
	}
}

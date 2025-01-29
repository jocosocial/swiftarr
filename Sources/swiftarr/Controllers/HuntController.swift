import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/hunt/*` route endpoints and handler functions related to Hunts and their Puzzles.
struct HuntController: APIRouteCollection {
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/hunt endpoints
		let huntRoutes = app.grouped("api", "v3", "hunts")
		let flexRoutes = huntRoutes.flexRoutes(feature: .hunts)
		flexRoutes.get("", use: list)
		flexRoutes.get(huntIDParam, use: getHunt)

		let adminAuthGroup = huntRoutes.tokenRoutes(feature: .hunts, minAccess: .admin)
		adminAuthGroup.post("create", use: addHunt)
	}

	func list(_ req: Request) async throws -> HuntListData {
		let hunts = try await Hunt.query(on: req.db).sort(\.$title, .ascending).all()
		return try HuntListData(hunts)
	}

	func getHunt(_ req: Request) async throws -> HuntData {
		let user = req.auth.get(UserCacheData.self)
		// We'd like to order the children and filter their children, and Fluent doesn't
		// allow either of those on eager loads, so we have to do two queries.
		let hunt = try await Hunt.findFromParameter(huntIDParam, on: req)
		let huntID = try hunt.requireID()
		let puzzlesQuery = Puzzle.query(on: req.db)
				.filter(\.$hunt.$id == huntID)
				.sort(\.$unlockTime, .custom("ASC NULLS FIRST"))
		if let user = user {
			puzzlesQuery.joinWithFilter(method: .left, from: \Puzzle.$id, to: \PuzzleCallIn.$puzzle.$id, otherFilters:
					[.value(.path(PuzzleCallIn.path(for: \.$user.$id), schema: PuzzleCallIn.schema), .equal, .bind(user.userID)),
					.value(.path(PuzzleCallIn.path(for: \.$result), schema: PuzzleCallIn.schema), .equal, .enumCase("correct"))])
		}
		return try HuntData(hunt, try await puzzlesQuery.all())
	}

	func addHunt(_ req: Request) async throws -> HTTPStatus {
		let data = try ValidatingJSONDecoder().decode(HuntCreateData.self, fromBodyOf: req)
		try await req.db.transaction { transaction in
			let hunt = try Hunt(title: data.title, description: data.description)
			try await hunt.create(on: transaction)
			for puzzle in data.puzzles {
				let puzzleModel = try Puzzle(hunt: hunt, title: puzzle.title, body: puzzle.body, answer: puzzle.answer, hints: puzzle.hints, unlockTime: puzzle.unlockTime)
				try await puzzleModel.create(on: transaction)
			}
		}
		return .created
	}
}

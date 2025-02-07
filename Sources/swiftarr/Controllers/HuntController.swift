import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/hunts/*` route endpoints and handler functions related to Hunts and their Puzzles.
struct HuntController: APIRouteCollection {
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
		
		// convenience route group for all /api/v3/hunts endpoints
		let huntRoutes = app.grouped("api", "v3", "hunts")
		let flexRoutes = huntRoutes.flexRoutes(feature: .hunts)
		flexRoutes.get("", use: list)
		flexRoutes.get(huntIDParam, use: getHunt)
		flexRoutes.get("puzzles", puzzleIDParam, use: getPuzzle)

		// Hunt Route Group, requires token
		let tokenAuthGroup = huntRoutes.tokenRoutes(feature: .hunts)
		tokenAuthGroup.post("puzzles", puzzleIDParam, "callin", use: callIn)

		let adminAuthGroup = huntRoutes.tokenRoutes(feature: .hunts, minAccess: .twitarrteam)
		adminAuthGroup.post("create", use: addHunt)
		adminAuthGroup.get(huntIDParam, "admin", use: getHuntAdmin)
		adminAuthGroup.patch("puzzles", puzzleIDParam, use: updatePuzzle)
		adminAuthGroup.delete(huntIDParam, use: deleteHunt)
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

	func getHuntAdmin(_ req: Request) async throws -> HuntData {
		let hunt = try await Hunt.findFromParameter(huntIDParam, on: req)
		let huntID = try hunt.requireID()
		let puzzles = try await Puzzle.query(on: req.db)
				.filter(\.$hunt.$id == huntID)
				.sort(\.$unlockTime, .custom("ASC NULLS FIRST")).all()
		return try HuntData(forAdmin: hunt, puzzles)
	}

	func getPuzzle(_ req: Request) async throws -> HuntPuzzleDetailData {
		let user = req.auth.get(UserCacheData.self)
		let puzzle = try await Puzzle.findFromParameter(puzzleIDParam, on: req) { query in
			query.with(\.$hunt).group(.or) { group in
				group.filter(\.$unlockTime == nil).filter(\.$unlockTime <= Date())
			}
		}
		let puzzleID = try puzzle.requireID()
		var callIns: [PuzzleCallIn] = []
		if let user = user {
			callIns = try await PuzzleCallIn.query(on: req.db)
				.filter(\.$user.$id == user.userID)
				.filter(\.$puzzle.$id == puzzleID)
				.sort(\.$createdAt)
				.all()
		}
		return try HuntPuzzleDetailData(puzzle, callIns)
	}

	func callIn(_ req: Request) async throws -> Response {
		let user = try req.auth.require(UserCacheData.self)
		let rawSubmission = try req.content.decode(String.self, using: PlaintextDecoder())
		let normalizedSubmission = rawSubmission.normalizePuzzleAnswer()
		let puzzle = try await Puzzle.findFromParameter(puzzleIDParam, on: req)
		let puzzleID = try puzzle.requireID()
		if let alreadySubmitted = try await PuzzleCallIn.query(on: req.db)
				.filter(\.$user.$id == user.userID)
				.filter(\.$puzzle.$id == puzzleID)
				.filter(\.$normalizedSubmission == normalizedSubmission)
				.first() { 
			return Response(status:.ok, body: Response.Body(data: try JSONEncoder().encode(HuntPuzzleCallInResultData(alreadySubmitted, puzzle))))
		}
		if let _ = try await PuzzleCallIn.query(on: req.db)
				.filter(\.$user.$id == user.userID)
				.filter(\.$puzzle.$id == puzzleID)
				.filter(\.$result == .correct)  // unfortunately can't easily make a partial index
				.first() {
			throw Abort(.conflict, reason: "you have already solved this puzzle")
		}
		var callInResult: CallInResult = .incorrect
		if puzzle.answer.normalizePuzzleAnswer() == normalizedSubmission {
			callInResult = .correct
		} else if let _ = puzzle.hints[normalizedSubmission] {
			callInResult = .hint
		}
		let newCallIn = try PuzzleCallIn(user.userID, puzzle, rawSubmission, callInResult)
		try await newCallIn.create(on: req.db)
		return Response(status: .created, body: Response.Body(data: try JSONEncoder().encode(HuntPuzzleCallInResultData(newCallIn, puzzle))))
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

	func updatePuzzle(_ req: Request) async throws -> HTTPStatus {
		let data = try req.content.decode(HuntPuzzlePatchData.self)
		let puzzle = try await Puzzle.findFromParameter(puzzleIDParam, on: req)
		if let body = data.body {
			puzzle.body = body
		}
		switch data.unlockTime {
			case .absent:
				break
			case .null:
				puzzle.unlockTime = nil
			case .present(let unlockTime):
				puzzle.unlockTime = unlockTime
		}
		try await puzzle.save(on: req.db)
		return .noContent
	}

	func deleteHunt(_ req: Request) async throws -> HTTPStatus {
		let hunt = try await Hunt.findFromParameter(huntIDParam, on: req)
		try await hunt.delete(on: req.db)
		return .ok
	}
}

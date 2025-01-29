import Vapor

struct SiteHuntController: SiteControllerUtils {
	func registerRoutes(_ app: Application) throws {
		let openRoutes = getOpenRoutes(app, feature: .hunts)
		openRoutes.get("hunts", use: huntsPageHandler).destination("the hunts")
		openRoutes.get("hunts", huntIDParam, use: singleHuntPageHandler)
		openRoutes.get("hunts", "puzzles", puzzleIDParam, use: singlePuzzlePageHandler)
    }

    func huntsPageHandler(_ req: Request) async throws -> View {
        struct HuntsPageContext: Encodable {
            var trunk: TrunkContext
            var hunts: HuntListData
            init(_ req: Request, _ hunts: HuntListData) {
                trunk = .init(req, title: "Hunts", tab: .hunts)
                self.hunts = hunts
            }
        }
        let response =  try await apiQuery(req, endpoint: "/hunts")
        let ctx = HuntsPageContext(req, try response.content.decode(HuntListData.self))
        return try await req.view.render("Hunts/list.html", ctx)
    }

    func singleHuntPageHandler(_ req: Request) async throws -> View {
        struct SingleHuntPageContext: Encodable {
            var trunk: TrunkContext
            var hunt: HuntData
            init(_ req: Request, _ hunt: HuntData) {
                trunk = .init(req, title: "\(hunt.title) | Hunt", tab: .hunts)
                self.hunt = hunt
            }
        }
		guard let huntID = req.parameters.get(huntIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid hunt ID"
		}
        let response = try await apiQuery(req, endpoint: "/hunts/\(huntID)")
        let ctx = SingleHuntPageContext(req, try response.content.decode(HuntData.self))
        return try await req.view.render("Hunts/hunt.html", ctx)
    }

    func singlePuzzlePageHandler(_ req: Request) async throws -> View {
        struct SinglePuzzlePageContext: Encodable {
            var trunk: TrunkContext
            var puzzle: HuntPuzzleDetailData
            var solved: Bool
            init(_ req: Request, _ puzzle: HuntPuzzleDetailData) {
                trunk = .init(req, title: "\(puzzle.title) | Puzzle", tab: .hunts)
                self.puzzle = puzzle
                solved = puzzle.callIns.contains { $0.correct != nil }
            }
        }
		guard let puzzleID = req.parameters.get(puzzleIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid puzzle ID"
		}
        let response = try await apiQuery(req, endpoint: "/hunts/puzzles/\(puzzleID)")
        let ctx = SinglePuzzlePageContext(req, try response.content.decode(HuntPuzzleDetailData.self))
        return try await req.view.render("Hunts/puzzle.html", ctx)

    }
}
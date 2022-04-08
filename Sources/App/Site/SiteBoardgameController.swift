import Vapor
import Crypto
import FluentSQL
import LeafKit

struct GameListContext: Encodable {
	var trunk: TrunkContext
	var games: BoardgameResponseData
	var showingFavorites: Bool
	var favoriteBtnURL: String
	var searchText: String
	var paginator: PaginatorContext

	init(_ req: Request, games: BoardgameResponseData) throws {
		trunk = .init(req, title: "Board Games List", tab: .games, search: "Search")
		self.games = games
		searchText = req.query[String.self, at: "search"] ?? ""
		if req.query[String.self, at: "favorite"]?.lowercased() == "true" {
			showingFavorites = true
			favoriteBtnURL = "/boardgames"
			if !searchText.isEmpty {
				favoriteBtnURL.append("?search=\(searchText)")
			}
		}
		else {
			showingFavorites = false
			favoriteBtnURL = "/boardgames?favorite=true"
			if !searchText.isEmpty {
				favoriteBtnURL.append("&search=\(searchText)")
			}
		}
		paginator = .init(start: games.start, total: games.totalGames, limit: games.limit) { pageIndex in
			"/boardgames?start=\(pageIndex * games.limit)&limit=\(games.limit)"
		}
	}
}

struct GameExpansionsContext: Encodable {
	var trunk: TrunkContext
	var games: [BoardgameData]

	init(_ req: Request, games: [BoardgameData]) throws {
		trunk = .init(req, title: "Board Games + Expansions", tab: .games)
		self.games = games
	}
}


/// Pages for displaying board games in the onboard Board Game Library.
struct SiteBoardgameController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .gameslist))
		openRoutes.get("boardgames", use: gamesPageHandler)
		openRoutes.get("boardgames", boardgameIDParam, "expansions", use: expansionPageHandler)
		openRoutes.get("boardgames", boardgameIDParam, "createfez", use: createFezForGame)
		
		// Routes that the user needs to be logged in to access.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .gameslist))
		privateRoutes.post("boardgames", boardgameIDParam, "favorite", use: addFavoriteGame)
		privateRoutes.delete("boardgames", boardgameIDParam, "favorite", use: removeFavoriteGame)
	}
	
	/// `GET /boardgames`
	/// 
	/// Returns a list of boardgames matching the query. Pageable.
	///
	/// Query Parameters:
	/// - search=STRING		Filter only games whose title that match the given string.
	/// - favorite=TRUE		Filter only favorites
	/// - start=INT
	/// - limit=INT
	func gamesPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/boardgames")
		let games = try response.content.decode(BoardgameResponseData.self)
		let gameListContext = try GameListContext(req, games: games)
		return try await req.view.render("GamesAndSongs/boardgameList", gameListContext)
	}
	
	/// `GET /boardgames/:boardgameID/expansions`
	/// 
	///
	func expansionPageHandler(_ req: Request) async throws -> View {
		guard let gameID = req.parameters.get(boardgameIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing game ID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/boardgames/expansions/\(gameID)")
		let games = try response.content.decode([BoardgameData].self)
		let ctx = try GameExpansionsContext(req, games: games)
		return try await req.view.render("GamesAndSongs/boardgameExpansions", ctx)
	}
	
	/// `GET /boardgames/:boardgameID/createfez`
	/// 
	/// Opens the Create Fez page, prefilled with info aboutt he given board game.
	func createFezForGame(_ req: Request) async throws -> View {
		guard let gameID = req.parameters.get(boardgameIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing game ID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/boardgames/\(gameID)")
		let game = try response.content.decode(BoardgameData.self)
		if game.isExpansion {
			let expansionsResponse = try await apiQuery(req, endpoint: "/boardgames/expansions/\(gameID)")
			let expansions = try expansionsResponse.content.decode([BoardgameData].self)
			let basegame = expansions.first(where: { !$0.isExpansion })
			let ctx = FezCreateUpdatePageContext(req, forGame: game, baseGame: basegame)
			return try await req.view.render("Fez/fezCreate", ctx)
		}
		else {
			let ctx = FezCreateUpdatePageContext(req, forGame: game)
			return try await req.view.render("Fez/fezCreate", ctx)
		}
	}
	
	/// `GET /boardgame/:boardgameID/favorite`
	/// 
	func addFavoriteGame(_ req: Request) async throws -> HTTPStatus {
		guard let gameID = req.parameters.get(boardgameIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing game ID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/boardgames/\(gameID)/favorite", method: .POST)
		return response.status
	}

	/// `DELETE /boardgame/:boardgameID/favorite`
	/// 
	func removeFavoriteGame(_ req: Request) async throws -> HTTPStatus {
		guard let gameID = req.parameters.get(boardgameIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing game ID parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/boardgames/\(gameID)/favorite", method: .DELETE)
		return response.status
	}

}

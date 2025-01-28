import Vapor

struct SiteHuntController: SiteControllerUtils {
	func registerRoutes(_ app: Application) throws {
		let openRoutes = getOpenRoutes(app, feature: .hunts)
		openRoutes.get("hunts", use: huntsPageHandler).destination("the hunts")
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
}
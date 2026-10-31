import Vapor

/// Leaf context for the Client Apps pages.
struct ClientAppsPageContext: Encodable {
	enum ClientAppTab: String, Codable {
		case all, web, ios, android, other, faq
	}

	struct AppCard: Encodable {
		var app: ClientAppData
		/// Links to show on the card. On a platform tab this is just that platform's link.
		var links: [LinkButton]
	}

	struct LinkButton: Encodable {
		var platformLabel: String
		var buttonTitle: String
		var url: String
	}

	var trunk: TrunkContext
	var tab: ClientAppTab
	var apps: [AppCard]
	var faqContent: String?

	init(_ req: Request, tab: ClientAppTab, apps: [ClientAppData] = [], faqContent: String? = nil) {
		trunk = .init(req, title: tab == .faq ? "Client Apps FAQ" : "Client Apps", tab: .home)
		self.tab = tab
		self.faqContent = faqContent
		let platformFilter = ClientAppPlatform(rawValue: tab.rawValue)
		self.apps = apps.map { app in
			let links = app.links.filter { platformFilter == nil || $0.platform == platformFilter }
			return AppCard(app: app, links: links.map { link in
				LinkButton(platformLabel: link.platform.label, buttonTitle: Self.buttonTitle(for: link.platform), url: link.url)
			})
		}
	}

	static func buttonTitle(for platform: ClientAppPlatform) -> String {
		switch platform {
		case .web: return "Open Website"
		case .ios: return "App Store"
		case .android: return "Google Play"
		case .other: return "Download"
		}
	}
}

/// Pages for browsing the list of suggested client apps.
struct SiteClientAppController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		let openRoutes = getOpenRoutes(app, path: "clients")
		openRoutes.get("", use: clientAppsPageHandler).destination("the Client Apps list")
		openRoutes.get("faq", use: clientAppsFAQHandler).destination("the Client Apps FAQ")
	}

	/// `GET /clients?platform=web|ios|android|other|all`
	///
	/// Shows the list of client apps. `platform=all` and no `platform` both show every app.
	func clientAppsPageHandler(_ req: Request) async throws -> View {
		let platform = try ClientAppPlatform.fromAPIString(req.query[String.self, at: "platform"])
		let response = try await apiQuery(req, endpoint: "/admin/clients", passThroughQuery: true)
		let apps = try response.content.decode([ClientAppData].self)
		let tab = platform.flatMap { ClientAppsPageContext.ClientAppTab(rawValue: $0.rawValue) } ?? .all
		return try await req.view.render("ClientApps/clientApps", ClientAppsPageContext(req, tab: tab, apps: apps))
	}

	/// `GET /clients/faq`
	///
	/// Shows the Client Apps FAQ, a render of a Markdown source file.
	func clientAppsFAQHandler(_ req: Request) async throws -> View {
		let content = try await fetchMarkdownFile(req, filePath: "/public/clientFaq.md")
		return try await req.view.render("ClientApps/clientAppsFAQ", ClientAppsPageContext(req, tab: .faq, faqContent: content))
	}
}

import FluentSQL
import LeafKit
import Vapor

struct SitePhotostreamController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user needs to be logged in to access.
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .photostream))
		globalRoutes.get("photostream", use: showPhotostream).destination("the photostream page")

		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .photostream))
		privateRoutes.get("photostream", "report", streamPhotoParam, use: photostreamReportPage)
		privateRoutes.post("photostream", "report", streamPhotoParam, use: postPhotostreamReport)
	}
	
	// GET /photostream
	//
	// Shows the last 30 photos in the photostream. This view has the Report and Mod controls; the view on the home page
	// doesn't have them primarily because the carousel is set to auto-play, although the buttons looking bad there and 
	// user confusion as to which photo you'd be reporting play a part.
	//
	// Mods get pagination when seeing this page; the `start` and `limit` query parameters work. 
	func showPhotostream(_ req: Request) async throws -> View {
		let photostreamResponse = try await apiQuery(req, endpoint: "/photostream")
		let photostream = try photostreamResponse.content.decode(PhotostreamListData.self)
		struct PhotostreamPageContext: Encodable {
			var trunk: TrunkContext
			var photostream: PhotostreamListData
			var paginator: PaginatorContext

			init(_ req: Request, photostream: PhotostreamListData) {
				trunk = .init(req, title: "Twitarr", tab: .home)
				self.photostream = photostream
				paginator = PaginatorContext(photostream.paginator) { pageIndex in
					"/photostream?start=\(pageIndex * photostream.paginator.limit)&limit=\(photostream.paginator.limit)"
				}
			}
		}
		let ctx = PhotostreamPageContext(req, photostream: photostream)
		return try await req.view.render("Photostream/photostream", ctx)		
	}

	// GET /photostream/report/:photostream_ID
	//
	// Shows a page that lets a user file a report against a photostream photo.
	func photostreamReportPage(_ req: Request) async throws -> View {
		guard let photostreamID = req.parameters.get(streamPhotoParam.paramString, as: Int.self) else {
			throw Abort(.badRequest, reason: "Missing photostream_ID parameter.")
		}
		let ctx = try ReportPageContext(req, photostreamID: photostreamID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /photostream/report/:photostream_ID
	//
	// Handles the POST of a report on a photostream photo.
	func postPhotostreamReport(_ req: Request) async throws -> HTTPStatus {
		guard let photostreamID = req.parameters.get(streamPhotoParam.paramString, as: Int.self) else {
			throw Abort(.badRequest, reason: "Missing photostream_ID parameter.")
		}
		let report = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/photostream/\(photostreamID)/report", method: .POST, encodeContent: report)
		return .created
	}
}

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
	// Supports filtering by `eventID` or `locationName` query parameters.
	func showPhotostream(_ req: Request) async throws -> View {
		// Get query parameters for filtering
		let eventID = req.query[UUID.self, at: "eventID"]
		let locationName = req.query[String.self, at: "locationName"]
		let start = req.query[Int.self, at: "start"]
		let limit = req.query[Int.self, at: "limit"]
		
		// Build query items for API call
		var queryItems: [URLQueryItem] = []
		if let eventID = eventID {
			queryItems.append(URLQueryItem(name: "eventID", value: eventID.uuidString))
		}
		if let locationName = locationName {
			queryItems.append(URLQueryItem(name: "locationName", value: locationName))
		}
		if let start = start {
			queryItems.append(URLQueryItem(name: "start", value: String(start)))
		}
		if let limit = limit {
			queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
		}
		
		// Fetch photostream data
		let photostreamResponse = try await apiQuery(req, endpoint: "/photostream", query: queryItems.isEmpty ? nil : queryItems, passThroughQuery: false)
		let photostream = try photostreamResponse.content.decode(PhotostreamListData.self)
		
		// Fetch available locations for filter menu
		let locationsResponse = try await apiQuery(req, endpoint: "/photostream/placenames")
		let locationsData = try locationsResponse.content.decode(PhotostreamLocationData.self)
		
		struct LocationFilterItem: Encodable {
			var name: String
			var url: String
			
			init(_ location: String) {
				self.name = location
				var components = URLComponents()
				components.path = "/photostream"
				components.queryItems = [URLQueryItem(name: "locationName", value: location)]
				self.url = components.string ?? "/photostream?locationName=\(location)"
			}
		}
		
		struct PhotostreamPhotoContext: Encodable {
			// Include all fields from PhotostreamImageData
			var postID: Int
			var createdAt: Date
			var author: UserHeader
			var image: String
			var event: EventData?
			var location: String?
			
			// Additional fields for template
			var title: String
			var titleUrl: String?
			
			init(_ photo: PhotostreamImageData) {
				self.postID = photo.postID
				self.createdAt = photo.createdAt
				self.author = photo.author
				self.image = photo.image
				self.event = photo.event
				self.location = photo.location
				
				// Set title and titleUrl based on event or location
				if let event = photo.event {
					self.title = event.title
					self.titleUrl = "/events/\(event.eventID)"
				} else if let location = photo.location {
					self.title = location
					var components = URLComponents()
					components.path = "/photostream"
					components.queryItems = [URLQueryItem(name: "locationName", value: location)]
					self.titleUrl = components.string
				} else {
					self.title = "On Boat"
					self.titleUrl = nil
				}
			}
		}
		
		struct PhotostreamPageContext: Encodable {
			var trunk: TrunkContext
			var photos: [PhotostreamPhotoContext]
			var paginator: PaginatorContext
			var locations: [LocationFilterItem]
			var currentEventID: UUID?
			var currentEventTitle: String?
			var currentLocationName: String?

			init(_ req: Request, photostream: PhotostreamListData, locations: [String], eventID: UUID?, locationName: String?) {
				trunk = .init(req, title: "Twitarr", tab: .home)
				self.photos = photostream.photos.map { PhotostreamPhotoContext($0) }
				self.locations = locations.map { LocationFilterItem($0) }
				self.currentEventID = eventID
				self.currentLocationName = locationName
				// Get event title from first photo if filtering by event
				if let eventID = eventID, let firstPhoto = photostream.photos.first, let event = firstPhoto.event, event.eventID == eventID {
					self.currentEventTitle = event.title
				} else {
					self.currentEventTitle = nil
				}
				
				// Build paginator URL preserving filter parameters
				paginator = PaginatorContext(photostream.paginator) { pageIndex in
					var components = URLComponents()
					components.path = "/photostream"
					var queryItems: [URLQueryItem] = []
					queryItems.append(URLQueryItem(name: "start", value: String(pageIndex * photostream.paginator.limit)))
					queryItems.append(URLQueryItem(name: "limit", value: String(photostream.paginator.limit)))
					if let eventID = eventID {
						queryItems.append(URLQueryItem(name: "eventID", value: eventID.uuidString))
					}
					if let locationName = locationName {
						queryItems.append(URLQueryItem(name: "locationName", value: locationName))
					}
					components.queryItems = queryItems
					return components.string ?? "/photostream"
				}
			}
		}
		let ctx = PhotostreamPageContext(req, photostream: photostream, locations: locationsData.locations, eventID: eventID, locationName: locationName)
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

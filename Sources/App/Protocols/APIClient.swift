import Vapor

protocol APIClient {
    // Pass
}

extension APIClient {
    /// Call the Swiftarr API. This method pulls a user's token from their session data and adds it to the API call. By default it also forwards URL query parameters
	/// from the Site-level request to the API-level request. 
	/// Previously, this method used the hostname and port from `application.http.server.configuration` to set the hostname and port to call.
	/// However, if Swiftarr is launched with command line overrides for the host and port, the HTTPServer startup code uses those overrides instead of the 
	/// values in the publicly accessible configuration, but does not update the values in the configuration. So, instead, we attempt to use the site-level Request's
	/// `Host` header to get these values.
	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod = .GET, defaultHeaders: HTTPHeaders? = nil,
			passThroughQuery: Bool = true,
			beforeSend: (inout ClientRequest) throws -> () = { _ in }) -> EventLoopFuture<ClientResponse> {
    	var headers = defaultHeaders ?? HTTPHeaders()
    	if let token = req.session.data["token"], !headers.contains(name: "Authorization") {
   			headers.add(name: "Authorization", value: "Bearer \(token)")
    	}
		let hostname = req.application.http.server.configuration.hostname
		let port = req.application.http.server.configuration.port
		let host: String = req.headers.first(name: "Host") ?? "\(hostname):\(port)"
    	var urlStr = "http://\(host)/api/v3" + endpoint
    	if passThroughQuery, let queryStr = req.url.query {
    		// FIXME: Chintzy. Should convert to URLComponents and back.
    		if urlStr.contains("?") {
	    		urlStr.append("&\(queryStr)")
    		}
    		else {
	    		urlStr.append("?\(queryStr)")
			}
    	}
    	return req.client.send(method, headers: headers, to: URI(string: urlStr), beforeSend: beforeSend).flatMapThrowing { response in
			guard response.status.code < 300 else {
				if let errorResponse = try? response.content.decode(ErrorResponse.self) {
					throw errorResponse
				}
				throw Abort(response.status)
			}
			return response
    	}
	}
}
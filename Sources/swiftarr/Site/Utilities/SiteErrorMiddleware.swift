import Vapor

/// Catches 404 errors where we don't match any route, genrates HTML error pages for them unless the path starts with `/api/v3`.
/// Must be installed as a global middleware (via app.middleware) to work, since it needs to be called for paths that don't mach routes.
public final class SiteNoRouteErrorMiddleware: AsyncMiddleware {
	let isReleaseMode: Bool

	func handleError(req: Request, error: Error) async throws -> Response {
		guard req.route == nil else  {
			throw error
		}
		// If we didn't match a route, only return an HTML page for 404 errors on GET methods.
		guard let abortError = error as? AbortError, abortError.status == .notFound, req.method == .GET else {
			throw error
		}
		// And, if it appears the client was trying (but failed) to find an API route, don't return an HTML page,
		// as API routes return JSON errors.
		guard !req.url.path.hasPrefix("/api/v3") else {
			throw error
		}

		// Report the error to logger.
		req.logger.report(error: error)

		struct ErrorPageContext: Encodable {
			var trunk: TrunkContext
			var status: UInt
			var statusText: String
			var errorString: String
			var linkDesc: String?			// If login fixes the error, where login takes you.

			init(_ req: Request, status: HTTPResponseStatus, errorStr: String) {
				trunk = .init(req, title: "Error", tab: .none)
				self.status = status.code
				self.statusText = "\(status.code) \(status.reasonPhrase)"
				errorString = errorStr
				linkDesc = nil 
			}
		}
		let ctx = ErrorPageContext(req, status: abortError.status, errorStr: abortError.reason)
		return try await req.view.render("error", ctx).encodeResponse(status: abortError.status, for: req)
	}

	init(environment: Environment) {
		isReleaseMode = environment.isRelease
	}

	/// See `Middleware`.
	public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		do {
			let response = try await next.respond(to: request)
			return response
		}
		catch {
			// handleError inspects the route and only returns the 'error' HTML page if the route would have
			// returned HTML. This middleware could be optimized to only be attached to routes that return HTML,
			// but there's no easy way to that.
			return try await handleError(req: request, error: error)
		}
	}
}

/// Captures all errors and transforms them into an internal server error HTTP response.
public final class SiteErrorMiddleware: AsyncMiddleware {
	let isReleaseMode: Bool

	func handleError(req: Request, error: Error) async throws -> Response {
		if let route = req.route {
			if let store = req.storage.get(SiteErrorStorageKey.self), let htmlErrors = store.produceHTMLFormattedErrors {
				if !htmlErrors {
					throw error
				}
			}
			// If we matched a route, and that route *doesn't* return an HTML page, don't return an error HTML page.
			else if route.responseType != View.self {
				throw error
			}
		}
		else {
			// If we didn't match a route, only return an HTML page for 404 errors on GET methods.
			guard let abortError = error as? AbortError, abortError.status == .notFound, req.method == .GET else {
				throw error
			}
			// And, if it appears the client was trying (but failed) to find an API route, don't return an HTML page,
			// as API routes return JSON errors.
			guard !req.url.path.hasPrefix("/api/v3") else {
				throw error
			}
		}

		// variables to determine
		let status: HTTPResponseStatus
		var reason: String
		var fieldErrors: [String: String]?
		var jsonError: ErrorResponse? = nil

		// inspect the error type
		switch error {
		case let validationError as ValidationError:
			status = .badRequest
			reason = validationError.collectReasonString()
			fieldErrors = validationError.collectFieldErrors()
		case let abort as AbortError:
			// this is an abort error, we should use its status, reason, and headers
			status = abort.status
			if status == .unauthorized {
				reason = "Login required"
				req.session.data["returnAfterLogin"] = Settings.shared.enablePreregistration || req.route?.userInfo["destination"] == nil ? 
						nil : req.url.string
			}
			else {
				reason = abort.reason
			}
		case let resp as ErrorResponse:
			// A call that returns an ErrorResponse on failure could get parsed and then thrown by a higher level API call
			reason = resp.reason
			status = HTTPResponseStatus(statusCode: Int(resp.status))
			fieldErrors = resp.fieldErrors
		case let resp as ErrorResponse:
			// For site-level errors that are going to get parsed by Javascript client-side, instead of displaying an error HTML page.
			reason = resp.reason
			status = HTTPResponseStatus(statusCode: Int(resp.status))
			jsonError = resp
		default:
			// if not release mode, and error is debuggable, provide debug info
			// otherwise, deliver a generic 500 to avoid exposing any sensitive error info
			reason = isReleaseMode ? "Something went wrong." : String(describing: error)
			status = .internalServerError
		}

		// Report the error to logger.
		req.logger.report(error: error)

		if let err = jsonError {
			return Response(status: status, body: .init(data: try JSONEncoder().encode(err)))				
		}
		else {
			struct ErrorPageContext: Encodable {
				var trunk: TrunkContext
				var status: UInt
				var statusText: String
				var errorString: String
				var linkDesc: String?			// If login fixes the error, where login takes you.

				init(_ req: Request, status: HTTPResponseStatus, errorStr: String) {
					trunk = .init(req, title: "Error", tab: .none)
					self.status = status.code
					self.statusText = "\(status.code) \(status.reasonPhrase)"
					errorString = errorStr
					if status == .unauthorized, let desc = req.route?.userInfo["destination"] as? String? {
						linkDesc = desc 
					}
				}
			}
			// Append field errors onto the error string
			if let fieldErrors = fieldErrors {
				for (field, err) in fieldErrors {
					reason.append("<br>\(field): \(err)")
				}
			}
			let ctx = ErrorPageContext(req, status: status, errorStr: reason)
			return try await req.view.render("error", ctx).encodeResponse(status: status, for: req)
		}
	}

	init(environment: Environment) {
		isReleaseMode = environment.isRelease
	}

	/// See `Middleware`.
	public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		do {
			let response = try await next.respond(to: request)
			return response
		}
		catch {
			// handleError inspects the route and only returns the 'error' HTML page if the route would have
			// returned HTML. This middleware could be optimized to only be attached to routes that return HTML,
			// but there's no easy way to that.
			return try await handleError(req: request, error: error)
		}
	}
}

// Stores instructions in a Request describing special handling ErrorMiddleware should take if the request throws an error.
// Can only be used in cases where the request actually matches a route.
struct SiteErrorStorageKey: StorageKey {
	typealias Value = SiteErrorMiddlewareStorage
}

struct SiteErrorMiddlewareStorage {
	// If non-nil, this value overrides the normal SiteErrorMidleware logic for whether to emit JSON or HTML to describe an error.
	let produceHTMLFormattedErrors: Bool?
}

import Vapor

/// Captures all errors and transforms them into an internal server error HTTP response.
public final class SiteErrorMiddleware: AsyncMiddleware {
	var isReleaseMode: Bool

	func handleError(req: Request, error: Error) async throws -> Response {
		if let route = req.route {
			// If we matched a route, and that route *doesn't* return an HTML page, don't return an error HTML page.
			if route.responseType != View.self {
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
		let reason: String
		var fieldErrors: [String: String]?

		// inspect the error type
		switch error {
		case let validationError as ValidationError:
			status = .badRequest
			reason = validationError.collectReasonString()
			fieldErrors = validationError.collectFieldErrors()
		case let abort as AbortError:
			// this is an abort error, we should use its status, reason, and headers
			reason = abort.reason
			status = abort.status
		case let resp as ErrorResponse:
			// A call that returns an ErrorResponse on failure could get parsed and then thrown by a higher level API call
			reason = resp.reason
			status = .badRequest
			fieldErrors = resp.fieldErrors
		default:
			// if not release mode, and error is debuggable, provide debug info
			// otherwise, deliver a generic 500 to avoid exposing any sensitive error info
			reason = isReleaseMode ? "Something went wrong." : String(describing: error)
			status = .internalServerError
		}

		// Report the error to logger.
		req.logger.report(error: error)

		// Append field errors onto the error string
		var errorStr = reason
		if let fieldErrors = fieldErrors {
			for (field, err) in fieldErrors {
				errorStr.append("<br>\(field): \(err)")
			}
		}

		struct ErrorPageContext: Encodable {
			var trunk: TrunkContext
			var status: String
			var errorString: String

			init(_ req: Request, status: HTTPResponseStatus, errorStr: String) {
				trunk = .init(req, title: "Error", tab: .none)
				self.status = "\(status.code) \(status.reasonPhrase)"
				errorString = errorStr
			}
		}
		let ctx = ErrorPageContext(req, status: status, errorStr: errorStr)
		return try await req.view.render("error", ctx).encodeResponse(status: status, for: req)
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

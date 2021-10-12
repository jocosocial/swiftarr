import Vapor

/// All errors returned in HTTP responses use this structure.
///`error` is always true, `reason` concatenates all errors into a single string, and `fieldErrors` breaks errors up by field name
/// of the request's body content, if available. Only content validation errors actaully use `fieldErrors`.
/// Field-specific validation errors are keyed by the path to the field that caused the error. Validation errors that aren't specific to an input field
/// (e.g. an error indicating that one of two fields may be empty, but not both) are all concatenated and placed into a `general` key in `fieldErrors`.
/// This means lthat all errors are both in `error` (concatenated into a single string), and also in `fieldErrors` (split into fields). 
public struct ErrorResponse: Codable, Error {
	/// Always `true` to indicate this is a non-typical JSON response.
	var error: Bool
	
	/// The HTTP status
	var status: UInt

	/// The reason for the error.
	var reason: String
	
	var fieldErrors: [String : String]?
}

/// Captures all errors and transforms them into an internal server error HTTP response.
public final class SwiftarrErrorMiddleware: Middleware {
	var isReleaseMode: Bool

	func handleError(req: Request, error: Error) -> Response {
		// variables to determine
		let status: HTTPResponseStatus
		var reason: String
		let headers: HTTPHeaders
		var fieldErrors: [String : String]?

		// inspect the error type
		switch error {
		case let validationError as ValidationError:
			status = .badRequest
			reason = validationError.collectReasonString()
			headers = validationError.headers
			fieldErrors = validationError.collectFieldErrors()
		case let abort as AbortError:
			// this is an abort error, we should use its status, reason, and headers
			reason = abort.reason
			status = abort.status
			headers = abort.headers
			if status == .notFound {
				reason = "404 Not Found - There's nothing at this URL path"
			}
		case let resp as ErrorResponse:
			// A call that returns an ErrorResponse on failure could get parsed and then thrown by a higher level API call
			reason = resp.reason
			status = HTTPStatus(statusCode: Int(resp.status))
			headers = [:]
			fieldErrors = resp.fieldErrors
		default:
			// if not release mode, and error is debuggable, provide debug info
			// otherwise, deliver a generic 500 to avoid exposing any sensitive error info
			reason = isReleaseMode ? "Something went wrong." : String(describing: error)
			status = .internalServerError
			headers = [:]
		}

		// Report the error to logger.
		req.logger.report(error: error)
		req.logger.log(level: .info, "\(req.method) \(req.url.path.removingPercentEncoding ?? req.url.path) -> \(status)")

		// create a Response with appropriate status
		let response = Response(status: status, headers: headers)

		// attempt to serialize the error to json
		do {
			let errorResponse = ErrorResponse(error: true, status: status.code, reason: reason, fieldErrors: fieldErrors)
			response.body = try .init(data: JSONEncoder().encode(errorResponse))
			response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
		} catch {
			response.body = .init(string: "{ \"error\": true, \"reason\": \"Unknown error. Error thrown during error handling.\" }")
			response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
		}
		return response
	}
	
	init(environment: Environment) {
		isReleaseMode = environment.isRelease
	}

	/// See `Middleware`.
	public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		return next.respond(to: request).map { response in
			request.logger.log(level: .info, "\(request.method) \(request.url.path.removingPercentEncoding ?? request.url.path) -> \(response.status)")
			return response
		}.flatMapErrorThrowing { error in
			return self.handleError(req: request, error: error)
		}
	}
}

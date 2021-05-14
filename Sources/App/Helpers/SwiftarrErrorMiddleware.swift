import Vapor

/// All errors returned in HTTP responses use this structure.
///`error` is always true, `reason` concatenates all errors into a single string, and `fieldErrors` breaks errors up by field name
/// of the request's body content, if available. Only content validation errors actaully use `fieldErrors`.
/// Field-specific validation errors are keyed by the path to the field that caused the error. Validation errors that aren't specific to an input field
/// (e.g. an error indicating that one of two fields may be empty, but not both) are all concatenated and placed into a `general` key in `fieldErrors`.
/// This means lthat all errors are both in `error` (concatenated into a single string), and also in `fieldErrors` (split into fields). 
struct ErrorResponse: Codable, Error {
	/// Always `true` to indicate this is a non-typical JSON response.
	var error: Bool

	/// The reason for the error.
	var reason: String
	
	var fieldErrors: [String : String]?
}

/// Captures all errors and transforms them into an internal server error HTTP response.
public final class SwiftarrErrorMiddleware: Middleware {

    /// Create a default `ErrorMiddleware`. Logs errors to a `Logger` based on `Environment`
    /// and converts `Error` to `Response` based on conformance to `AbortError` and `Debuggable`.
    ///
    /// - parameters:
    ///     - environment: The environment to respect when presenting errors.
    public static func `default`(environment: Environment) -> ErrorMiddleware {
        return .init { req, error in
            // variables to determine
            let status: HTTPResponseStatus
            let reason: String
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
			case let resp as ErrorResponse:
				// A call that returns an ErrorResponse on failure could get parsed and then thrown by a higher level API call
				reason = resp.reason
				status = .badRequest
				headers = [:]
				fieldErrors = resp.fieldErrors
            default:
                // if not release mode, and error is debuggable, provide debug info
                // otherwise, deliver a generic 500 to avoid exposing any sensitive error info
                reason = environment.isRelease
                    ? "Something went wrong."
                    : String(describing: error)
                status = .internalServerError
                headers = [:]
            }
            
            // Report the error to logger.
            req.logger.report(error: error)
            
            // create a Response with appropriate status
            let response = Response(status: status, headers: headers)
            
            // attempt to serialize the error to json
            do {
                let errorResponse = ErrorResponse(error: true, reason: reason, fieldErrors: fieldErrors)
                response.body = try .init(data: JSONEncoder().encode(errorResponse))
                response.headers.replaceOrAdd(name: .contentType, value: "application/json; charset=utf-8")
            } catch {
                response.body = .init(string: "Oops: \(error)")
                response.headers.replaceOrAdd(name: .contentType, value: "text/plain; charset=utf-8")
            }
            return response
        }
    }

    /// Error-handling closure.
    private let closure: (Request, Error) -> (Response)

    /// Create a new `ErrorMiddleware`.
    ///
    /// - parameters:
    ///     - closure: Error-handling closure. Converts `Error` to `Response`.
    public init(_ closure: @escaping (Request, Error) -> (Response)) {
        self.closure = closure
    }

    /// See `Middleware`.
    public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        return next.respond(to: request).flatMapErrorThrowing { error in
            return self.closure(request, error)
        }
    }
}

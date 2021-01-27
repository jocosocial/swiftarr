import Vapor
import Fluent

extension Model where IDValue: LosslessStringConvertible {

    /// Returns an `EventLoopFuture<User>` that will match the UUID of a user in a named request parameter. 
    ///
	///	- Parameter param: The name of a request parameter e.g. "user_id"
    /// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on
    ///   which the query must be run.
    /// - Returns: `[UUID]` containing all the user's associated IDs.
	static func findFromParameter(_ param: String, on req: Request) -> EventLoopFuture<Self> {
  		guard let parameter = req.parameters.get(param) else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Request parameter \(param) is missing."))
        }
  		guard let userID = IDValue(parameter) else {
            return req.eventLoop.makeFailedFuture(
            		Abort(.badRequest, reason: "Request parameter \(param) with value \(parameter) is malformed."))
        }
		return Self.find(userID, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(parameter)'"))
	}
}

extension EventLoopFuture where Value: Model {
    public func addModelID(or error: @autoclosure @escaping () -> Error = FluentError.idRequired) 
    		-> EventLoopFuture<(Value, Value.IDValue)> {
        return self.flatMapThrowing { value in
            guard let id = value.id else {
                throw error()
            }
            return (value, id)
        }
    }
}


// I am not proud of this. Wrapping closures in other closures like this isn't ideal.
// This code adds a new map variant for flatMaps whose callbacks throw errors. This method wraps the callback
// in another callback that catches errors and turns them into failed futures.
extension EventLoopFuture {
    @inlinable
    public func throwingFlatMap<NewValue>(file: StaticString = #file, line: UInt = #line,
    		 _ callback: @escaping (Value) throws -> EventLoopFuture<NewValue>) -> EventLoopFuture<NewValue> {
		let wrappedCallback: (Value) -> EventLoopFuture<NewValue> = { value in
			do {
				return try callback(value)
			}
			catch {
				return self.eventLoop.makeFailedFuture(error)
			}
		}
		return self.flatMap(wrappedCallback)
    }
}

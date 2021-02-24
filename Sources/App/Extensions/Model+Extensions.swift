import Vapor
import Fluent

extension Model where IDValue: LosslessStringConvertible {

	static func findFromParameter(_ param: PathComponent, on req: Request) -> EventLoopFuture<Self> {
		return findFromParameter(param.description, on: req)
	}

    /// Returns an `EventLoopFuture<User>` that will match the UUID of a user in a named request parameter. 
	/// Returns a failed future with an Abort error if: the parameter doesn't exist, the parameter's value can't be made into an IDValue 
	/// for the Model type, or no Model type with that ID was found in the database.
    ///
	///	- Parameter param: The name of a request parameter e.g. "user_id"
    /// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on
    ///   which the query must be run.
    /// - Returns: `[UUID]` containing all the user's associated IDs.
	static func findFromParameter(_ param: String, on req: Request) -> EventLoopFuture<Self> {
		let paramName = param.hasPrefix(":") ? String(param.dropFirst()) : param
  		guard let paramVal = req.parameters.get(paramName) else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Request parameter \(param) is missing."))
        }
  		guard let objectID = IDValue(paramVal) else {
            return req.eventLoop.makeFailedFuture(
            		Abort(.badRequest, reason: "Request parameter \(param) with value \(paramVal) is malformed."))
        }
		return Self.find(objectID, on: req.db)
			.unwrap(or: Abort(.notFound, reason: "no value found for identifier '\(paramVal)'"))
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

extension SiblingsProperty {
	// A thing that it seems like Fluent ought to have, but doesn't. Implemented in-package
	// this could get rid of the from: parameter, as the property wrapper knows about its object.
	// Fluent has a very similar attach() method, but it only calls your edit() block if it creates
	// the pivot.
	//
	// Anyway, given From and To sibling objects where From needs to be the object that contains
	// the sibling property, finds or creates the pivot model, calls the edit block so you can mod it,
	// and saves the pivot. 
	public func attachOrEdit(
		from: From,
		to: To,
        on database: Database,
        _ edit: @escaping (Through) -> () = { _ in }
    ) -> EventLoopFuture<Void> {
        guard let fromID = from.id else {
            fatalError("Cannot attach siblings relation to unsaved model.")
        }
        guard let toID = to.id else {
            fatalError("Cannot attach unsaved model.")
        }

        return Through.query(on: database)
            .filter(self.from.appending(path: \.$id) == fromID)
            .filter(self.to.appending(path: \.$id) == toID)
            .first()
            .flatMap { pivotOptional in
            	var pivot: Through
            	switch pivotOptional {
				case .some(let p):
					pivot = p
				case .none:
					pivot = Through()
					pivot[keyPath: self.from].id = fromID
					pivot[keyPath: self.to].id = toID
            	}
				edit(pivot)
				return pivot.save(on: database)
        	}
    }

}

// This lets use PathComponents when registering route parameters, and then get the string that req.parameters.get() wants
// from inside the route handler. Vapor uses ":parameter" when registering the route parameter, but uses "parameter" when 
// retrieving it.
extension PathComponent {
	var paramString: String {
        switch self {
        case .anything:
            return "*"
        case .catchall:
            return "**"
        case .parameter(let name):
            return name
        case .constant(let constant):
            return constant
        }
	}
}

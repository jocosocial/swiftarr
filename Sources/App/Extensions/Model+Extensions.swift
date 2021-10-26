import Vapor
import Fluent
import SQLKit

extension Model where IDValue: LosslessStringConvertible {

    /// Returns an `EventLoopFuture<Model>` that will match the ID given in a named request parameter. 
	/// For a route that has a  parameter named `userIDParam.paramString`,  `User.findFromParameter(userIDParam, req)`
	/// will get the value of the parameter and use that to fetch the user with that ID from the User table.
	/// Returns a failed future with an Abort error if: the parameter doesn't exist, the parameter's value can't be made into an IDValue 
	/// for the Model type, or no Model type with that ID was found in the database.
    ///
	///	- Parameter param: A PathComponent describing a path component of type .parameter
    /// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on
    ///   which the query must be run.
    /// - Returns: `[UUID]` containing all the user's associated IDs.
	static func findFromParameter(_ param: PathComponent, on req: Request) -> EventLoopFuture<Self> {
		return findFromParameter(param.description, on: req)
	}

    /// Returns an `EventLoopFuture<Model>` that will match the ID given in a named request parameter. 
	/// For a route that has a ":userid" parameter,  `User.findFromParameter("userid", req)` will return that user from the User table.
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

	/// Converts an `EventLoopFuture<Model>` into a `EventLoopFuture<((Model, id)>`, where id is the Model's id value.
	/// The tuple values may then be retrieved with something similar to `.map { (model, modelID) in ...`
	/// This method is designed to be chained, often after a query, like so: `Model.query(...).first().addModelID().map ...`
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
extension EventLoopFuture {

	/// SwiftNIO has a map() variant that can throw exceptions (oddly named flatMapThrowing()), but does not have a flatMap() that can throw.
	/// There's a whole discussion about it here: https://forums.swift.org/t/rename-flatmapthrowing-introduce-a-real-throwing-flatmap/40905
	/// 
	/// I personally feel the arguments against a throwing FlatMap are misguided, as exceptions that unwind the stack are a different error mechanism from
	/// failed futures meant to forward errors to async callbacks. Specifically, since an exception can't be caught by a future async callback, it has to be
	/// caught and handled, caught and converted to a error future, or allowed to unwind (In Vapor, this probably means it'll abort()). 
	///
	/// Now, a better argument for not having a throwing flatMap() in NIO may be that the calling code can't control how the exception gets turned into a failed future.
	/// makeFailedFuture(error) happens to be all we need at the moment, but that may change.
	///
	/// Anyway, this fn uses callback wrapping to wrap its callback inside a callback that catches errors, making it a real throwing flatMap().
    @inlinable public func throwingFlatMap<NewValue>(file: StaticString = #file, line: UInt = #line,
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


extension Array where Element: Model {
	/// Returns a Dictionary mapping IDs of the array elements to counts of how many associated Children each element has in the database.
	/// 
	/// Result is a Dictionary instead of an array because (I think?) SQL may coalesce array values with the same ID, resulting in a output array
	/// smaller than the input.
	/// 
	/// If the database is SQL-backed, this method uses SQLKit to get counts for the # of related rows of each array element all with one call. 
	/// This is considerably faster than the Fluent-only path, saving ~1.2ms per array element. For a 50 element array, the SQLKit path will take
	/// ~2ms, and the Fluent path will take ~75ms.
	public func childCountsPerModel<ChildModel: Model>(atPath: KeyPath<Element, ChildrenProperty<Element, ChildModel>>, on db: Database)
			throws -> EventLoopFuture<Dictionary<Element.IDValue, Int>> {
		guard let sql = db as? SQLDatabase else {
			// SQL not available? Use Fluent; make a separate count() query per array element. 
			let futures = self.map { $0[keyPath: atPath].query(on: db).count() }
			return futures.flatten(on: db.eventLoop).flatMapThrowing { counts in
				var elementTuples: [(Element.IDValue, Int)] = []
				for (index, element) in self.enumerated() {
					try elementTuples.append((element.requireID(), counts[index]))
				}
				return Dictionary(elementTuples, uniquingKeysWith: { (first, _) in first })
			}
		}
		// Use SQLKit directly, bypassing Fluent. Make a single SQL call of the general form:
		// "select parentColumn, count(*) from "childModelSchema" where parentColumn in <list of IDs> group by parentColumn
		// This returns a bunch of rows of (parentID, count) tuples
		var columnName: String
		switch self[0][keyPath: atPath.appending(path: \.parentKey)] {
			case .required(let required):
				columnName = ChildModel()[keyPath: required.appending(path: \.$id.key)].description
			case .optional(let optional):
				columnName = ChildModel()[keyPath: optional.appending(path: \.$id.key)].description
		}
		let elementIDArray = try self.map { try $0.requireID() }
		return sql.select().columns(SQLColumn(columnName), SQLFunction("COUNT", args: SQLLiteral.all))
				.from(ChildModel.schema).where(SQLIdentifier(columnName), .in, elementIDArray)
				.groupBy(columnName).all().flatMapThrowing { rows in
			let elementTuples: [(Element.IDValue, Int)] = try rows.map { row in
				let elementID = try row.decode(column: columnName, as: Element.IDValue.self)
				let countForThisElement = try row.decode(column: "count", as: Int.self)
				return (elementID, countForThisElement)
			}
			return Dictionary(elementTuples, uniquingKeysWith: { (first, _) in first })
		}
	}
}

extension SiblingsProperty {
	/// A thing that it seems like Fluent ought to have, but doesn't. Implemented in-package
	/// this could get rid of the from: parameter, as the property wrapper knows about its object.
	/// Fluent has a very similar attach() method, but it only calls your edit() block if it creates
	/// the pivot.
	///
	/// Anyway, given From and To sibling objects where From needs to be the object that contains
	/// the sibling property, finds or creates the pivot model, calls the edit block so you can mod it,
	/// and saves the pivot. 
	/// 
	/// Importantly, the edit closure is always called, whether a new pivot is created or not.
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

extension PathComponent {

	/// This lets us use PathComponents when registering route parameters, and then get the string that req.parameters.get() wants
	/// from inside the route handler. Vapor uses ":parameter" when registering the route parameter, but uses "parameter" when 
	/// retrieving it.
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

import Vapor
import Fluent
import SQLKit

extension Model where IDValue: LosslessStringConvertible {

	/// Returns a `Model` that will match the ID given in a named request parameter. 
	/// For a route that has a  parameter named `userIDParam.paramString`,  `User.findFromParameter(userIDParam, req)`
	/// will get the value of the parameter and use that to fetch the user with that ID from the User table.
	/// Returns a failed future with an Abort error if: the parameter doesn't exist, the parameter's value can't be made into an IDValue 
	/// for the Model type, or no Model type with that ID was found in the database.
	///
	///	- Parameter param: A PathComponent describing a path component of type .parameter
	/// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on
	///   which the query must be run.
	/// - Returns: `[UUID]` containing all the user's associated IDs.
	static func findFromParameter(_ param: PathComponent, on req: Request, builder: ((QueryBuilder<Self>) -> Void)? = nil) async throws -> Self {
		return try await findFromParameter(param.description, on: req, builder: builder)
	}

	/// Returns a `Model` that will match the ID given in a named request parameter. 
	/// For a route that has a ":userid" parameter,  `User.findFromParameter("userid", req)` will return that user from the User table.
	/// Returns a failed future with an Abort error if: the parameter doesn't exist, the parameter's value can't be made into an IDValue 
	/// for the Model type, or no Model type with that ID was found in the database.
	///
	///	- Parameter param: The name of a request parameter e.g. "user_id"
	/// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on which the query must be run.
	/// - Parameter builder:A block that runs during query construction; mostly lets callers add `.with()` clauses to the query.
	/// - Returns: `[UUID]` containing all the user's associated IDs.
	static func findFromParameter(_ param: String, on req: Request, builder: ((QueryBuilder<Self>) -> Void)? = nil) async throws -> Self {
		let paramName = param.hasPrefix(":") ? String(param.dropFirst()) : param
  		guard let paramVal = req.parameters.get(paramName) else {
			throw Abort(.badRequest, reason: "Request parameter \(param) is missing.")
		}
  		guard let objectID = IDValue(paramVal) else {
			throw Abort(.badRequest, reason: "Request parameter \(param) with value \(paramVal) is malformed.")
		}
		let query = Self.query(on: req.db).filter(\._$id == objectID)
		builder?(query)
		guard let result = try await query.first() else {
			throw Abort(.notFound, reason: "no value found for identifier '\(paramVal)'")
		}
		return result
	}
}

extension Array where Element: Model {
	/// Returns a Dictionary mapping IDs of the array elements to counts of how many associated Children each element has in the database.
	/// 
	/// Result is a Dictionary instead of an array because (I think?) SQL may coalesce array values with the same ID, resulting in a output array
	/// smaller than the input. Also, SQL won't return rows for UUIDS that aren't in the table.
	/// 
	/// If the database is SQL-backed, this method uses SQLKit to get counts for the # of related rows of each array element all with one call. 
	/// This is considerably faster than the Fluent-only path, saving ~1.2ms per array element. For a 50 element array, the SQLKit path will take
	/// ~2ms, and the Fluent path will take ~75ms.
	/// 
	/// The filter callbacks are used to modify the Fluent or SQLKit query before it runs. They are given the appropriate type of partially-built query builder.
	/// The intent is that the filters express the same operation (only one will be used for any connected database).
	public func childCountsPerModel<ChildModel: Model>(atPath: KeyPath<Element, ChildrenProperty<Element, ChildModel>>, on db: Database,
			fluentFilter: @escaping (QueryBuilder<ChildModel>) -> () = {_ in },
			sqlFilter: ((SQLSelectBuilder) -> ())? = nil)
			async throws -> Dictionary<Element.IDValue, Int> {
		guard !self.isEmpty else {
			return [:]
		}	
		guard let sql = db as? SQLDatabase else {
			// SQL not available? Use Fluent; make a separate count() query per array element. 
			let counts = try await withThrowingTaskGroup(of: (Element.IDValue, Int).self) { group -> [Element.IDValue : Int] in
				for model in self {
					group.addTask {
						let query = model[keyPath: atPath].query(on: db)
						fluentFilter(query)
						return try (model.requireID(), await query.count()) 
					}
				}
				var resultDict = [Element.IDValue : Int]()
				for try await result in group {
					resultDict[result.0] = result.1
				}
				return resultDict
			}
			return counts
		}
		// Use SQLKit directly, bypassing Fluent. Make a single SQL call of the general form:
		// "select parentColumn, count(*) from "childModelSchema" where parentColumn in <list of IDs> group by parentColumn
		// So, for an array of Forums calling this on their ForumPosts, the SQL would be:
		// "select forum, count(*) from forumpost where forum in <list of forum UUIDs> group by forum"
		// This returns a bunch of rows of (parentID, count) tuples
		var columnName: String
		switch Element.init()[keyPath: atPath.appending(path: \.parentKey)] {
			case .required(let required):
				columnName = ChildModel()[keyPath: required.appending(path: \.$id.key)].description
			case .optional(let optional):
				columnName = ChildModel()[keyPath: optional.appending(path: \.$id.key)].description
		}
		let elementIDArray = try self.map { try $0.requireID() }
		let query = sql.select().columns(SQLColumn(columnName), SQLFunction("COUNT", args: SQLLiteral.all))
				.from(ChildModel.schema).where(SQLIdentifier(columnName), .in, elementIDArray)
				.groupBy(columnName)
		if let filter = sqlFilter {
			filter(query)
		}
		
		// DEBUG code to show the generated SQL
//		var s = SQLSerializer(database: sql)
//		query.query.serialize(to: &s)
//		print(s.sql)

		let rows = try await query.all()
		let elementTuples: [(Element.IDValue, Int)] = try rows.map { row in
			let elementID = try row.decode(column: columnName, as: Element.IDValue.self)
			let countForThisElement = try row.decode(column: "count", as: Int.self)
			return (elementID, countForThisElement)
		}
		return Dictionary(elementTuples, uniquingKeysWith: { (first, _) in first })
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
	public func attachOrEdit(from: From, to: To, on database: Database, _ edit: @escaping (Through) -> () = { _ in }) async throws {
		guard let fromID = from.id else {
			fatalError("Cannot attach siblings relation to unsaved model.")
		}
		guard let toID = to.id else {
			fatalError("Cannot attach unsaved model.")
		}
		let pivotOptional = try await Through.query(on: database)
			.filter(self.from.appending(path: \.$id) == fromID)
			.filter(self.to.appending(path: \.$id) == toID)
			.first()
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
		try await pivot.save(on: database)
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

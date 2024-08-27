import Fluent
import FluentSQL
import SQLKit
import Vapor

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
	static func findFromParameter(
		_ param: PathComponent,
		on req: Request,
		builder: ((QueryBuilder<Self>) -> Void)? = nil
	) async throws -> Self {
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
	static func findFromParameter(_ param: String, on req: Request, builder: ((QueryBuilder<Self>) -> Void)? = nil)
		async throws -> Self
	{
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
	public func childCountsPerModel<ChildModel: Model>(
		atPath: KeyPath<Element, ChildrenProperty<Element, ChildModel>>,
		on db: Database,
		fluentFilter: @escaping (QueryBuilder<ChildModel>) -> Void = { _ in },
		sqlFilter: ((SQLSelectBuilder) -> Void)? = nil
	)
		async throws -> [Element.IDValue: Int]
	{
		guard !self.isEmpty else {
			return [:]
		}
		guard let sql = db as? SQLDatabase else {
			// SQL not available? Use Fluent; make a separate count() query per array element.
			let counts = try await withThrowingTaskGroup(of: (Element.IDValue, Int).self) {
				group -> [Element.IDValue: Int] in
				for model in self {
					group.addTask {
						let query = model[keyPath: atPath].query(on: db)
						fluentFilter(query)
						return try (model.requireID(), await query.count())
					}
				}
				var resultDict = [Element.IDValue: Int]()
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
		let query = sql.select()
			.columns(SQLColumn(columnName, table: ChildModel.schema), SQLFunction("COUNT", args: SQLLiteral.all))
			.from(ChildModel.schema)
			.where(SQLColumn(columnName, table: ChildModel.schema), .in, SQLBind.group(elementIDArray))
			.groupBy(SQLColumn(columnName, table: ChildModel.schema))
		sqlFilter?(query)

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
	public func attachOrEdit(from: From, to: To, on database: Database, _ edit: @escaping (Through) -> Void = { _ in })
		async throws
	{
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

extension QueryBuilder {

	/// Uses Postgres full text search capabilities for improved search when using a Postgres db. This fn is modeled after the many filter() methods
	/// in FluentKit's QueryBuilder+Filter.swift.
	@discardableResult public func fullTextFilter<Field>(_ field: KeyPath<Model, Field>, _ value: String) -> Self
	where Field: QueryableProperty, Field.Model == Model, Field.Value == String {
		if database is SQLDatabase && Model.self is any Searchable.Type {
			return filter(
				.extendedPath(
					[FieldKey(stringLiteral: "fulltext_search")],
					schema: Model.schemaOrAlias,
					space: Model.space
				),
				.custom("@@"),
				DatabaseQuery.Value.custom("websearch_to_tsquery('english', \(bind: String(value)))" as SQLQueryString)
			)
		}
		else {
			return filter(field, .custom("ILIKE"), "%\(value)%")
		}
	}

	// Same as above, but for joined tables in a query
	@discardableResult public func fullTextFilter<Joined, Field>(
		_ joined: Joined.Type,
		_ field: KeyPath<Joined, Field>,
		_ value: String
	) -> Self
	where Joined: Schema, Field: QueryableProperty, Field.Model == Joined, Field.Value == String {
		if database is SQLDatabase && Joined.self is any Searchable.Type {
			return filter(
				.extendedPath(
					[FieldKey(stringLiteral: "fulltext_search")],
					schema: Joined.schemaOrAlias,
					space: Joined.space
				),
				.custom("@@"),
				DatabaseQuery.Value.custom("websearch_to_tsquery('english', \(bind: String(value)))" as SQLQueryString)
			)
		}
		else {
			return filter(joined, field, .custom("ILIKE"), "%\(value)%")
		}
	}
	
	/// Joins a foriegn table to the current query and attaches filter clauses to the join. This lets us do the fairly common pattern
	/// `Query on <ModelX> and left join <ModelX_Favorite>, filtering the join for the current user's favorites`
	/// This returns ModelX rows that nobody has favorited and ModelX rows that others have favorited but the current user hasn't--with Favorite cols set to nil in each case.
	///  
	@discardableResult func joinWithFilter<LocalField, Foreign, ForeignField>(method: DatabaseQuery.Join.Method = .inner, 
			from: KeyPath<Model, LocalField>, to: KeyPath<Foreign, ForeignField>, otherFilters: [DatabaseQuery.Filter]) -> Self 	
    		where Foreign: Schema, ForeignField: QueryableProperty, LocalField: QueryableProperty, 
    		ForeignField.Value == LocalField.Value {
		var filters: [DatabaseQuery.Filter] = otherFilters
		filters.append(.field(.path(Model.path(for: from), schema: Model.schema), .equal, .path(Foreign.path(for: to), schema: Foreign.schema)))
		self.join(Foreign.self, filters, method: method)
		return self
	}
	
	/// Prints an approximation of the SQL this QueryBuilder will produce when run.  
	/// Does not produce a fully valid SQL statement because parts of the query aren't known until `.all()`, `.count()`, `.first()` etc. are called.
	/// Also, Fluent may add more clauses to the query when it's executed, such as the soft-delete filter.
	/// The intended purpose of this method is to make it easier to build queries by letting you see what a query is going to look like before executing it. 
	///  
	/// You can see something closer to the actual SQL produced by setting `application.logger.logLevel = .debug`, although this logs everything and is pretty verbose.
	/// Also it actually executes the queries, which may be bad if you' just want to preview the generated SQL.
	/// 
	/// To use: add `query.debugRawSQL()` to your code, where `query` is a `QueryBuilder`. Debug only; don't check in code that uses this.
	func debugRawSQL() {
		guard let db = self.database as? SQLDatabase else {
			return
		}
        var expression = SQLQueryConverter(delegate: PostgresConverterDelegate()).convert(query)
		let (sqlString, binds) = db.serialize(expression)
		let bindString = binds.count == 0 ? "" : binds.reduce(("Binds:\n", 1)) { ($0.0.appending("    \($0.1): \($1)\n"), $0.1 + 1) }.0
		print("\(sqlString)\n\(bindString)")		
	}
	
	/// Copied from file `PostgresConverterDelegate.swift` in package `fluent-postgres-driver` to make it available here for debugging
	private struct PostgresConverterDelegate: SQLConverterDelegate {
		func customDataType(_ dataType: DatabaseSchema.DataType) -> (any SQLExpression)? {
			switch dataType {
			case .uuid:
				return SQLRaw("UUID")
			case .bool:
				return SQLRaw("BOOL")
			case .data:
				return SQLRaw("BYTEA")
			case .date:
				return SQLRaw("DATE")
			case .datetime:
				return SQLRaw("TIMESTAMPTZ")
			case .double:
				return SQLRaw("DOUBLE PRECISION")
			case .dictionary:
				return SQLRaw("JSONB")
			case .array(of: let type):
				if let type = type, let dataType = self.customDataType(type) {
					return SQLArrayDataType(dataType: dataType)
				} else {
					return SQLRaw("JSONB")
				}
			case .enum(let value):
				return SQLIdentifier(value.name)
			case .int8, .uint8:
				return SQLIdentifier("char")
			case .int16, .uint16:
				return SQLRaw("SMALLINT")
			case .int32, .uint32:
				return SQLRaw("INT")
			case .int64, .uint64:
				return SQLRaw("BIGINT")
			case .string:
				return SQLRaw("TEXT")
			case .time:
				return SQLRaw("TIME")
			case .float:
				return SQLRaw("FLOAT")
			case .custom:
				return nil
			}
		}
	}

	/// Copied from file `PostgresConverterDelegate.swift` in package `fluent-postgres-driver` to make it available here for debugging
	private struct SQLArrayDataType: SQLExpression {
		let dataType: any SQLExpression
		
		func serialize(to serializer: inout SQLSerializer) {
			self.dataType.serialize(to: &serializer)
			serializer.write("[]")
		}
	}
}

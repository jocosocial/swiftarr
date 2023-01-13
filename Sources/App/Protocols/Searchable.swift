import Fluent

protocol Searchable: Model {
    var fullTextSearch: String { get }
}
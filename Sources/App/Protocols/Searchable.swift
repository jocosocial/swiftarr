import Fluent

/// A `Protocol` for searchable models.
/// Any model which implements this protocol should have a database column, `fulltext_search`,
/// which is a stored generated column containg tsvector data. 
/// See Sources/App/Migrations/Schema Creation/SearchIndexCreation.swift
protocol Searchable: Model { }

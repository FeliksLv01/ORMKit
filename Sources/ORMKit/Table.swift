public import GRDB

/// A value type mapped to one SQLite table by `@Table`.
public protocol TableModel: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable where Columns: Sendable {
    static var columns: Columns { get }
    static var primaryKeyColumn: String { get }
}

/// Generates column mapping and `TableModel` conformance for a Swift struct.
@attached(member, names: named(databaseTableName), named(primaryKeyColumn), named(Columns), named(columns), named(CodingKeys))
@attached(extension, conformances: TableModel)
public macro Table(_ name: String) = #externalMacro(module: "ORMKitMacros", type: "TableMacro")

/// Marks the primary-key property of a `@Table` struct.
@attached(peer, names: arbitrary)
public macro PrimaryKey() = #externalMacro(module: "ORMKitMacros", type: "PrimaryKeyMacro")

/// Overrides a property's database column name in a `@Table` struct.
@attached(peer, names: arbitrary)
public macro Column(_ name: String) = #externalMacro(module: "ORMKitMacros", type: "ColumnMacro")

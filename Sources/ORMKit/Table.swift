public import GRDB

/// A value type mapped to one SQLite table by `@Table`.
public protocol TableModel: Codable, FetchableRecord, PersistableRecord, TableRecord, Sendable where Columns: Sendable {
    static var columns: Columns { get }
    static var primaryKeyColumn: String { get }
    static func tableSchema() throws -> TableSchema
    static var schemaIndexes: [TableIndex] { get }
    static var schemaChecks: [String] { get }
}

extension TableModel {
    public static func tableSchema() throws -> TableSchema { throw SchemaError.noSchema(databaseTableName) }
    public static var schemaIndexes: [TableIndex] { [] }
    public static var schemaChecks: [String] { [] }
}

/// Generates column mapping and `TableModel` conformance for a Swift struct.
@attached(member, names: named(databaseTableName), named(primaryKeyColumn), named(Columns), named(columns), named(CodingKeys), named(tableSchema))
@attached(extension, conformances: TableModel)
public macro Table(_ name: String, schema: Bool = true) = #externalMacro(module: "ORMKitMacros", type: "TableMacro")

/// Marks the primary-key property of a `@Table` struct.
@attached(peer, names: arbitrary)
public macro PrimaryKey(autoIncrement: Bool = false) = #externalMacro(module: "ORMKitMacros", type: "PrimaryKeyMacro")

/// Overrides a property's database column name in a `@Table` struct.
@attached(peer, names: arbitrary)
public macro Column(_ name: String? = nil, storage: ColumnStorage? = nil, unique: Bool = false,
                    defaultValue: ColumnDefault? = nil, references: ColumnReference? = nil, check: String? = nil)
    = #externalMacro(module: "ORMKitMacros", type: "ColumnMacro")

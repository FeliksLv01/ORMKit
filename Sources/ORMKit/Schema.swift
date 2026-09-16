import Foundation
import GRDB

public enum ColumnStorage: Sendable {
    case integer, real, text, blob

    var sqlType: GRDB.Database.ColumnType {
        switch self {
        case .integer: .integer
        case .real: .real
        case .text: .text
        case .blob: .blob
        }
    }
}

public enum ColumnDefault: Sendable {
    case integer(Int64), real(Double), text(String), boolean(Bool), null
    /// A trusted SQLite expression, such as CURRENT_TIMESTAMP. Never pass user input.
    case sql(String)

    func apply(to column: ColumnDefinition) {
        switch self {
        case .integer(let value): column.defaults(to: value)
        case .real(let value): column.defaults(to: value)
        case .text(let value): column.defaults(to: value)
        case .boolean(let value): column.defaults(to: value)
        case .null: column.defaults(to: DatabaseValue.null)
        case .sql(let expression): column.defaults(sql: expression)
        }
    }
}

public struct ColumnReference: Sendable {
    public let table: String
    public let column: String
    public let onDelete: GRDB.Database.ForeignKeyAction?
    public let onUpdate: GRDB.Database.ForeignKeyAction?

    public init(_ table: String, column: String, onDelete: GRDB.Database.ForeignKeyAction? = nil,
                onUpdate: GRDB.Database.ForeignKeyAction? = nil) {
        self.table = table
        self.column = column
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
}

public struct SchemaColumn: Sendable {
    public let name: String
    public let storage: ColumnStorage
    public let isNullable: Bool
    public let isPrimaryKey: Bool
    public let autoIncrement: Bool
    public let unique: Bool
    public let defaultValue: ColumnDefault?
    public let references: ColumnReference?
    public let check: String?

    public init(_ name: String, type: Any.Type, storage: ColumnStorage? = nil,
                primaryKey: Bool = false, autoIncrement: Bool = false, unique: Bool = false,
                defaultValue: ColumnDefault? = nil, references: ColumnReference? = nil, check: String? = nil) throws {
        let optional = type as? any OptionalSchemaType.Type
        let valueType = optional?.wrappedType ?? type
        let resolvedStorage = try storage ?? inferStorage(valueType)
        guard !(primaryKey && optional != nil) else {
            throw SchemaError.invalidColumn(name, "A primary key cannot be optional.")
        }
        guard !autoIncrement || (primaryKey && resolvedStorage == .integer && (valueType == Int.self || valueType == Int64.self)) else {
            throw SchemaError.invalidColumn(name, "AUTOINCREMENT requires a non-optional Int or Int64 primary key.")
        }
        self.name = name
        self.storage = resolvedStorage
        self.isNullable = optional != nil
        self.isPrimaryKey = primaryKey
        self.autoIncrement = autoIncrement
        self.unique = unique
        self.defaultValue = defaultValue
        self.references = references
        self.check = check
    }
}

public struct TableIndex: Sendable {
    public let name: String
    public let columns: [String]
    public let unique: Bool
    /// A trusted SQL expression used for a partial index.
    public let conditionSQL: String?

    public init(_ name: String, columns: [String], unique: Bool = false, conditionSQL: String? = nil) {
        self.name = name
        self.columns = columns
        self.unique = unique
        self.conditionSQL = conditionSQL
    }
}

public struct TableSchema: Sendable {
    public let name: String
    public let columns: [SchemaColumn]
    public let indexes: [TableIndex]
    public let checks: [String]

    public init(_ name: String, columns: [SchemaColumn], indexes: [TableIndex] = [], checks: [String] = []) {
        self.name = name
        self.columns = columns
        self.indexes = indexes
        self.checks = checks
    }

    public func create(in db: GRDB.Database) throws {
        let identifiers = [name] + columns.map(\.name) + indexes.map(\.name)
            + columns.compactMap(\.references).flatMap { [$0.table, $0.column] }
        for identifier in identifiers {
            guard !identifier.isEmpty, !identifier.contains("\""), !identifier.contains("\0") else {
                throw SchemaError.invalidIdentifier(identifier)
            }
        }
        guard !columns.isEmpty, Set(columns.map(\.name)).count == columns.count,
              columns.filter(\.isPrimaryKey).count == 1 else {
            throw SchemaError.invalidTable(name)
        }
        let names = Set(columns.map(\.name))
        guard Set(indexes.map(\.name)).count == indexes.count,
              indexes.allSatisfy({ !$0.columns.isEmpty && Set($0.columns).isSubset(of: names) }) else {
            throw SchemaError.invalidTable(name)
        }
        try db.inSavepoint {
            try db.create(table: name) { table in
                for column in columns {
                    let definition = table.column(column.name, column.storage.sqlType)
                    if column.isPrimaryKey { definition.primaryKey(autoincrement: column.autoIncrement) }
                    if !column.isNullable { definition.notNull() }
                    if column.unique { definition.unique() }
                    column.defaultValue?.apply(to: definition)
                    if let check = column.check { definition.check(sql: check) }
                    if let reference = column.references {
                        definition.references(reference.table, column: reference.column,
                                              onDelete: reference.onDelete, onUpdate: reference.onUpdate)
                    }
                }
                for check in checks { table.check(sql: check) }
            }
            for index in indexes {
                let condition = index.conditionSQL.map { SQL(sql: $0).sqlExpression }
                try db.create(index: index.name, on: name, columns: index.columns,
                              unique: index.unique, condition: condition)
            }
            return .commit
        }
    }
}

public enum SchemaError: Error, CustomStringConvertible {
    case unsupportedType(String)
    case invalidColumn(String, String)
    case invalidTable(String)
    case noSchema(String)
    case invalidIdentifier(String)

    public var description: String {
        switch self {
        case .unsupportedType(let type): "Cannot infer SQLite storage for \(type). Specify @Column(storage:)."
        case .invalidColumn(let name, let reason): "Invalid column \(name): \(reason)"
        case .invalidTable(let name): "Invalid schema for \(name): check primary key, column names, and indexes."
        case .noSchema(let name): "\(name) does not provide a table schema. Projections cannot create tables."
        case .invalidIdentifier(let name): "Unsupported SQLite identifier: \(name). Names must be nonempty and contain no quote or NUL."
        }
    }
}

extension GRDB.Database {
    /// Creates a model's table and indexes atomically. Call from a versioned migration.
    public func createTable<Record: TableModel>(_ model: Record.Type) throws {
        try model.tableSchema().create(in: self)
    }
}

extension Migration {
    /// Captures schema definitions now; each table is created once when this migration runs.
    public init(_ identifier: String, tables: [any TableModel.Type]) throws {
        let schemas = try tables.map { try $0.tableSchema() }
        guard Set(schemas.map(\.name)).count == schemas.count else {
            throw SchemaError.invalidTable("Duplicate table registration")
        }
        self.init(identifier) { db in
            for schema in schemas { try schema.create(in: db) }
        }
    }
}

private protocol OptionalSchemaType {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalSchemaType {
    static var wrappedType: Any.Type { Wrapped.self }
}

private func inferStorage(_ type: Any.Type) throws -> ColumnStorage {
    if [Int.self, Int8.self, Int16.self, Int32.self, Int64.self,
        UInt.self, UInt8.self, UInt16.self, UInt32.self, UInt64.self, Bool.self].contains(where: { $0 == type }) {
        return .integer
    }
    if type == Double.self || type == Float.self { return .real }
    if type == String.self || type == Date.self { return .text }
    if type == Data.self || type == UUID.self { return .blob }
    if let raw = type as? any RawRepresentable.Type { return try rawStorage(raw) }
    throw SchemaError.unsupportedType(String(reflecting: type))
}

private func rawStorage<T: RawRepresentable>(_ type: T.Type) throws -> ColumnStorage {
    try inferStorage(T.RawValue.self)
}

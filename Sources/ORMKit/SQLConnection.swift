import Foundation
internal import GRDB

public enum ForeignKeyAction: Sendable {
    case cascade, restrict, setNull, setDefault
    var grdb: GRDB.Database.ForeignKeyAction {
        switch self {
        case .cascade: .cascade
        case .restrict: .restrict
        case .setNull: .setNull
        case .setDefault: .setDefault
        }
    }
}

/// A connection scoped to a synchronous migration, read or write closure. Do not retain it.
public struct SQLConnection {
    let database: GRDB.Database

    public func execute(sql: String, arguments: [(any SQLValueConvertible)?] = []) throws {
        try database.execute(sql: sql, arguments: StatementArguments(arguments.map { $0?.sqlValue.databaseValue ?? .null }))
    }
    public func tableExists(_ name: String) throws -> Bool { try database.tableExists(name) }
    public func columns(in table: String) throws -> [SQLColumnInfo] {
        try database.columns(in: table).map { SQLColumnInfo(name: $0.name) }
    }
    public func create(index: String, on table: String, columns: [String], unique: Bool = false) throws {
        try database.create(index: index, on: table, columns: columns, unique: unique)
    }
}

public struct SQLColumnInfo: Sendable {
    public let name: String
}

/// An owned row; its values do not depend on a live database connection.
public struct SQLRow: Sendable {
    private let values: [String: SQLValue]
    init(_ row: GRDB.Row) { values = Dictionary(row.map { ($0.0, SQLValue($0.1)) }, uniquingKeysWith: { first, _ in first }) }
    public subscript<Value: SQLValueConvertible>(_ column: String) -> Value {
        guard let value = values[column], let result = Value.fromSQLValue(value) else { preconditionFailure("Missing or incompatible SQL column: \(column)") }
        return result
    }
    public static func fetchAll(_ connection: SQLConnection, sql: String, arguments: [(any SQLValueConvertible)?] = []) throws -> [SQLRow] {
        try GRDB.Row.fetchAll(connection.database, sql: sql, arguments: StatementArguments(arguments.map { $0?.sqlValue.databaseValue ?? .null })).map(SQLRow.init)
    }
}

extension SQLValueConvertible {
    public static func fetchOne(_ connection: SQLConnection, sql: String, arguments: [(any SQLValueConvertible)?] = []) throws -> Self? {
        let rows = try GRDB.Row.fetchOne(connection.database, sql: sql, arguments: StatementArguments(arguments.map { $0?.sqlValue.databaseValue ?? .null }))
        guard let row = rows else { return nil }
        let value: GRDB.DatabaseValue = row[0]
        guard value != .null else { return nil }
        guard let converted = Self.fromSQLValue(SQLValue(value)) else { throw SQLValueError.incompatibleValue }
        return converted
    }
}

public enum SQLValueError: Error { case incompatibleValue }

/// A serial synchronous connection for tests, migrations and command-line tools.
public final class DatabaseQueue: Sendable {
    private let queue: GRDB.DatabaseQueue
    public init(path: String = ":memory:") throws { queue = try GRDB.DatabaseQueue(path: path) }
    public func write<Value>(_ updates: (SQLConnection) throws -> Value) throws -> Value {
        try queue.write { try updates(SQLConnection(database: $0)) }
    }
    public func read<Value>(_ fetch: (SQLConnection) throws -> Value) throws -> Value {
        try queue.read { try fetch(SQLConnection(database: $0)) }
    }
}

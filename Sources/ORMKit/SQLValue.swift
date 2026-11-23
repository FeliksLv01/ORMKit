import Foundation
internal import GRDB

/// A SQLite value independent of the database implementation.
public enum SQLValue: Sendable, Equatable {
    case null, integer(Int64), real(Double), text(String), blob(Data)

    init(_ value: GRDB.DatabaseValue) {
        switch value.storage {
        case .null: self = .null
        case .int64(let value): self = .integer(value)
        case .double(let value): self = .real(value)
        case .string(let value): self = .text(value)
        case .blob(let value): self = .blob(value)
        }
    }
    var databaseValue: GRDB.DatabaseValue {
        switch self {
        case .null: .null
        case .integer(let value): value.databaseValue
        case .real(let value): value.databaseValue
        case .text(let value): value.databaseValue
        case .blob(let value): value.databaseValue
        }
    }
}

/// Converts values bound to SQL parameters and typed query columns.
public protocol SQLValueConvertible: Sendable {
    var sqlValue: SQLValue { get }
    static func fromSQLValue(_ value: SQLValue) -> Self?
}

extension SQLValue: SQLValueConvertible {
    public var sqlValue: SQLValue { self }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { value }
}

extension SQLValueConvertible where Self: RawRepresentable, RawValue: SQLValueConvertible {
    public var sqlValue: SQLValue { rawValue.sqlValue }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { RawValue.fromSQLValue(value).flatMap(Self.init(rawValue:)) }
}

extension Optional: SQLValueConvertible where Wrapped: SQLValueConvertible {
    public var sqlValue: SQLValue { self?.sqlValue ?? .null }
    public static func fromSQLValue(_ value: SQLValue) -> Self? {
        if value == .null { return .some(nil) }
        return Wrapped.fromSQLValue(value).map { .some($0) }
    }
}

extension String: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Bool: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Int: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Int8: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Int16: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Int32: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Int64: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension UInt: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension UInt8: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension UInt16: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension UInt32: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension UInt64: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Double: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Float: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Data: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension Date: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

extension UUID: SQLValueConvertible {
    public var sqlValue: SQLValue { SQLValue(databaseValue) }
    public static func fromSQLValue(_ value: SQLValue) -> Self? { fromDatabaseValue(value.databaseValue) }
}

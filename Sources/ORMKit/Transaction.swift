import GRDB

public struct TableAssignment: Sendable {
    let column: String
    let value: DatabaseValue
}

extension TableColumn where Value: DatabaseValueConvertible {
    public func set(to value: Value) -> TableAssignment {
        TableAssignment(column: name, value: value.databaseValue)
    }
}

extension TableColumn where Value == String {
    /// Literal substring matching; percent, underscore and backslash are escaped, never interpreted as wildcards.
    public func contains(_ text: String) -> TablePredicate {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        return TablePredicate(expression: GRDB.Column(name).like("%\(escaped)%", escape: "\\"))
    }
}

/// A typed row-value comparison lets SQLite seek into a composite index, rather than scan an OR predicate.
public func before<A, B>(
    _ first: TableColumn<A>, _ second: TableColumn<B>, _ firstValue: A, _ secondValue: B
) -> TablePredicate
where
    A: DatabaseValueConvertible & Comparable & Sendable,
    B: DatabaseValueConvertible & Comparable & Sendable
{
    TablePredicate(
        expression: SQL(
            "(\(sql: quoteIdentifier(first.name)), \(sql: quoteIdentifier(second.name))) < (\(firstValue), \(secondValue))"
        ).sqlExpression)
}

public enum TableMutationError: Error {
    case emptyAssignments, duplicateColumn, limitedMutation
}

/// Valid only inside its database closure. It is deliberately not Sendable and cannot cross executors.
public struct Transaction {
    let database: GRDB.Database
    public func table<Record: TableModel>(_ record: Record.Type) -> TransactionTable<Record> {
        TransactionTable(database: database)
    }
}

public struct TransactionTable<Record: TableModel> {
    let database: GRDB.Database
    var predicate: TablePredicate?
    var ordering: TableOrder?
    var limitCount: Int?

    public func `where`(_ makePredicate: (Record.Columns) -> TablePredicate) -> Self {
        var result = self
        let next = makePredicate(Record.columns)
        result.predicate = predicate.map { $0 && next } ?? next
        return result
    }

    public func order(_ makeOrder: (Record.Columns) -> TableOrder) -> Self {
        var result = self
        result.ordering = makeOrder(Record.columns)
        return result
    }

    public func limit(_ count: Int) -> Self {
        var result = self
        result.limitCount = max(0, count)
        return result
    }

    private var request: QueryInterfaceRequest<Record> {
        TableQuery<Record>.request(predicate: predicate, ordering: ordering, limitCount: limitCount)
    }

    public func fetchAll() throws -> [Record] { try request.fetchAll(database) }
    public func fetchOne() throws -> Record? { try request.fetchOne(database) }
    public func count() throws -> Int { try request.fetchCount(database) }
    public func exists() throws -> Bool { limitCount == 0 ? false : try limit(1).count() > 0 }

    /// A single-column subquery; executes as SQL IN without materializing an ID array.
    public func contains<Value>(
        _ column: (Record.Columns) -> TableColumn<Value>, value: TableColumn<Value>
    ) -> TablePredicate {
        TablePredicate(
            expression: request.select(GRDB.Column(column(Record.columns).name)).contains(
                GRDB.Column(value.name)))
    }

    public func contains<Value>(
        _ column: (Record.Columns) -> TableColumn<Value?>, value: TableColumn<Value>
    ) -> TablePredicate {
        TablePredicate(
            expression: request.select(GRDB.Column(column(Record.columns).name)).contains(
                GRDB.Column(value.name)))
    }

    /// Omitted columns retain SQLite defaults (including an auto-increment primary key).
    public func insert(_ fields: (Record.Columns) -> [TableAssignment]) throws {
        let assignments = try validated(fields(Record.columns))
        let columns = assignments.map { quoteIdentifier($0.column) }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: assignments.count).joined(separator: ", ")
        try database.execute(
            sql:
                "INSERT INTO \(quoteIdentifier(Record.databaseTableName)) (\(columns)) VALUES (\(placeholders))",
            arguments: StatementArguments(assignments.map(\.value)))
    }

    @discardableResult public func update(_ fields: (Record.Columns) -> [TableAssignment]) throws
        -> Int
    {
        guard limitCount == nil else { throw TableMutationError.limitedMutation }
        let assignments = try validated(fields(Record.columns))
        return try request.updateAll(
            database, assignments.map { GRDB.Column($0.column).set(to: $0.value) })
    }

    @discardableResult public func delete() throws -> Int {
        guard limitCount == nil else { throw TableMutationError.limitedMutation }
        return try request.deleteAll(database)
    }

    private func validated(_ assignments: [TableAssignment]) throws -> [TableAssignment] {
        guard !assignments.isEmpty else { throw TableMutationError.emptyAssignments }
        guard Set(assignments.map(\.column)).count == assignments.count else {
            throw TableMutationError.duplicateColumn
        }
        return assignments
    }
}

private func quoteIdentifier(_ name: String) -> String {
    "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

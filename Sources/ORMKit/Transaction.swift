internal import GRDB

public struct TableAssignment: Sendable {
    let column: String
    let value: DatabaseValue
}

extension TableColumn where Value: SQLValueConvertible {
    public func set(to value: Value) -> TableAssignment {
        TableAssignment(column: name, value: value.sqlValue.databaseValue)
    }
}

/// A typed row-value comparison `(first, second) < (firstValue, secondValue)` for composite index seeks.
public func before<A, B>(
    _ first: TableColumn<A>, _ second: TableColumn<B>, _ firstValue: A, _ secondValue: B
) -> TablePredicate
where
    A: SQLValueConvertible & Comparable & Sendable,
    B: SQLValueConvertible & Comparable & Sendable
{
    TablePredicate(
        expression: SQL(
            "(\(sql: quoteIdentifier(first.name)), \(sql: quoteIdentifier(second.name))) < (\(firstValue.sqlValue.databaseValue), \(secondValue.sqlValue.databaseValue))"
        ).sqlExpression
    )
}

/// A typed row-value comparison `(first, second) > (firstValue, secondValue)` for composite index seeks.
public func after<A, B>(
    _ first: TableColumn<A>, _ second: TableColumn<B>, _ firstValue: A, _ secondValue: B
) -> TablePredicate
where
    A: SQLValueConvertible & Comparable & Sendable,
    B: SQLValueConvertible & Comparable & Sendable
{
    TablePredicate(
        expression: SQL(
            "(\(sql: quoteIdentifier(first.name)), \(sql: quoteIdentifier(second.name))) > (\(firstValue.sqlValue.databaseValue), \(secondValue.sqlValue.databaseValue))"
        ).sqlExpression
    )
}

public enum TableMutationError: Error, Equatable {
    case emptyAssignments
    case duplicateColumn
    case limitedMutation
}

/// Valid only inside its database closure. It is deliberately not `Sendable` and cannot cross executors.
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
    var offsetCount: Int?

    public func filter(_ makePredicate: (Record.Columns) -> TablePredicate) -> Self {
        var result = self
        let next = makePredicate(Record.columns)
        result.predicate = predicate.map { $0 && next } ?? next
        return result
    }

    public func orderBy(_ makeOrders: (Record.Columns) -> [TableOrder]) -> Self {
        var result = self
        result.ordering = TableOrder.combined(makeOrders(Record.columns))
        return result
    }

    public func limit(_ count: Int) -> Self {
        var result = self
        result.limitCount = max(0, count)
        return result
    }

    public func offset(_ count: Int) -> Self {
        var result = self
        result.offsetCount = max(0, count)
        return result
    }

    private var request: QueryInterfaceRequest<RecordAdapter<Record>> {
        TableQuery<Record>.request(
            predicate: predicate,
            ordering: ordering,
            limitCount: limitCount,
            offsetCount: offsetCount
        )
    }

    public func fetch() throws -> [Record] {
        try request.fetchAll(database).map(\.model)
    }

    public func first() throws -> Record? {
        let effectiveLimit = limitCount == 0 ? 0 : 1
        return try TableQuery<Record>.request(
            predicate: predicate,
            ordering: ordering,
            limitCount: effectiveLimit,
            offsetCount: offsetCount
        ).fetchOne(database)?.model
    }

    public func find(_ id: Record.PrimaryKeyValue) throws -> Record? {
        try RecordAdapter<Record>
            .filter(GRDB.Column(Record.primaryKeyColumn) == id.sqlValue.databaseValue)
            .fetchOne(database)?
            .model
    }

    public func count() throws -> Int {
        try request.fetchCount(database)
    }

    public func exists() throws -> Bool {
        guard limitCount != 0 else { return false }
        return try first() != nil
    }

    /// A single-column subquery; executes as SQL `IN (SELECT ...)` without materializing an ID array.
    public func contains<Value>(
        _ column: (Record.Columns) -> TableColumn<Value>,
        value: TableColumn<Value>
    ) -> TablePredicate {
        TablePredicate(
            expression: request.select(GRDB.Column(column(Record.columns).name)).contains(
                GRDB.Column(value.name)
            )
        )
    }

    public func contains<Value>(
        _ column: (Record.Columns) -> TableColumn<Value?>,
        value: TableColumn<Value>
    ) -> TablePredicate {
        TablePredicate(
            expression: request.select(GRDB.Column(column(Record.columns).name)).contains(
                GRDB.Column(value.name)
            )
        )
    }

    public func insert(_ record: Record) throws {
        try RecordAdapter(model: record).insert(database)
    }

    public func insert(_ records: [Record]) throws {
        for record in records {
            try RecordAdapter(model: record).insert(database)
        }
    }

    /// Omitted columns retain SQLite defaults (including an auto-increment primary key).
    public func insert(_ fields: (inout TableChanges<Record>) -> Void) throws {
        var patch = TableChanges<Record>()
        fields(&patch)
        try insert { _ in patch.assignments }
    }

    public func insert(_ fields: (Record.Columns) -> [TableAssignment]) throws {
        let assignments = try validated(fields(Record.columns))
        let columns = assignments.map { quoteIdentifier($0.column) }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: assignments.count).joined(separator: ", ")
        try database.execute(
            sql: "INSERT INTO \(quoteIdentifier(Record.databaseTableName)) (\(columns)) VALUES (\(placeholders))",
            arguments: StatementArguments(assignments.map(\.value))
        )
    }

    public func upsert(_ record: Record) throws {
        try RecordAdapter(model: record).save(database)
    }

    public func upsert(_ records: [Record]) throws {
        for record in records {
            try RecordAdapter(model: record).save(database)
        }
    }

    public func update(_ record: Record) throws {
        try RecordAdapter(model: record).update(database)
    }

    @discardableResult
    public func update(_ changes: (inout TableChanges<Record>) -> Void) throws -> Int {
        var patch = TableChanges<Record>()
        changes(&patch)
        return try update { _ in patch.assignments }
    }

    @discardableResult
    public func update(_ fields: (Record.Columns) -> [TableAssignment]) throws -> Int {
        guard limitCount == nil, offsetCount == nil else { throw TableMutationError.limitedMutation }
        let assignments = try validated(fields(Record.columns))
        return try request.updateAll(
            database,
            assignments.map { GRDB.Column($0.column).set(to: $0.value) }
        )
    }

    @discardableResult
    public func delete(_ record: Record) throws -> Bool {
        try RecordAdapter(model: record).delete(database)
    }

    @discardableResult
    public func delete(id: Record.PrimaryKeyValue) throws -> Bool {
        try RecordAdapter<Record>
            .filter(GRDB.Column(Record.primaryKeyColumn) == id.sqlValue.databaseValue)
            .deleteAll(database) > 0
    }

    @discardableResult
    public func delete() throws -> Int {
        guard limitCount == nil, offsetCount == nil else { throw TableMutationError.limitedMutation }
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

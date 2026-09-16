import Foundation
import GRDB

/// A named migration. Existing migrations must not be edited after release.
public struct Migration: Sendable {
    public let identifier: String
    let migrate: @Sendable (GRDB.Database) throws -> Void

    public init(_ identifier: String, migrate: @escaping @Sendable (GRDB.Database) throws -> Void) {
        self.identifier = identifier
        self.migrate = migrate
    }
}

/// Owns a SQLite connection pool and applies explicit migrations at opening.
public final class Database: Sendable {
    let pool: DatabasePool

    public init(at url: URL, migrations: [Migration] = []) throws {
        let pool = try DatabasePool(path: url.path)
        var migrator = DatabaseMigrator()
        for migration in migrations {
            migrator.registerMigration(migration.identifier, migrate: migration.migrate)
        }
        try migrator.migrate(pool)
        self.pool = pool
    }

    public func table<Record: TableModel>(_ record: Record.Type) -> Table<Record> {
        Table(pool: pool)
    }

    /// One atomic, non-suspending transaction. Do not retain its scoped tables outside the closure.
    public func transaction<Value: Sendable>(
        _ updates: @escaping @Sendable (Transaction) throws -> Value
    ) async throws -> Value {
        try await pool.write { try updates(Transaction(database: $0)) }
    }

    /// Multiple typed reads from one consistent snapshot, on the reader pool.
    public func snapshot<Value: Sendable>(_ fetch: @escaping @Sendable (Transaction) throws -> Value)
        async throws -> Value
    {
        try await pool.read { try fetch(Transaction(database: $0)) }
    }

    /// Executes custom SQL or multiple operations in one transaction.
    public func write<Value: Sendable>(_ updates: @escaping @Sendable (GRDB.Database) throws -> Value)
        async throws -> Value
    {
        try await pool.write(updates)
    }

    /// Executes a custom read using the same pool as table queries.
    public func read<Value: Sendable>(_ fetch: @escaping @Sendable (GRDB.Database) throws -> Value)
        async throws -> Value
    {
        try await pool.read(fetch)
    }
}

public struct Table<Record: TableModel>: Sendable {
    let pool: DatabasePool

    public func filter(_ predicate: (Record.Columns) -> TablePredicate) -> TableQuery<Record> { all().filter(predicate) }
    public func orderBy(_ orders: (Record.Columns) -> [TableOrder]) -> TableQuery<Record> { all().orderBy(orders) }
    public func limit(_ count: Int) -> TableQuery<Record> { all().limit(count) }
    public func fetch() async throws -> [Record] { try await all().fetch() }
    public func first() async throws -> Record? { try await all().first() }
    public func count() async throws -> Int { try await all().count() }
    public func exists() async throws -> Bool { try await all().exists() }

    public func insert(_ fields: (inout TableChanges<Record>) -> Void) async throws {
        var patch = TableChanges<Record>()
        fields(&patch)
        let assignments = patch.assignments
        try await pool.write { db in try TransactionTable<Record>(database: db).insert { _ in assignments } }
    }

    @discardableResult public func update(_ changes: (inout TableChanges<Record>) -> Void) async throws -> Int {
        try await all().update(changes)
    }

    @discardableResult public func delete() async throws -> Int { try await all().delete() }

    public func all() -> TableQuery<Record> {
        TableQuery(pool: pool)
    }

    public func `where`(_ makePredicate: (Record.Columns) -> TablePredicate) -> TableQuery<Record> {
        all().where(makePredicate)
    }

    public func order(_ makeOrder: (Record.Columns) -> TableOrder) -> TableQuery<Record> {
        all().order(makeOrder)
    }

    public func fetchAll() async throws -> [Record] {
        try await all().fetchAll()
    }

    public func insert(_ record: Record) async throws {
        try await pool.write { db in try record.insert(db) }
    }

    public func update(_ record: Record) async throws {
        try await pool.write { db in try record.update(db) }
    }

    @discardableResult
    public func delete(_ record: Record) async throws -> Bool {
        try await pool.write { db in try record.delete(db) }
    }
}

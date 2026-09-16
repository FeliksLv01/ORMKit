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

    /// Executes custom SQL or multiple operations in one transaction.
    public func write<Value: Sendable>(_ updates: @escaping @Sendable (GRDB.Database) throws -> Value) async throws -> Value {
        try await pool.write(updates)
    }

    /// Executes a custom read using the same pool as table queries.
    public func read<Value: Sendable>(_ fetch: @escaping @Sendable (GRDB.Database) throws -> Value) async throws -> Value {
        try await pool.read(fetch)
    }
}

public struct Table<Record: TableModel>: Sendable {
    let pool: DatabasePool

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

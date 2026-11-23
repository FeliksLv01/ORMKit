import Foundation
internal import GRDB

/// SQLite journal mode for file-backed databases.
public enum JournalMode: Sendable, Equatable {
    /// Write-Ahead Logging (default): concurrent readers with snapshot isolation and serialized writer.
    case wal
    /// Traditional rollback journal mode using a serialized connection queue.
    case delete
}

/// Configuration for opening an `ORMKit.Database`.
public struct DatabaseConfiguration: Sendable {
    public var journalMode: JournalMode
    public var foreignKeysEnabled: Bool
    public var busyTimeout: TimeInterval
    public var readonly: Bool

    public init(
        journalMode: JournalMode = .wal,
        foreignKeysEnabled: Bool = true,
        busyTimeout: TimeInterval = 5.0,
        readonly: Bool = false
    ) {
        self.journalMode = journalMode
        self.foreignKeysEnabled = foreignKeysEnabled
        self.busyTimeout = busyTimeout
        self.readonly = readonly
    }

    func makeGRDBConfiguration() -> GRDB.Configuration {
        var config = GRDB.Configuration()
        config.foreignKeysEnabled = foreignKeysEnabled
        config.readonly = readonly
        if busyTimeout > 0 {
            config.busyMode = .timeout(busyTimeout)
        }
        return config
    }
}

/// A named migration. Existing migrations must not be edited after release.
public struct Migration: Sendable {
    public let identifier: String
    let migrate: @Sendable (SQLConnection) throws -> Void

    public init(_ identifier: String, migrate: @escaping @Sendable (SQLConnection) throws -> Void) {
        self.identifier = identifier
        self.migrate = migrate
    }
}

/// Owns a SQLite database connection (WAL pool for files by default, queue for in-memory) and applies explicit migrations.
public final class Database: Sendable {
    public let path: String
    let writer: any GRDB.DatabaseWriter

    public init(
        at url: URL,
        configuration: DatabaseConfiguration = .init(),
        migrations: [Migration] = []
    ) throws {
        let grdbConfig = configuration.makeGRDBConfiguration()
        let writer: any GRDB.DatabaseWriter
        switch configuration.journalMode {
        case .wal:
            writer = try GRDB.DatabasePool(path: url.path, configuration: grdbConfig)
        case .delete:
            writer = try GRDB.DatabaseQueue(path: url.path, configuration: grdbConfig)
        }
        if !configuration.readonly, !migrations.isEmpty {
            try Self.runMigrations(migrations, on: writer)
        }
        self.writer = writer
        self.path = url.path
    }

    private init(writer: any GRDB.DatabaseWriter, path: String) {
        self.writer = writer
        self.path = path
    }

    /// Creates an in-memory SQLite database, ideal for tests and ephemeral caches.
    public static func inMemory(
        configuration: DatabaseConfiguration = .init(),
        migrations: [Migration] = []
    ) throws -> Database {
        var grdbConfig = configuration.makeGRDBConfiguration()
        grdbConfig.readonly = false
        let queue = try GRDB.DatabaseQueue(configuration: grdbConfig)
        if !migrations.isEmpty {
            try runMigrations(migrations, on: queue)
        }
        return Database(writer: queue, path: ":memory:")
    }

    private static func runMigrations(_ migrations: [Migration], on writer: any GRDB.DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        for migration in migrations {
            migrator.registerMigration(migration.identifier) { db in
                try migration.migrate(SQLConnection(database: db))
            }
        }
        try migrator.migrate(writer)
    }

    public func close() throws {
        try writer.close()
    }

    public func table<Record: TableModel>(_ record: Record.Type) -> Table<Record> {
        Table(writer: writer)
    }

    /// One atomic, non-suspending transaction. Do not retain its scoped tables outside the closure.
    public func transaction<Value: Sendable>(
        _ updates: @escaping @Sendable (Transaction) throws -> Value
    ) async throws -> Value {
        try await writer.write { try updates(Transaction(database: $0)) }
    }

    /// Multiple typed reads from one consistent snapshot.
    public func snapshot<Value: Sendable>(
        _ fetch: @escaping @Sendable (Transaction) throws -> Value
    ) async throws -> Value {
        try await writer.read { try fetch(Transaction(database: $0)) }
    }

    /// Executes custom SQL or multiple operations in one transaction.
    public func write<Value: Sendable>(
        _ updates: @escaping @Sendable (SQLConnection) throws -> Value
    ) async throws -> Value {
        try await writer.write { try updates(SQLConnection(database: $0)) }
    }

    /// Executes a custom read using the same database connection.
    public func read<Value: Sendable>(
        _ fetch: @escaping @Sendable (SQLConnection) throws -> Value
    ) async throws -> Value {
        try await writer.read { try fetch(SQLConnection(database: $0)) }
    }
}

public struct Table<Record: TableModel>: Sendable {
    let writer: any GRDB.DatabaseWriter

    public func all() -> TableQuery<Record> {
        TableQuery(writer: writer)
    }

    public func filter(_ predicate: (Record.Columns) -> TablePredicate) -> TableQuery<Record> {
        all().filter(predicate)
    }

    public func orderBy(_ orders: (Record.Columns) -> [TableOrder]) -> TableQuery<Record> {
        all().orderBy(orders)
    }

    public func limit(_ count: Int) -> TableQuery<Record> {
        all().limit(count)
    }

    public func offset(_ count: Int) -> TableQuery<Record> {
        all().offset(count)
    }

    public func fetch() async throws -> [Record] {
        try await all().fetch()
    }

    public func first() async throws -> Record? {
        try await all().first()
    }

    public func find(_ id: Record.PrimaryKeyValue) async throws -> Record? {
        try await writer.read { db in
            try TransactionTable<Record>(database: db).find(id)
        }
    }

    public func count() async throws -> Int {
        try await all().count()
    }

    public func exists() async throws -> Bool {
        try await all().exists()
    }

    public func observe() -> TableObservation<Record> {
        all().observe()
    }

    public func insert(_ record: Record) async throws {
        try await writer.write { db in
            try RecordAdapter(model: record).insert(db)
        }
    }

    /// Inserts multiple records atomically inside one transaction.
    public func insert(_ records: [Record]) async throws {
        guard !records.isEmpty else { return }
        try await writer.write { db in
            for record in records {
                try RecordAdapter(model: record).insert(db)
            }
        }
    }

    /// Partial insert preserving database defaults and auto-increment primary keys.
    public func insert(_ fields: (inout TableChanges<Record>) -> Void) async throws {
        var patch = TableChanges<Record>()
        fields(&patch)
        let assignments = patch.assignments
        try await writer.write { db in
            try TransactionTable<Record>(database: db).insert { _ in assignments }
        }
    }

    /// Inserts or updates a record based on its primary key.
    public func upsert(_ record: Record) async throws {
        try await writer.write { db in
            try RecordAdapter(model: record).save(db)
        }
    }

    /// Inserts or updates multiple records atomically inside one transaction.
    public func upsert(_ records: [Record]) async throws {
        guard !records.isEmpty else { return }
        try await writer.write { db in
            for record in records {
                try RecordAdapter(model: record).save(db)
            }
        }
    }

    public func update(_ record: Record) async throws {
        try await writer.write { db in
            try RecordAdapter(model: record).update(db)
        }
    }

    @discardableResult
    public func update(_ changes: (inout TableChanges<Record>) -> Void) async throws -> Int {
        try await all().update(changes)
    }

    @discardableResult
    public func delete(_ record: Record) async throws -> Bool {
        try await writer.write { db in
            try RecordAdapter(model: record).delete(db)
        }
    }

    @discardableResult
    public func delete(id: Record.PrimaryKeyValue) async throws -> Bool {
        try await writer.write { db in
            try TransactionTable<Record>(database: db).delete(id: id)
        }
    }

    @discardableResult
    public func delete() async throws -> Int {
        try await all().delete()
    }
}

import Foundation
import ORMKit
import XCTest

@Table("parents")
private struct SchemaParent: Sendable {
    @PrimaryKey var id: String
}

private enum SchemaState: String, Codable, Sendable { case active, archived }

@Table("children")
private struct SchemaChild: Sendable {
    @PrimaryKey(autoIncrement: true) var id: Int64
    @Column(references: .init("parents", column: "id", onDelete: .cascade)) var parentID: String
    @Column("display_name", defaultValue: .text("untitled")) var name: String
    @Column(defaultValue: .integer(0), check: "count >= 0") var count: Int
    @Column(defaultValue: .text("active")) var state: SchemaState
    var payload: Data?

    static var schemaIndexes: [TableIndex] {
        [TableIndex("one_active_child", columns: [columns.parentID.name], unique: true, conditionSQL: "state = 'active'")]
    }
}

@Table("children", schema: false)
private struct SchemaProjection: Sendable {
    @PrimaryKey var id: Int64
}

@Table("invalid")
private struct InvalidAutoIncrement: Sendable {
    @PrimaryKey(autoIncrement: true) var id: String
}

@Table("quoted\"table")
private struct QuotedRecord: Sendable {
    @PrimaryKey var id: Int
    @Column("quoted\"column", unique: true) var value: String
}

@Table("values_table")
private struct FoundationRecord: Sendable, Equatable {
    @PrimaryKey var id: UUID
    var date: Date
    var data: Data
    var flag: Bool
    var real: Double
}

@Table(#"order details"#)
private struct NamedRecord: Sendable {
    @PrimaryKey var id: Int
    @Column(nil) var `default`: String { didSet {} }
    var computed: String { `default` }
}

final class SchemaTests: XCTestCase {
    func testRawNamesKeywordsAndStoredObservers() async throws {
        let db = try Database.inMemory()
        try await db.write { conn in
            try conn.createTable(NamedRecord.self)
            try NamedRecord(id: 1, default: "kept").insert(conn)
            XCTAssertEqual(try NamedRecord.fetchOne(conn)?.default, "kept")
            XCTAssertEqual(try conn.columns(in: "order details").map(\.name), ["id", "default"])
        }
    }

    func testGeneratedSchemaDefaultsConstraintsAndCascade() async throws {
        let db = try Database.inMemory()
        try await db.write { conn in
            try conn.createTable(SchemaParent.self)
            try conn.createTable(SchemaChild.self)
            try SchemaParent(id: "p").insert(conn)
            try conn.execute(sql: "INSERT INTO children(parentID) VALUES ('p')")
            let row = try XCTUnwrap(SchemaChild.fetchOne(conn))
            XCTAssertEqual(row.id, 1)
            XCTAssertEqual(row.name, "untitled")
            XCTAssertEqual(row.count, 0)
            XCTAssertEqual(row.state, .active)
            XCTAssertNil(row.payload)
            XCTAssertThrowsError(try conn.execute(sql: "INSERT INTO children(parentID) VALUES ('p')"))
            XCTAssertThrowsError(try conn.execute(sql: "UPDATE children SET count = -1"))
            XCTAssertThrowsError(try conn.execute(sql: "INSERT INTO children(parentID) VALUES ('missing')"))
            try conn.execute(sql: "UPDATE children SET state = 'archived'")
            try conn.execute(sql: "INSERT INTO children(parentID) VALUES ('p')")
            XCTAssertEqual(try SchemaChild.fetchCount(conn), 2)
            try conn.execute(sql: "DELETE FROM parents")
            XCTAssertEqual(try SchemaChild.fetchCount(conn), 0)
            try SchemaParent(id: "p").insert(conn)
            try conn.execute(sql: "INSERT INTO children(parentID) VALUES ('p')")
            XCTAssertEqual(try SchemaChild.fetchOne(conn)?.id, 3, "AUTOINCREMENT must not reuse deleted IDs")
        }
    }

    func testMigrationRunsOnceAndPreservesDataOnReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("db.sqlite")
        let migration = Migration("v1", tables: [SchemaParent.self, SchemaChild.self])
        let first = try Database(at: url, migrations: [migration])
        try await first.table(SchemaParent.self).insert(SchemaParent(id: "kept"))
        let reopened = try Database(at: url, migrations: [migration])
        let rows = try await reopened.table(SchemaParent.self).fetch()
        XCTAssertEqual(rows.map(\.id), ["kept"])
    }

    func testInvalidSchemaAndProjectionsFailBeforeCreatingTable() async throws {
        let db = try Database.inMemory()
        try await db.write { conn in
            XCTAssertThrowsError(try conn.createTable(InvalidAutoIncrement.self))
            XCTAssertThrowsError(try conn.createTable(SchemaProjection.self))
            XCTAssertFalse(try conn.tableExists("invalid"))
            XCTAssertFalse(try conn.tableExists("children"))
        }
        XCTAssertThrowsError(try Database.inMemory(migrations: [Migration("duplicate", tables: [SchemaParent.self, SchemaParent.self])]))
        XCTAssertThrowsError(try SchemaColumn("id", type: Int?.self, primaryKey: true))
        XCTAssertThrowsError(try SchemaColumn("id", type: Bool.self, primaryKey: true, autoIncrement: true))
        XCTAssertThrowsError(try SchemaColumn("unknown", type: [String].self))
        XCTAssertEqual(try SchemaColumn("json", type: [String].self, storage: .text).storage, .text)
    }

    func testFailedIndexCreationRollsBackTable() async throws {
        let db = try Database.inMemory()
        try await db.write { conn in
            try conn.createTable(SchemaParent.self)
            try conn.create(index: "one_active_child", on: "parents", columns: ["id"])
            XCTAssertThrowsError(try conn.createTable(SchemaChild.self))
            XCTAssertFalse(try conn.tableExists("children"))
            XCTAssertTrue(try conn.tableExists("parents"))
        }
    }

    func testUnsupportedIdentifiersFailBeforeSQLExecution() async throws {
        let db = try Database.inMemory()
        try await db.write { conn in
            XCTAssertThrowsError(try conn.createTable(QuotedRecord.self)) { error in
                guard case SchemaError.invalidIdentifier = error else { return XCTFail("\(error)") }
            }
        }
    }

    func testFoundationTypesRoundTrip() async throws {
        let db = try Database.inMemory()
        try await db.write { conn in
            try conn.createTable(FoundationRecord.self)
            let record = FoundationRecord(id: UUID(), date: Date(timeIntervalSince1970: 100), data: Data([0, 1]), flag: true, real: 1.5)
            try record.insert(conn)
            XCTAssertEqual(try FoundationRecord.fetchOne(conn), record)
        }
    }
}

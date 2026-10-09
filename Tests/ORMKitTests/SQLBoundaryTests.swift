import Foundation
import ORMKit
import XCTest

private enum BoundaryState: String, Codable, SQLValueConvertible { case ready, complete }

@Table("boundary_records")
private struct BoundaryRecord: Sendable {
    @PrimaryKey var id: Int64
    var state: BoundaryState
    var note: String?
}

final class SQLBoundaryTests: XCTestCase {
    func testEnumsAndNullPatchesThroughPublicAPI() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try ORMKit.Database(at: directory.appendingPathComponent("db.sqlite"), migrations: [
            Migration("create", tables: [BoundaryRecord.self]),
        ])
        let table = database.table(BoundaryRecord.self)
        try await table.insert { $0.id = 1; $0.state = .ready; $0.note = "keep" }
        try await table.filter { $0.state == .ready }.update { $0.state = .complete; $0.note = nil }
        let rows = try await table.filter { $0.state == .complete }.fetch()
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first?.note)
    }

    func testSaveInsertsAndUpdatesExistingPrimaryKey() throws {
        let queue = try DatabaseQueue()
        try queue.write { connection in
            try BoundaryRecord.tableSchema().create(in: connection)
            let initial = BoundaryRecord(id: 1, state: .ready, note: "initial")
            try initial.save(connection)
            let updated = BoundaryRecord(id: 1, state: .complete, note: nil)
            try updated.save(connection)
            XCTAssertEqual(try BoundaryRecord.fetchCount(connection), 1)
            let fetched = try BoundaryRecord.fetchOne(connection, key: Int64(1))
            XCTAssertEqual(fetched?.state, .complete)
            XCTAssertNil(fetched?.note)
        }
    }

    func testBoundSQLAndOwnedRows() throws {
        let queue = try DatabaseQueue()
        let payload = Data([0, 1, 255])
        let malicious = "'); DROP TABLE values_table; --"
        let rows = try queue.write { connection in
            try connection.execute(sql: "CREATE TABLE values_table (name TEXT, payload BLOB, note TEXT)")
            try connection.execute(sql: "INSERT INTO values_table VALUES (?, ?, ?)", arguments: [malicious, payload, nil])
            XCTAssertTrue(try connection.tableExists("values_table"))
            XCTAssertEqual(try Int.fetchOne(connection, sql: "SELECT COUNT(*) FROM values_table"), 1)
            return try SQLRow.fetchAll(connection, sql: "SELECT * FROM values_table")
        }
        let name: String = rows[0]["name"]
        let blob: Data = rows[0]["payload"]
        let note: String? = rows[0]["note"]
        XCTAssertEqual(name, malicious)
        XCTAssertEqual(blob, payload)
        XCTAssertNil(note)
        XCTAssertEqual(String?.fromSQLValue(.null), .some(nil))
    }
}

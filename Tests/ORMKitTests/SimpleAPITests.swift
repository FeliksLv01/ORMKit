import Foundation
import ORMKit
import XCTest

@Table("simple_items")
private struct Item: Sendable {
    @PrimaryKey let id: Int64
    @Column("display_name") let name: String
    let note: String?
    let rank: Int
}

final class SimpleAPITests: XCTestCase {
    private func fixture() throws -> ORMKit.Database {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try ORMKit.Database(
            at: root.appendingPathComponent("db.sqlite"),
            migrations: [
                Migration("items") { db in
                    try db.execute(
                        sql:
                            "CREATE TABLE simple_items(id INTEGER PRIMARY KEY AUTOINCREMENT, display_name TEXT NOT NULL, note TEXT, rank INTEGER NOT NULL DEFAULT 0)"
                    )
                }
            ])
    }

    func testTypedPatchOmissionAndExplicitNullAreDifferent() async throws {
        let db = try fixture()
        let table = db.table(Item.self)
        try await table.insert {
            $0.name = "original"
            $0.note = "keep"
            $0.rank = 3
        }
        let count = try await table.filter { $0.id == 1 }.update { $0.name = "renamed" }
        XCTAssertEqual(count, 1)
        let first = try await table.first()
        let retained = try XCTUnwrap(first)
        XCTAssertEqual(retained.name, "renamed")
        XCTAssertEqual(retained.note, "keep")
        XCTAssertEqual(retained.rank, 3)
        try await table.filter { $0.id == 1 }.update { $0.note = nil }
        let cleared = try await table.first()
        XCTAssertNil(cleared?.note)
        XCTAssertEqual(cleared?.name, "renamed")
    }

    func testLastAssignmentWinsAndValuesAreBound() async throws {
        let db = try fixture()
        try await db.table(Item.self).insert { $0.name = "initial" }
        let text = "'; DROP TABLE simple_items; --"
        try await db.table(Item.self).update {
            $0.name = "ignored"
            $0.name = text
        }
        let value = try await db.table(Item.self).first()
        XCTAssertEqual(value?.name, text)
        let count = try await db.table(Item.self).count()
        XCTAssertEqual(count, 1)
    }

    func testFiftyRowsOrderedAndCountedInSQL() async throws {
        let db = try fixture()
        try await db.transaction { tx in
            for n in 0..<80 {
                try tx.table(Item.self).insert {
                    $0.name = "item"
                    $0.rank = n % 2
                }
            }
        }
        let query = db.table(Item.self).filter { $0.rank == 1 }.orderBy { [$0.rank.desc, $0.id.desc] }.limit(50)
        let rows = try await query.fetch()
        let count = try await query.count()
        let exists = try await query.exists()
        XCTAssertEqual(rows.count, 40)
        XCTAssertEqual(rows.first?.id, 80)
        XCTAssertEqual(count, 40)
        XCTAssertTrue(exists)
        let fifty = try await db.table(Item.self).limit(50).fetch()
        XCTAssertEqual(fifty.count, 50)
        let zero = try await db.table(Item.self).limit(0).first()
        XCTAssertNil(zero)
    }

    func testSameMutationSyntaxInsideTransactionAndRollback() async throws {
        enum Failure: Error { case rollback }
        let db = try fixture()
        try await db.table(Item.self).insert { $0.name = "before" }
        do {
            try await db.transaction { tx in
                try tx.table(Item.self).filter { $0.id == 1 }.update {
                    $0.name = "rolled back"
                    $0.note = nil
                }
                XCTAssertEqual(try tx.table(Item.self).first()?.name, "rolled back")
                throw Failure.rollback
            }
            XCTFail("Expected rollback")
        } catch Failure.rollback {}
        let value = try await db.table(Item.self).first()
        XCTAssertEqual(value?.name, "before")
        let deleted = try await db.table(Item.self).filter { $0.id == 1 }.delete()
        XCTAssertEqual(deleted, 1)
    }

    func testEmptyAndLimitedUpdatesAreRejected() async throws {
        let db = try fixture()
        try await db.table(Item.self).insert { $0.name = "unchanged" }
        do {
            try await db.table(Item.self).update { _ in }
            XCTFail("Expected error")
        } catch TableMutationError.emptyAssignments {}
        do {
            try await db.table(Item.self).limit(1).update { $0.name = "bad" }
            XCTFail("Expected error")
        } catch TableMutationError.limitedMutation {}
        let value = try await db.table(Item.self).first()
        XCTAssertEqual(value?.name, "unchanged")
    }
}

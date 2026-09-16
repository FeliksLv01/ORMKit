import Foundation
import ORMKit
import XCTest

@Table("entries")
private struct Entry: Sendable, Equatable {
    @PrimaryKey let sequence: Int64
    let title: String
    let updated: Double
    let parent: Int64?
}

final class TransactionTests: XCTestCase {
    private func fixture() throws -> ORMKit.Database {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try ORMKit.Database(
            at: directory.appendingPathComponent("test.sqlite"),
            migrations: [
                Migration("entries") { db in
                    try db.execute(
                        sql:
                            "CREATE TABLE entries(sequence INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL DEFAULT '', updated REAL NOT NULL, parent INTEGER); CREATE INDEX entry_page ON entries(updated DESC, sequence DESC)"
                    )
                }
            ])
    }

    func testLimitFiftyAndCompositeCursorDoNotRepeatTies() async throws {
        let db = try fixture()
        try await db.transaction { tx in
            for _ in 0..<120 { try tx.table(Entry.self).insert { [$0.updated.set(to: 10)] } }
        }
        let first = try await db.table(Entry.self).order { $0.updated.desc.then($0.sequence.desc) }
            .limit(50).fetchAll()
        XCTAssertEqual(first.count, 50)
        let last = try XCTUnwrap(first.last)
        let second = try await db.table(Entry.self).where {
            before($0.updated, $0.sequence, last.updated, last.sequence)
        }
        .order { $0.updated.desc.then($0.sequence.desc) }.limit(50).fetchAll()
        XCTAssertEqual(second.count, 50)
        XCTAssertEqual(Set((first + second).map(\.sequence)).count, 100)
        XCTAssertEqual(first.first?.sequence, 120)
        XCTAssertEqual(second.first?.sequence, 70)
    }

    func testFieldUpdatesAndDeletesStayInsideTransaction() async throws {
        let db = try fixture()
        try await db.transaction { tx in
            let table = tx.table(Entry.self)
            try table.insert { [$0.title.set(to: "before"), $0.updated.set(to: 1)] }
            try table.insert { [$0.title.set(to: "keep"), $0.updated.set(to: 2)] }
            XCTAssertEqual(
                try table.where { $0.title == "before" }.update { [$0.title.set(to: "after")] }, 1)
            XCTAssertEqual(try table.where { $0.title == "after" }.fetchOne()?.updated, 1)
            XCTAssertEqual(try table.where { $0.title == "keep" }.delete(), 1)
            XCTAssertEqual(try table.count(), 1)
        }
        let title = try await db.table(Entry.self).all().fetchOne()?.title
        XCTAssertEqual(title, "after")
    }

    func testFailureRollsBackAllMutations() async throws {
        enum Expected: Error { case rollback }
        let db = try fixture()
        do {
            try await db.transaction { tx in
                try tx.table(Entry.self).insert { [$0.updated.set(to: 1)] }
                throw Expected.rollback
            }
            XCTFail("Expected rollback")
        } catch Expected.rollback {}
        let rows = try await db.table(Entry.self).fetchAll()
        XCTAssertTrue(rows.isEmpty)
    }

    func testZeroAndNegativeLimitsNeverReturnARow() async throws {
        let db = try fixture()
        try await db.transaction { try $0.table(Entry.self).insert { [$0.updated.set(to: 1)] } }
        let zero = try await db.table(Entry.self).all().limit(0).fetchOne()
        let negative = try await db.table(Entry.self).all().limit(-1).fetchAll()
        XCTAssertNil(zero)
        XCTAssertTrue(negative.isEmpty)
        try await db.snapshot { tx in
            XCTAssertFalse(try tx.table(Entry.self).limit(0).exists())
            XCTAssertEqual(try tx.table(Entry.self).limit(0).count(), 0)
        }
    }

    func testLiteralSearchAndSubquery() async throws {
        let db = try fixture()
        try await db.transaction { tx in
            let table = tx.table(Entry.self)
            try table.insert { [$0.title.set(to: "100%_value"), $0.updated.set(to: 1)] }
            try table.insert {
                [$0.title.set(to: "100xxvalue"), $0.updated.set(to: 1), $0.parent.set(to: 1)]
            }
            XCTAssertEqual(try table.where { $0.title.contains("%_") }.count(), 1)
            let related = table.where { $0.parent != nil }
            let parents = try table.where { related.contains({ $0.parent }, value: $0.sequence) }
                .fetchAll()
            XCTAssertEqual(parents.map(\.sequence), [1])
        }
    }

    func testRejectsAmbiguousMutationsWithoutChangingRows() async throws {
        let db = try fixture()
        try await db.transaction { tx in
            let table = tx.table(Entry.self)
            try table.insert { [$0.updated.set(to: 1)] }
            XCTAssertThrowsError(try table.limit(1).delete())
            XCTAssertThrowsError(try table.limit(1).update { [$0.title.set(to: "bad")] })
            XCTAssertThrowsError(try table.update { _ in [] })
            XCTAssertThrowsError(try table.update { [$0.title.set(to: "a"), $0.title.set(to: "b")] })
            XCTAssertEqual(try table.fetchOne()?.title, "")
        }
    }
}

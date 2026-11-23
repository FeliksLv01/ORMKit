import Foundation
import ORMKit
import XCTest

@Table("messages")
private struct Message: Sendable, Equatable {
    @PrimaryKey var id: String
    @Column("chat_id") var chatID: String
    var text: String
    var score: Int
    var tag: String?
}

final class ORMKitTests: XCTestCase {
    func testFileDatabaseUsesWALByDefault() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let database = try Database(
            at: dir.appendingPathComponent("wal.sqlite"),
            migrations: [Migration("create_messages", tables: [Message.self])]
        )
        let mode = try await database.read { conn in
            try String.fetchOne(conn, sql: "PRAGMA journal_mode")
        }
        XCTAssertEqual(mode?.lowercased(), "wal")
    }

    func testCRUDFindUpsertBatchAndPredicates() async throws {
        let database = try Database.inMemory(migrations: [
            Migration("create_messages", tables: [Message.self]),
        ])
        let messages = database.table(Message.self)

        let first = Message(id: "1", chatID: "a", text: "hello_world", score: 10, tag: "pinned")
        let second = Message(id: "2", chatID: "a", text: "hello%swift", score: 20, tag: nil)
        let third = Message(id: "3", chatID: "b", text: "goodbye", score: 30, tag: "archive")
        try await messages.insert([first, second, third])

        let found = try await messages.find("2")
        XCTAssertEqual(found, second)

        let range = try await messages
            .filter { $0.score >= 10 && $0.score <= 20 }
            .orderBy { [$0.score.asc] }
            .fetch()
        XCTAssertEqual(range, [first, second])

        let inSet = try await messages
            .filter { $0.id.in(["1", "3"]) }
            .orderBy { [$0.id.asc] }
            .fetch()
        XCTAssertEqual(inSet, [first, third])

        let emptyIn = try await messages.filter { $0.id.in([]) }.fetch()
        XCTAssertTrue(emptyIn.isEmpty)

        let nulls = try await messages.filter { $0.tag.isNull }.fetch()
        XCTAssertEqual(nulls, [second])
        let nonNulls = try await messages.filter { $0.tag.isNotNull }.count()
        XCTAssertEqual(nonNulls, 2)

        let negated = try await messages.filter { !($0.chatID == "a") }.fetch()
        XCTAssertEqual(negated, [third])

        let prefixed = try await messages.filter { $0.text.hasPrefix("hello_") }.fetch()
        XCTAssertEqual(prefixed, [first])
        let suffixed = try await messages.filter { $0.text.hasSuffix("%swift") }.fetch()
        XCTAssertEqual(suffixed, [second])

        let paged = try await messages.orderBy { [$0.score.asc] }.limit(1).offset(1).fetch()
        XCTAssertEqual(paged, [second])

        let updatedSecond = Message(id: "2", chatID: "a", text: "upserted", score: 25, tag: "vip")
        let fourth = Message(id: "4", chatID: "c", text: "new", score: 40, tag: nil)
        try await messages.upsert([updatedSecond, fourth])
        let fetchedSecond = try await messages.find("2")
        XCTAssertEqual(fetchedSecond, updatedSecond)
        let total = try await messages.count()
        XCTAssertEqual(total, 4)

        let deleted = try await messages.delete(id: "3")
        XCTAssertTrue(deleted)
        let deletedAgain = try await messages.delete(id: "3")
        XCTAssertFalse(deletedAgain)
        let remaining = try await messages.count()
        XCTAssertEqual(remaining, 3)
    }

    func testObservationDeliversUpdatedSnapshot() async throws {
        let database = try Database.inMemory(migrations: [
            Migration("create_messages", tables: [Message.self]),
        ])
        let messages = database.table(Message.self)
        var iterator = messages.filter { $0.chatID == "a" }.observe().makeAsyncIterator()
        let initial = try await iterator.next()
        XCTAssertEqual(initial, [])

        let inserted = Message(id: "1", chatID: "a", text: "observed", score: 1, tag: nil)
        try await messages.insert(inserted)
        let changed = try await iterator.next()
        XCTAssertEqual(changed, [inserted])
    }
}

import Foundation
import XCTest
import ORMKit

@Table("messages")
private struct Message: Sendable, Equatable {
    @PrimaryKey var id: String
    @Column("chat_id") var chatID: String
    var text: String
}

final class ORMKitTests: XCTestCase {
    func testCRUDAndTypedQuery() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let database = try ORMKit.Database(at: url, migrations: [
            Migration("create_messages") { db in
                try db.create(table: "messages") { table in
                    table.column("id", .text).primaryKey()
                    table.column("chat_id", .text).notNull()
                    table.column("text", .text).notNull()
                }
            },
        ])
        let messages = database.table(Message.self)
        let first = Message(id: "1", chatID: "a", text: "first")
        let second = Message(id: "2", chatID: "b", text: "second")
        try await messages.insert(first)
        try await messages.insert(second)

        let result = try await messages.where { $0.chatID == "a" }.order { $0.id.asc }.fetchAll()
        XCTAssertEqual(result, [first])
        let initialCount = try await messages.all().fetchAll().count
        XCTAssertEqual(initialCount, 2)

        try await messages.update(Message(id: "1", chatID: "a", text: "updated"))
        let updated = try await messages.where { $0.id == "1" }.fetchOne()
        XCTAssertEqual(updated?.text, "updated")
        let deleted = try await messages.delete(second)
        XCTAssertTrue(deleted)
        let count = try await messages.all().fetchAll().count
        XCTAssertEqual(count, 1)
    }

    func testObservationDeliversUpdatedSnapshot() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let database = try ORMKit.Database(at: url, migrations: [
            Migration("create_messages") { db in
                try db.create(table: "messages") { table in
                    table.column("id", .text).primaryKey()
                    table.column("chat_id", .text).notNull()
                    table.column("text", .text).notNull()
                }
            },
        ])
        let messages = database.table(Message.self)
        var iterator = messages.where { $0.chatID == "a" }.observe().makeAsyncIterator()
        let initial = try await iterator.next()
        XCTAssertEqual(initial, [])

        let inserted = Message(id: "1", chatID: "a", text: "observed")
        try await messages.insert(inserted)
        let changed = try await iterator.next()
        XCTAssertEqual(changed, [inserted])
    }
}

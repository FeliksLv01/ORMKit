import XCTest
import Foundation
import ORMKit

@Table("integration")
public struct IntegrationProbe: Sendable {
    @PrimaryKey public var id: Int64
    @Column("display_name") public var name: String
    public var note: String?
    public var rank: Int
}

public func IntegrationProbeCheck() async throws -> Bool {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let schema = try IntegrationProbe.tableSchema()
    guard schema.name == "integration", schema.columns.map(\.name) == ["id", "display_name", "note", "rank"] else { return false }
    let database = try ORMKit.Database(at: directory.appendingPathComponent("probe.sqlite"), migrations: [
        Migration("create_probe", tables: [IntegrationProbe.self]),
    ])
    let table = database.table(IntegrationProbe.self)
    try await table.insert {
        $0.id = 1
        $0.name = "initial"
        $0.note = "keep"
        $0.rank = 7
    }
    let updated = try await table.filter { $0.id == 1 }.update { $0.name = "updated" }
    let rows = try await table.filter { $0.rank == 7 }.orderBy { [$0.id.asc] }.fetch()
    guard updated == 1, rows.count == 1, rows.first?.name == "updated", rows.first?.note == "keep" else { return false }
    try await table.filter { $0.id == 1 }.update { $0.note = nil }
    let cleared = try await table.first()
    let deleted = try await table.filter { $0.id == 1 }.delete()
    let count = try await table.count()
    return cleared?.note == nil && deleted == 1 && count == 0
}

final class IntegrationTests: XCTestCase {
    @MainActor func testBinaryDatabaseAndMacro() async throws {
        let passed = try await IntegrationProbeCheck()
        XCTAssertTrue(passed)
    }
}

import ORMKitMacros
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import XCTest

final class TableMacroTests: XCTestCase {
    private func members(_ source: String) throws -> [DeclSyntax] {
        let file = Parser.parse(source: source)
        let declaration = try XCTUnwrap(file.statements.first?.item.as(StructDeclSyntax.self))
        let attribute = try XCTUnwrap(declaration.attributes.first?.as(AttributeSyntax.self))
        return try TableMacro.expansion(
            of: attribute,
            providingMembersOf: declaration,
            conformingTo: [],
            in: BasicMacroExpansionContext()
        )
    }

    func testPublicColumnMappingAndSchemaOptions() throws {
        let generated = try members("""
        @Table("books")
        public struct Book: Sendable {
            @PrimaryKey(autoIncrement: true) var id: Int64
            @Column("display_name", unique: true, defaultValue: .text("")) var title: String
        }
        """).map(\.trimmedDescription).joined(separator: "\n")
        XCTAssertTrue(generated.contains("public static let databaseTableName = \"books\""))
        XCTAssertTrue(generated.contains("public static let primaryKeyColumn = \"id\""))
        XCTAssertTrue(generated.contains("public let `title`: TableColumn<String> = TableColumn(\"display_name\")"))
        XCTAssertTrue(generated.contains("case `title` = \"display_name\""))
        XCTAssertTrue(generated.contains("primaryKey: true, autoIncrement: true"))
        XCTAssertTrue(generated.contains("unique: true, defaultValue: .text(\"\")"))
        XCTAssertTrue(generated.contains("public static func tableSchema() throws -> TableSchema"))
    }

    func testProjectionRejectsSchemaCreation() throws {
        let generated = try members("""
        @Table("books", schema: false)
        struct Projection {
            @PrimaryKey var id: Int64
        }
        """).map(\.trimmedDescription).joined(separator: "\n")
        XCTAssertTrue(generated.contains("throw SchemaError.noSchema(databaseTableName)"))
    }

    func testMissingPrimaryKeyIsRejected() {
        XCTAssertThrowsError(try members("""
        @Table("books")
        struct Book { var id: Int64 }
        """)) { error in
            XCTAssertEqual(String(describing: error), "@Table requires exactly one @PrimaryKey property.")
        }
    }

    func testDuplicateDatabaseColumnsAreRejected() {
        XCTAssertThrowsError(try members("""
        @Table("books")
        struct Book {
            @PrimaryKey var id: Int64
            @Column("id") var duplicate: String
        }
        """)) { error in
            XCTAssertEqual(String(describing: error), "@Table has duplicate database column names.")
        }
    }
}

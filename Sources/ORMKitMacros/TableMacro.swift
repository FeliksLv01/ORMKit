import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct TableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structure = declaration.as(StructDeclSyntax.self) else {
            throw TableMacroError.structOnly
        }
        let tableName = try stringArgument(of: node)
        let properties = try storedProperties(of: structure)
        guard !properties.isEmpty else { throw TableMacroError.noColumns }
        let primaryKeys = properties.filter(\.isPrimaryKey)
        guard primaryKeys.count == 1, let primaryKey = primaryKeys.first else {
            throw TableMacroError.onePrimaryKey
        }
        let access = structure.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        let columns = properties.map {
            "\(access)let \($0.propertyName): TableColumn<\($0.typeName)> = TableColumn(\(swiftLiteral($0.columnName)))"
        }.joined(separator: "\n    ")
        let codingKeys = properties.map {
            "case \($0.propertyName) = \(swiftLiteral($0.columnName))"
        }.joined(separator: "\n    ")
        return [
            DeclSyntax(stringLiteral: "\(access)static let databaseTableName = \(swiftLiteral(tableName))"),
            DeclSyntax(stringLiteral: "\(access)static let primaryKeyColumn = \(swiftLiteral(primaryKey.columnName))"),
            DeclSyntax(stringLiteral: "\(access)struct Columns: Sendable {\n    \(columns)\n}"),
            DeclSyntax(stringLiteral: "\(access)static let columns = Columns()"),
            DeclSyntax(stringLiteral: "enum CodingKeys: String, CodingKey {\n    \(codingKeys)\n}"),
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else { throw TableMacroError.structOnly }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): TableModel {}")]
    }
}

public struct PrimaryKeyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

public struct ColumnMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

private struct Property {
    let propertyName: String
    let typeName: String
    let columnName: String
    let isPrimaryKey: Bool
}

private func storedProperties(of structure: StructDeclSyntax) throws -> [Property] {
    var result: [Property] = []
    for member in structure.memberBlock.members {
        guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
        if variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }) {
            continue
        }
        if variable.bindings.allSatisfy({ $0.accessorBlock != nil }) { continue }
        guard variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let annotation = binding.typeAnnotation else {
            throw TableMacroError.explicitStoredProperty
        }
        let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
        let key = attributes.contains { $0.attributeName.trimmedDescription == "PrimaryKey" }
        let customName = try attributes.first { $0.attributeName.trimmedDescription == "Column" }.map { try stringArgument(of: $0) }
        result.append(Property(
            propertyName: identifier.identifier.text,
            typeName: annotation.type.trimmedDescription,
            columnName: customName ?? identifier.identifier.text,
            isPrimaryKey: key
        ))
    }
    if Set(result.map(\.columnName)).count != result.count { throw TableMacroError.duplicateColumn }
    return result
}

private func stringArgument(of node: AttributeSyntax) throws -> String {
    guard case .argumentList(let arguments) = node.arguments,
          arguments.count == 1,
          let expression = arguments.first?.expression.as(StringLiteralExprSyntax.self),
          expression.segments.count == 1,
          let segment = expression.segments.first?.as(StringSegmentSyntax.self),
          !segment.content.text.isEmpty else {
        throw TableMacroError.stringLiteral
    }
    return segment.content.text
}

private func swiftLiteral(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

private enum TableMacroError: Error, CustomStringConvertible {
    case structOnly
    case noColumns
    case onePrimaryKey
    case explicitStoredProperty
    case duplicateColumn
    case stringLiteral

    var description: String {
        switch self {
        case .structOnly: "@Table can only be applied to a struct."
        case .noColumns: "@Table requires at least one stored property."
        case .onePrimaryKey: "@Table requires exactly one @PrimaryKey property."
        case .explicitStoredProperty: "@Table properties need one stored binding and an explicit type."
        case .duplicateColumn: "@Table has duplicate database column names."
        case .stringLiteral: "@Table and @Column require a non-empty string literal."
        }
    }
}

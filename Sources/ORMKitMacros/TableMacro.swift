import Foundation
import SwiftParser
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
        if let schema = argument("schema", in: node), schema != "true", schema != "false" {
            throw TableMacroError.schemaLiteral
        }
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
        let schemaColumns = properties.map {
            "try SchemaColumn(\(swiftLiteral($0.columnName)), type: \($0.typeName).self, storage: \($0.storage), primaryKey: \($0.isPrimaryKey), autoIncrement: \($0.autoIncrement), unique: \($0.unique), defaultValue: \($0.defaultValue), references: \($0.references), check: \($0.check))"
        }.joined(separator: ",\n")
        let schemaBody: String
        if argument("schema", in: node) == "false" {
            schemaBody = "throw SchemaError.noSchema(databaseTableName)"
        } else {
            schemaBody = "return TableSchema(databaseTableName, columns: [\(schemaColumns)], indexes: schemaIndexes, checks: schemaChecks)"
        }
        return [
            DeclSyntax(stringLiteral: "\(access)static let databaseTableName = \(swiftLiteral(tableName))"),
            DeclSyntax(stringLiteral: "\(access)static let primaryKeyColumn = \(swiftLiteral(primaryKey.columnName))"),
            DeclSyntax(stringLiteral: "\(access)struct Columns: Sendable {\n    \(columns)\n}"),
            DeclSyntax(stringLiteral: "\(access)static let columns = Columns()"),
            DeclSyntax(stringLiteral: "enum CodingKeys: String, CodingKey {\n    \(codingKeys)\n}"),
            DeclSyntax(stringLiteral: "\(access)static func tableSchema() throws -> TableSchema { \(schemaBody) }"),
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
    let autoIncrement: String
    let storage: String
    let unique: String
    let defaultValue: String
    let references: String
    let check: String
}

private func storedProperties(of structure: StructDeclSyntax) throws -> [Property] {
    var result: [Property] = []
    for member in structure.memberBlock.members {
        guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
        if variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }) {
            continue
        }
        if variable.bindings.allSatisfy({ !isStored($0) }) { continue }
        guard variable.bindings.count == 1,
              let binding = variable.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let annotation = binding.typeAnnotation else {
            throw TableMacroError.explicitStoredProperty
        }
        let attributes = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }
        let keyAttribute = attributes.first { $0.attributeName.trimmedDescription.split(separator: ".").last == "PrimaryKey" }
        let columnAttribute = attributes.first { $0.attributeName.trimmedDescription.split(separator: ".").last == "Column" }
        let customName: String?
        if let columnAttribute, case .argumentList(let arguments) = columnAttribute.arguments,
           arguments.first?.label == nil, !arguments.isEmpty {
            customName = arguments.first?.expression.is(NilLiteralExprSyntax.self) == true
                ? nil : try stringArgument(of: columnAttribute)
        } else { customName = nil }
        let name = identifier.identifier.text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        result.append(Property(
            propertyName: "`\(name)`",
            typeName: annotation.type.trimmedDescription,
            columnName: customName ?? name,
            isPrimaryKey: keyAttribute != nil,
            autoIncrement: keyAttribute.flatMap { argument("autoIncrement", in: $0) } ?? "false",
            storage: columnAttribute.flatMap { argument("storage", in: $0) } ?? "nil",
            unique: columnAttribute.flatMap { argument("unique", in: $0) } ?? "false",
            defaultValue: columnAttribute.flatMap { argument("defaultValue", in: $0) } ?? "nil",
            references: columnAttribute.flatMap { argument("references", in: $0) } ?? "nil",
            check: columnAttribute.flatMap { argument("check", in: $0) } ?? "nil"
        ))
    }
    if Set(result.map(\.columnName)).count != result.count { throw TableMacroError.duplicateColumn }
    return result
}

private func isStored(_ binding: PatternBindingSyntax) -> Bool {
    guard let block = binding.accessorBlock else { return true }
    switch block.accessors {
    case .getter: return false
    case .accessors(let accessors):
        return accessors.allSatisfy { ["didSet", "willSet"].contains($0.accessorSpecifier.text) }
    }
}

private func stringArgument(of node: AttributeSyntax) throws -> String {
    guard case .argumentList(let arguments) = node.arguments,
          arguments.first?.label == nil,
          let expression = arguments.first?.expression.as(StringLiteralExprSyntax.self),
          let value = expression.representedLiteralValue,
          !value.isEmpty else {
        throw TableMacroError.stringLiteral
    }
    return value
}

private func argument(_ label: String, in node: AttributeSyntax) -> String? {
    guard case .argumentList(let arguments) = node.arguments else { return nil }
    return arguments.first { $0.label?.text == label }?.expression.trimmedDescription
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
    case schemaLiteral

    var description: String {
        switch self {
        case .structOnly: "@Table can only be applied to a struct."
        case .noColumns: "@Table requires at least one stored property."
        case .onePrimaryKey: "@Table requires exactly one @PrimaryKey property."
        case .explicitStoredProperty: "@Table properties need one stored binding and an explicit type."
        case .duplicateColumn: "@Table has duplicate database column names."
        case .stringLiteral: "@Table and @Column require a non-empty string literal."
        case .schemaLiteral: "@Table(schema:) requires a literal true or false."
        }
    }
}

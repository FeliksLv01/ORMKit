import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ORMKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        TableMacro.self,
        PrimaryKeyMacro.self,
        ColumnMacro.self,
    ]
}

import GRDB

/// A write-only, typed field patch. Unassigned fields are omitted; assigning nil writes SQL NULL.
@dynamicMemberLookup
public struct TableChanges<Record: TableModel>: Sendable {
    private var values: [String: DatabaseValue] = [:]

    init() {}

    public subscript<Value: DatabaseValueConvertible & Sendable>(
        dynamicMember keyPath: KeyPath<Record.Columns, TableColumn<Value>>
    ) -> Value {
        @available(*, unavailable, message: "Changes are write-only. Fetch a record to read existing values.")
        get { fatalError("Changes are write-only") }
        set { values[Record.columns[keyPath: keyPath].name] = newValue.databaseValue }
    }

    var assignments: [TableAssignment] {
        values.keys.sorted().map { TableAssignment(column: $0, value: values[$0]!) }
    }
}

import ORMKit

// Must fail: updates have no snapshot from which an existing field could be read.
func invalidRead<R: TableModel>(_ patch: TableChanges<R>, field: KeyPath<R.Columns, TableColumn<String>>) -> String {
    patch[dynamicMember: field]
}

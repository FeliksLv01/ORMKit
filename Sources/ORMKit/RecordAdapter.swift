internal import GRDB

struct RecordAdapter<Model: TableModel>: Codable, FetchableRecord, PersistableRecord, TableRecord {
    var model: Model
    static var databaseTableName: String { Model.databaseTableName }

    init(model: Model) { self.model = model }
    init(from decoder: any Decoder) throws { model = try Model(from: decoder) }
    func encode(to encoder: any Encoder) throws { try model.encode(to: encoder) }
}

extension TableModel {
    public func insert(_ connection: SQLConnection) throws { try RecordAdapter(model: self).insert(connection.database) }
    public func update(_ connection: SQLConnection) throws { try RecordAdapter(model: self).update(connection.database) }
    @discardableResult public func delete(_ connection: SQLConnection) throws -> Bool { try RecordAdapter(model: self).delete(connection.database) }
    public static func fetchOne(_ connection: SQLConnection) throws -> Self? {
        try RecordAdapter<Self>.fetchOne(connection.database)?.model
    }
    public static func fetchOne<Value: SQLValueConvertible>(_ connection: SQLConnection, key: Value) throws -> Self? {
        try RecordAdapter<Self>.filter(key: key.sqlValue.databaseValue).fetchOne(connection.database)?.model
    }
    public static func fetchCount(_ connection: SQLConnection) throws -> Int { try RecordAdapter<Self>.fetchCount(connection.database) }
}

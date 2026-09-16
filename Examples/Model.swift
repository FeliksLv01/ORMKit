import ORMKit

@Table("messages")
public struct Message: Sendable {
    @PrimaryKey public var id: String
    @Column("chat_id") public var chatID: String
    public var text: String

    public init(id: String, chatID: String, text: String) {
        self.id = id
        self.chatID = chatID
        self.text = text
    }
}

public func exampleQuery(_ database: ORMKit.Database) async throws -> [Message] {
    try await database.table(Message.self)
        .where { $0.chatID == "general" }
        .order { $0.id.desc }
        .fetchAll()
}

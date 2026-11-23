# ORMKit

ORMKit 是一个轻量、无 UI 依赖的 Swift 6 SQLite ORM，用于替代受系统版本限制的 SwiftData。通过 Swift 宏生成编译期类型安全的列与表结构，底层使用 `GRDB.swift`（通过 `internal import` 完全隔离，不向业务泄露任何 GRDB 类型），支持默认 WAL 模式与显式版本迁移。

- **纯 SwiftPM 分发**：不支持 CocoaPods，无需维护预编译二进制，业务代码只需 `import ORMKit`。
- **默认开启 WAL**：文件数据库默认使用 SQLite WAL 模式（多读单写、快照隔离）；单元测试可直接使用 `Database.inMemory()`，共用同一套 API。
- **平台支持**：iOS 15+、macOS 12+、tvOS 15+、watchOS 9+。

[English README](README.md)

## 安装

在 `Package.swift` 或 Xcode 中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/FeliksLv01/ORMKit.git", from: "0.0.1")
]
```

然后在目标中引入 `ORMKit` 即可。

## 快速开始

```swift
import ORMKit

@Table("messages")
struct Message: Sendable {
    @PrimaryKey var id: String
    @Column("chat_id") var chatID: String
    @Column(defaultValue: .text("")) var text: String
    var tag: String?
}

let database = try Database(
    at: databaseURL,
    migrations: [
        try Migration("v1_create_messages", tables: [Message.self])
    ]
)

let messages = database.table(Message.self)

// 插入与 Upsert（支持单条或批量原子写入）
try await messages.insert(Message(id: "1", chatID: "general", text: "Hello", tag: nil))
try await messages.upsert(Message(id: "1", chatID: "general", text: "Hello WAL", tag: "pinned"))

// 按主键查找与类型安全查询
let found = try await messages.find("1")
let rows = try await messages
    .filter { $0.chatID == "general" && $0.tag.isNotNull }
    .orderBy { [$0.id.desc] }
    .limit(50)
    .offset(0)
    .fetch()

// 只写字段补丁（未赋值字段保持不变；赋值 nil 显式写入 SQL NULL）
try await messages.filter { $0.id == "1" }.update {
    $0.text = "Updated"
    $0.tag = nil
}

// 异步响应式监听（AsyncSequence，不绑定 SwiftUI / UIKit）
for try await snapshot in messages.filter({ $0.chatID == "general" }).observe() {
    // 在任意 Actor 上消费最新快照
}
```

## 核心特性

- **WAL 与灵活配置**：`Database(at:configuration:migrations:)` 默认开启 `JournalMode.wal`、外键约束和 5 秒 `busyTimeout`；内存库使用 `Database.inMemory(migrations:)`。
- **声明式建表**：支持 `@Table`、`@PrimaryKey(autoIncrement:)`、`@Column`（列名、唯一约束、默认值、外键级联、CHECK 约束）以及索引 `schemaIndexes`。
- **完整查询谓词**：支持 `==`、`!=`、`<`、`<=`、`>`、`>=`、`&&`、`||`、`!`、`.in([...])`、`.isNull`、`.isNotNull`、字符串安全转义匹配 `.contains()` / `.hasPrefix()` / `.hasSuffix()`，以及复合索引游标分页 `before` / `after`。
- **事务与快照**：`database.transaction { tx in ... }` 与 `database.snapshot { tx in ... }` 提供与外层一致的类型安全语法。
- **显式迁移**：支持 `Migration("v1", tables: [...])` 以及基于参数绑定 `SQLConnection` 的自定义升级脚本。

## 运行测试

```sh
swift test
python3 Scripts/test.py negative
python3 Scripts/test.py ios
```

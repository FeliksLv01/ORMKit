# ORMKit

ORMKit is a UI-independent SQLite ORM for Swift 6. It uses macros for model mapping, GRDB for SQLite access, and explicit migrations. It does not require a DAO type or a SwiftUI context.

```swift
import ORMKit

@Table("messages")
struct Message: Sendable {
    @PrimaryKey var id: String
    @Column("chat_id") var chatID: String
    var text: String
}

let database = try ORMKit.Database(at: databaseURL, migrations: [
    Migration("create_messages") { db in
        try db.create(table: "messages") { table in
            table.column("id", .text).primaryKey()
            table.column("chat_id", .text).notNull()
            table.column("text", .text).notNull()
        }
    }
])

let messages = database.table(Message.self)
try await messages.insert(Message(id: "1", chatID: "general", text: "Hello"))
let rows = try await messages.where { $0.chatID == "general" }.order { $0.id.desc }.fetchAll()

for try await snapshot in messages.where({ $0.chatID == "general" }).observe() {
    // Update UIKit, SwiftUI, or any other consumer on its chosen executor.
}
```

`@Table` generates a table name, typed columns, coding keys, and `TableModel` conformance. Every model needs exactly one `@PrimaryKey`. Only stored properties with explicit types are supported in this first version. Custom column names use `@Column("sqlite_name")`.

## Swift Package Manager

Add this repository as a package dependency, then depend on the `ORMKit` product. The package uses Swift 6.1 or newer and supports iOS 15+, macOS 12+, tvOS 15+, and watchOS 8+.

## CocoaPods

The podspec needs a prebuilt macOS host macro executable. A release maintainer should run `sh build-macro.sh` using the Swift toolchain used for the pod release and include `Prebuilt/ORMKitMacros` in the release. The prebuilt compiler plugin may need rebuilding for a newer Swift toolchain or another macOS host architecture.

The compiler plugin includes SwiftSyntax; its license is included in [ThirdPartyNotices](ThirdPartyNotices/swift-syntax-LICENSE.txt).

GRDB 7 is not currently available in the CocoaPods public specs index, so declare its Git source explicitly in the Podfile:

```ruby
target 'YourApp' do
  pod 'GRDB.swift', :git => 'https://github.com/groue/GRDB.swift.git', :tag => 'v7.11.1'
  pod 'ORMKit', :git => 'https://github.com/FeliksLv01/ORMKit.git', :tag => '0.0.2'
end
```

The [local CocoaPods example](Examples/CocoaPods/Podfile) uses `:path => '../..'` to validate installation without a published repository. With current Xcode versions, it also raises the GRDB target's deployment setting to iOS 15 because GRDB's own podspec declares iOS 13.

## Design notes

### Bounded queries and atomic changes (0.0.2)

`limit(50)` emits SQL `LIMIT 50`: it never fetches the entire table and filters in memory.
For pagination, request 51 rows, display 50, and use the last displayed row as the next cursor.
Order by a unique tie-breaker as well as the activity timestamp:

```swift
let page = try await database.table(Conversation.self)
    .where { before($0.updatedAt, $0.sequence, cursor.updatedAt, cursor.sequence) }
    .order { $0.updatedAt.desc.then($0.sequence.desc) }
    .limit(51)
    .fetchAll()
```

Create an index matching the filter prefix and sort columns in an explicit migration.
Cursor comparison above is a SQL row-value comparison, allowing SQLite to seek into a composite index.
Zero/negative limits return no rows, including with `fetchOne()`.

Use `transaction` for atomic typed operations and `snapshot` for consistent reads. The closure is
non-suspending. Scoped tables must not escape it; they are intentionally not `Sendable`.

```swift
try await database.transaction { tx in
    let messages = tx.table(Message.self)
    try messages.insert { [$0.id.set(to: "3"), $0.chatID.set(to: "general"), $0.text.set(to: "Draft")] }
    try messages.where { $0.id == "3" }.update { [$0.text.set(to: "Ready")] }
    let exists = try messages.where { $0.id == "3" }.exists()
}
```

- Partial inserts preserve database defaults and auto-increment keys.
- `update` writes only selected fields; `delete` returns the affected row count.
- Mutations with `limit` are rejected rather than silently affecting more rows.
- Empty/duplicate assignment lists are rejected; values are bound as parameters.
- `contains("text")` on string columns performs literal substring matching; `%` and `_` are escaped.
- Scoped `contains(column, value:)` builds a SQL `IN (SELECT ...)` subquery without loading an ID array.
- WAL is enabled by GRDB's writable `DatabasePool`; writes are serialized, readers use snapshot isolation.
- `read`/`write` remain escape hatches for explicit schema migrations and specialized SQL.

- SQLite access and observations are asynchronous. The library has no UIKit, SwiftUI, or `@MainActor` dependency.
- Query columns are compile-time typed; migrations deliberately remain explicit SQL/GRDB schema operations.
- `Database.read` and `Database.write` expose GRDB's database handle for complex queries and transactional operations.
- Existing migration identifiers and contents should stay stable after release.

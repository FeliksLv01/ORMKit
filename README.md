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
    Migration("create_messages", tables: [Message.self])
])

let messages = database.table(Message.self)
try await messages.insert(Message(id: "1", chatID: "general", text: "Hello"))
let rows = try await messages.filter { $0.chatID == "general" }.orderBy { [$0.id.desc] }.limit(50).fetch()

for try await snapshot in messages.filter({ $0.chatID == "general" }).observe() {
    // Update UIKit, SwiftUI, or any other consumer on its chosen executor.
}
```

`@Table` generates a table name, typed columns, coding keys, a table schema, and `TableModel` conformance. Every model needs exactly one `@PrimaryKey`. Stored properties need explicit types. Custom column names use `@Column("sqlite_name")`.

## Creating tables

`Migration("v1", tables: [Message.self])` creates model tables and indexes once, inside a transaction. In a migration with other operations, use `try db.createTable(Message.self)`. Merely calling `database.table(Message.self)` does not change the schema.

```swift
@Table("notes")
struct Note: Sendable {
    @PrimaryKey(autoIncrement: true) var id: Int64
    @Column(unique: true) var externalID: String
    @Column(defaultValue: .text("")) var text: String
    @Column(defaultValue: .integer(0), check: "revision >= 0") var revision: Int
    @Column(references: .init("folders", column: "id", onDelete: .cascade)) var folderID: String
    var archivedAt: Double?

    static var schemaIndexes: [TableIndex] {
        [TableIndex("notes_folder", columns: [columns.folderID.name], conditionSQL: "archivedAt IS NULL")]
    }
}
```

Non-optional fields generate `NOT NULL`; optional fields allow `NULL`. Integer types and `Bool` map to INTEGER, `Float`/`Double` to REAL, `String`/`Date` to TEXT, and `Data`/`UUID` to BLOB. Raw-representable enums use their raw value's storage. These defaults match the internal record adapter encoding. Set `@Column(storage: .text)` (or another storage type) for custom codecs or overridden encoding strategies. Unsupported types fail with `SchemaError` rather than guessing. Swift property initializers are not SQLite defaults: declare database defaults with `@Column(defaultValue:)`.

`schemaChecks: [String]` adds cross-column checks. Checks, partial-index conditions, and `.sql` defaults are trusted SQL authored by the developer, never user input. Register referenced tables before their dependents. Only one non-optional primary key is supported; AUTOINCREMENT requires `Int` or `Int64`. Table, column, and index names must be nonempty and contain no double quote or NUL.

Use `@Table("notes", schema: false)` for partial-row projections that share a table with a full model. Creating a table from such a projection throws.

Existing databases still need explicit versioned migrations. Do not change the model used by a historical creation migration and then replay old ALTER statements against that new model: keep frozen per-version schema models, or create the latest model schema only for fresh databases and run the historical upgrade path only for existing databases (as in Nook's ChatSchema). Changing a Swift model alone never alters an existing table.

## Swift Package Manager

Add this repository as a package dependency, then depend on the `ORMKit` product. The package manifest uses Swift tools 6.1; CI validates Xcode 27 / Swift 6.4. It supports iOS 15+, macOS 12+, tvOS 15+, and watchOS 9+.

Macros build from source. GRDB 7.11.1 is a checksum-pinned XCFramework downloaded from an immutable artifact Release in this repository. Applications add only the `ORMKit` product; ordinary model and CRUD code imports only `ORMKit`.

## Design notes

### Simplified API

The APIs below are included in `0.0.3`. The earlier `0.0.2` tag was withdrawn.

```swift
let messages = database.table(Message.self)
let rows = try await messages
    .filter { $0.chatID == "general" }
    .orderBy { [$0.id.desc] }
    .limit(50)
    .fetch()

try await messages.filter { $0.id == "3" }.update {
    $0.text = "Ready"
}
```

The recommended query vocabulary is `filter`, `orderBy`, `limit`, `fetch`, `first`, `count`, and
`exists`. Existing `where`/`order`/`fetchAll`/`fetchOne` methods remain compatibility entry points.
`orderBy` replaces the order with the supplied array; repeated `filter` calls combine with AND.

Update closures receive a write-only typed patch, **not a fetched record**:

- Unassigned fields are not written; `$0.optionalField = nil` explicitly writes SQL NULL.
- Repeated assignment to a field uses its last value.
- Reading patch fields (including `+=`) is a compile-time error. Read the record inside a transaction
  when an update depends on the existing value.
- Empty patches are rejected. Mutations on a limited query are rejected rather than silently
  dropping the limit.
- Partial insert uses the same assignment syntax, preserving defaults for omitted fields.
- Patch fields must conform to `SQLValueConvertible`; raw-value enums can adopt that protocol.
- Updates return the number of affected rows. An unmatched filter returns zero, not an error.

`limit(50)` emits SQL `LIMIT 50`: it never fetches the entire table and filters in memory.
For pagination, request 51 rows, display 50, and use the last displayed row as the next cursor.
Order by a unique tie-breaker as well as the activity timestamp:

```swift
let page = try await database.table(Conversation.self)
    .filter { before($0.updatedAt, $0.sequence, cursor.updatedAt, cursor.sequence) }
    .orderBy { [$0.updatedAt.desc, $0.sequence.desc] }
    .limit(51)
    .fetch()
```

Create an index matching the filter prefix and sort columns in an explicit migration.
Cursor comparison above is a SQL row-value comparison, allowing SQLite to seek into a composite index.
Zero/negative limits return no rows, including with `first()`.

Use `transaction` for atomic typed operations and `snapshot` for consistent reads. The closure is
non-suspending. Scoped tables must not escape it; they are intentionally not `Sendable`.

```swift
try await database.transaction { tx in
    let messages = tx.table(Message.self)
    try messages.insert {
        $0.id = "3"
        $0.chatID = "general"
        $0.text = "Draft"
    }
    try messages.filter { $0.id == "3" }.update { $0.text = "Ready" }
    let exists = try messages.filter { $0.id == "3" }.exists()
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
- Query columns are compile-time typed; table creation uses generated schema metadata, and upgrades remain explicit versioned migrations.
- `Database.read` and `Database.write` expose ORMKit's scoped `SQLConnection` for complex queries and transactional operations.
- Existing migration identifiers and contents should stay stable after release.


## Tests and releases

This is a standard SwiftPM package: `Package.swift`, `Sources/` and `Tests/`. SwiftPM is the only supported integration, and macros compile from source. Historical versions remain unchanged.

Automation uses Python 3.11+ standard library, Xcode and xcbeautify; no Ruby or Python packages are required.

```sh
python3 Scripts/test.py macros
python3 Scripts/test.py ios
```

GitHub Actions runs host macro tests and iOS package tests on pull requests, main updates and version tags. Runtime tests include real macro expansion and automatic registration/database assertions. `xcodebuild` uses pipefail and xcbeautify; logs and xcresults are uploaded even on failure. New numeric version tags create a GitHub Release only after all CI jobs pass. Local release orchestration, CocoaPods and precompiled macro distribution have been removed.

## GRDB artifact

`python3 Scripts/build_grdb.py` builds the pinned upstream XCFramework. The manual **Build GRDB artifact** workflow builds and tests it on macOS and iOS before optional publication. Download and commit the generated `GRDBArtifact.lock.json` after publication. Normal CI and ORMKit versions reuse that checksum-pinned asset. Public APIs expose ORMKit's `SQLConnection`, `SQLValue`, `SQLRow` and `SQLValueConvertible`; application code does not depend on GRDB types.

## Migration from 0.0.3

Import and link only ORMKit. Model conformances no longer inherit GRDB protocols. Custom query/patch values adopt `SQLValueConvertible`; raw-value enums get default conversion implementations. Migration and raw SQL closures receive `SQLConnection`; use `createTable(Model.self)` or bound `execute(sql:arguments:)`. Replace raw `Row` reads with `SQLRow`. watchOS now requires version 9 because the build toolchain no longer accepts watchOS 8 frameworks.

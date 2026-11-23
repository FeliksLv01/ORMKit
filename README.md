# ORMKit

ORMKit is a lightweight, UI-independent SQLite ORM for Swift 6, designed as a clean alternative to SwiftData without iOS 17+ OS restrictions. It uses Swift macros for compile-time typed columns, `GRDB.swift` (encapsulated internally) for rock-solid SQLite and WAL support, and explicit versioned migrations.

- **Pure SwiftPM**: no CocoaPods, no precompiled binaries, no GRDB type leakage (`import ORMKit` only).
- **WAL by default**: file-backed databases open in SQLite WAL mode with concurrent snapshot reads and serialized writes; `Database.inMemory()` uses the exact same API for tests.
- **Platforms**: iOS 15+, macOS 12+, tvOS 15+, watchOS 9+.

[中文文档](README.zh-CN.md)

## Installation

Add `ORMKit` in `Package.swift` or Xcode Swift Package Dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/FeliksLv01/ORMKit.git", from: "0.0.1")
]
```

Then add `ORMKit` to your target dependencies.

## Quick Start

```swift
import ORMKit

@Table("messages")
struct Message: Sendable {
    @PrimaryKey var id: String
    @Column("chat_id") var chatID: String
    @Column(defaultValue: .text("")) var text: String
    var tag: String?
}

let database = try ORMKit.Database(
    at: databaseURL,
    migrations: [
        try Migration("v1_create_messages", tables: [Message.self])
    ]
)

let messages = database.table(Message.self)

// Insert & Upsert (single or batch)
try await messages.insert(Message(id: "1", chatID: "general", text: "Hello", tag: nil))
try await messages.upsert(Message(id: "1", chatID: "general", text: "Hello WAL", tag: "pinned"))

// Typed queries
let found = try await messages.find("1")
let rows = try await messages
    .filter { $0.chatID == "general" && $0.tag.isNotNull }
    .orderBy { [$0.id.desc] }
    .limit(50)
    .offset(0)
    .fetch()

// Write-only typed patches (omitted fields stay untouched; nil writes SQL NULL)
try await messages.filter { $0.id == "1" }.update {
    $0.text = "Updated"
    $0.tag = nil
}

// Reactive observation (AsyncSequence, UI-independent)
for try await snapshot in messages.filter({ $0.chatID == "general" }).observe() {
    // Update SwiftUI, UIKit, or any consumer on your chosen actor
}
```

## Features

- **WAL & Configuration**: `Database(at:configuration:migrations:)` defaults to `JournalMode.wal`, foreign keys enabled, and a 5s busy timeout. Use `Database.inMemory(migrations:)` in unit tests.
- **Typed Schema Generation**: `@Table`, `@PrimaryKey(autoIncrement:)`, `@Column(_:storage:unique:defaultValue:references:check:)`, `schemaIndexes`, and `schemaChecks`.
- **Rich Predicates**: `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, `!`, `.in([...])`, `.isNull`, `.isNotNull`, string `.contains()`, `.hasPrefix()`, `.hasSuffix()` (all safely escaped and parameter-bound), plus composite index cursors `before(_:_:_:_:)` and `after(_:_:_:_:)`.
- **Atomic Transactions & Snapshots**: `database.transaction { tx in ... }` and `database.snapshot { tx in ... }` share the same typed query and mutation syntax.
- **Explicit Migrations**: `Migration("v1", tables: [...])` or custom SQL via `SQLConnection`. Changing a Swift struct never silently alters an existing table.

## Testing

```sh
swift test
python3 Scripts/test.py negative
python3 Scripts/test.py ios
```

# ORMKit conventions

- Reply in Chinese; use English Conventional Commits and verify personal Git identity. New Swift files have no header comments.
- Use standard SwiftPM Sources/Tests structure. SwiftPM is the only distribution; no CocoaPods or precompiled binaries. All scripts belong in Scripts/.
- Keep ORMKit UI-independent. Applications link and import only ORMKit. Public APIs and model conformances must not expose GRDB types; use `internal import GRDB` and internal record adapters.
- File-backed databases use WAL mode by default (`DatabaseConfiguration.journalMode = .wal`); in-memory databases share the same `ORMKit.Database` API via `Database.inMemory(...)`.
- Preserve explicit versioned migrations, bound SQL parameters, typed queries, observations, and omitted-versus-NULL patches. Do not change historical migrations or implicitly alter tables.
- Use the canonical `https://github.com/swiftlang/swift-syntax.git` and `https://github.com/groue/GRDB.swift.git` URLs in `Package.swift`.

## Tests and CI

- GitHub Actions is the verification and release gate. Preserve macro tests, runtime tests, and `Tests/CompileFailures/ReadChanges.swift` negative compile-time test.
- `swift test` runs macro and runtime tests on macOS; `python3 Scripts/test.py ios` runs iOS Simulator tests; `python3 Scripts/test.py negative` verifies the write-only patch diagnostic.
- All automation scripts use Python 3.11+ standard library. Never commit generated projects, caches, or build output.
- Finish changes with `git diff --check` and keep English/Chinese docs synchronized.

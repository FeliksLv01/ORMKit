# ORMKit conventions

- Reply in Chinese; use English Conventional Commits and verify personal Git identity. New Swift files have no header comments.
- Use standard SwiftPM Sources/Tests structure. SwiftPM is the only distribution; no CocoaPods or precompiled macros. All scripts belong in Scripts/.
- Keep ORMKit UI-independent. Applications link/import only ORMKit. Public APIs and model conformances must not expose GRDB types; use internal imports and internal record adapters.
- Preserve explicit versioned migrations, bound SQL parameters, typed queries, observations and omitted-versus-NULL patches. Do not change historical migrations or implicitly alter tables.
- GRDBDistribution.json pins upstream revision/platforms; GRDBArtifact.lock.json pins the immutable Release ZIP checksum. Build official Release XCFrameworks with stable Swift interfaces, upstream SQLite flags, privacy manifests and MIT license. Never commit binary artifacts or add source GRDB beside the binary.
- Runtime/tests/docs changes reuse GRDB. Upstream/toolchain/build changes require a new immutable artifact; never overwrite published assets or historical tags.

## Tests and CI

- GitHub Actions is the verification and release gate. Preserve macro tests, all runtime tests and actual macro expansion/registration assertions. Host macro tests are separate because iOS cannot execute compiler-plugin host test bundles.
- python3 Scripts/test.py macros runs host macro tests; python3 Scripts/test.py ios runs the standard package runtime tests. No temporary consumer-project generator or local release orchestrator. All automation uses Python 3.11+ standard library; do not add Ruby or shell wrappers.
- Every xcodebuild uses pipefail, tee logs and xcbeautify; check Simulator availability. CI uploads logs and xcresults on success or failure. Stale results never validate new sources.
- Numeric version tags create a library Release only after all CI jobs pass. Never add skip-test options or overwrite existing tags/Releases. Preserve historical versions.
- Use rtk for shell tools, finish with git diff --check, and keep English/Chinese docs synchronized. Never commit generated projects, caches or build output. Do not patch dependency checkouts/generated fixtures to hide failures.

- Preserve Tests/CompileFailures/ReadChanges.swift and its expected write-only diagnostic in CI; unrelated compilation failures must not pass the negative test.
- GRDB workflow builds/tests the local candidate before publication, uploads the lock and ZIP, and only publishes when explicitly dispatched with publish enabled. Commit the resulting lock before releasing an ORMKit version. Reuse its immutable artifact in normal package CI; do not rebuild GRDB for every library commit.

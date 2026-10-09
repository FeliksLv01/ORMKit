#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/ormkit-write-only.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Sources" .build/ci
cp Tests/CompileFailures/ReadChanges.swift "$work/Sources/main.swift"
python3 - "$PWD" "$work" <<'PYTHON'
from pathlib import Path
import json,sys
root,work=map(Path,sys.argv[1:])
(work/'Package.swift').write_text('// swift-tools-version: 6.1\nimport PackageDescription\nlet package = Package(name: "WriteOnly", platforms: [.macOS(.v12)], dependencies: [.package(path: '+json.dumps(str(root))+')], targets: [.executableTarget(name: "WriteOnly", dependencies: [.product(name: "ORMKit", package: '+json.dumps(root.name)+')], path: "Sources")])\n')
PYTHON
if swift build --package-path "$work" --scratch-path "$PWD/.build/ci/WriteOnly" > .build/ci/write-only.log 2>&1; then
    echo 'Write-only patch unexpectedly compiled'; exit 1
fi
grep -Fq 'Changes are write-only. Fetch a record to read existing values.' .build/ci/write-only.log || {
    cat .build/ci/write-only.log; echo 'Expected diagnostic missing'; exit 1;
}

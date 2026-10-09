#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/ormkit-binary-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT
python3 - "$PWD" "$work" <<'PYTHON'
from pathlib import Path
import json,shutil,sys
root,work=map(Path,sys.argv[1:])
lock=json.loads((root/'GRDBArtifact.lock.json').read_text())
artifact=root/'.distribution/grdb'/lock['input_fingerprint']/'GRDB.xcframework'
for name in ['Sources','Tests','Scripts']: shutil.copytree(root/name,work/name)
for name in ['GRDBArtifact.lock.json','Package.resolved']: shutil.copy(root/name,work/name)
shutil.copytree(artifact,work/'GRDB.xcframework')
manifest=(root/'Package.swift').read_text().replace('.binaryTarget(name: "GRDB", url: grdbURL, checksum: grdbChecksum)', '.binaryTarget(name: "GRDB", path: "GRDB.xcframework")')
(work/'Package.swift').write_text(manifest)
PYTHON
mkdir -p .build/ci
swift test --package-path "$work" --scratch-path "$PWD/.build/ci/LocalGRDB" 2>&1 | tee .build/ci/local-grdb-tests.log
bash "$work/Scripts/check-write-only.sh"
bash "$work/Scripts/test-ios.sh"
cp "$work"/.build/ci/*.log .build/ci/
find "$work/.build/ci" -maxdepth 1 -name '*.xcresult' -exec cp -R {} .build/ci/ \;

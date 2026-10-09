#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ci
host=$(mktemp -d "${TMPDIR:-/tmp}/macro-tests.XXXXXX")
trap 'rm -rf "$host"' EXIT
python3 - "$PWD" "$host" <<'PYTHON'
from pathlib import Path
import json,re,shutil,sys
root,host=map(Path,sys.argv[1:])
manifest=(root/'Package.swift').read_text()
library=re.search(r'let package = Package\(\s*name: "([^"]+)"',manifest).group(1)
module=library+'Macros'; tests=module+'Tests'
shutil.copytree(root/'Sources'/module,host/'Macros')
shutil.copytree(root/'Tests'/tests,host/'Tests')
syntax=next(p for p in json.loads((root/'Package.resolved').read_text())['pins'] if p['identity']=='swift-syntax')
products=['SwiftSyntax','SwiftSyntaxMacros','SwiftCompilerPlugin','SwiftSyntaxBuilder','SwiftParser']
deps=', '.join('.product(name: '+json.dumps(p)+', package: "swift-syntax")' for p in products)
(host/'Package.swift').write_text('// swift-tools-version: 6.1\nimport PackageDescription\nimport CompilerPluginSupport\nlet package = Package(name: "MacroTests", dependencies: [.package(url: '+json.dumps(syntax['location'])+', revision: '+json.dumps(syntax['state']['revision'])+')], targets: [.macro(name: '+json.dumps(module)+', dependencies: ['+deps+'], path: "Macros"), .testTarget(name: '+json.dumps(tests)+', dependencies: ['+json.dumps(module)+', .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")], path: "Tests")])\n')
PYTHON
swift test --package-path "$host" --scratch-path "$PWD/.build/ci/MacroTests" 2>&1 | tee .build/ci/macro-tests.log

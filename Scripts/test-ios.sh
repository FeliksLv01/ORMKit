#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
library=$(swift package dump-package | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
mkdir -p .build/ci
xcodebuild -version | tee .build/ci/environment.log
swift --version | tee -a .build/ci/environment.log
simulator=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; candidates=[d for runtime,items in devices.items() if "iOS" in runtime for d in items]; print(next((d["udid"] for d in candidates if d["state"]=="Booted"), candidates[0]["udid"] if candidates else ""))')
[[ -n "$simulator" ]] || { echo "No available iOS Simulator"; exit 1; }
xcrun simctl boot "$simulator" 2>/dev/null || true
xcrun simctl bootstatus "$simulator" -b
result=".build/ci/Tests-$(date +%s).xcresult"
flags='$(inherited)'
if [[ "$library" == DebugMenuKit || "$library" == LaunchTaskKit ]]; then
    flags+=' -enable-experimental-feature SymbolLinkageMarkers'
fi
xcodebuild test -scheme "$library" -destination "platform=iOS Simulator,id=$simulator"     -derivedDataPath .build/ci/DerivedData -only-testing:"${library}Tests"     -skipMacroValidation -parallel-testing-enabled NO -resultBundlePath "$result"     CODE_SIGNING_ALLOWED=NO "OTHER_SWIFT_FLAGS=$flags" 2>&1 | tee .build/ci/ios-tests.log | xcbeautify

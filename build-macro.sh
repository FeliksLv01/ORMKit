#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release -Xswiftc -Osize
binary_directory=$(swift build -c release --show-bin-path)
binary_path="${binary_directory}/ORMKitMacros-tool"
if [ ! -f "${binary_path}" ]; then
  binary_path="${binary_directory}/ORMKitMacros"
  if [ ! -f "${binary_path}" ]; then
    echo "Macro executable not found in ${binary_directory}" >&2
    exit 1
  fi
fi
mkdir -p Prebuilt
cp "${binary_path}" Prebuilt/ORMKitMacros
chmod u+x Prebuilt/ORMKitMacros
strip -x Prebuilt/ORMKitMacros

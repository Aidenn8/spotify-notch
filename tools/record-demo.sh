#!/bin/bash
# Records the README demo and screenshots into docs/media (see
# tools/record-demo/main.swift). Nothing appears on screen while it runs.
set -euo pipefail
cd "$(dirname "$0")/.."
sources=()
for f in Sources/*.swift; do [[ $f == */main.swift ]] || sources+=("$f"); done
mkdir -p build
swiftc -O -target arm64-apple-macos14.0 "${sources[@]}" tools/record-demo/main.swift -o build/record-demo
build/record-demo "${1:-docs/media}"

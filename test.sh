#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$PROJECT_DIR/build"
/usr/bin/swiftc -swift-version 5 -O "$PROJECT_DIR/Sources/ProxyController.swift" "$PROJECT_DIR/Tests/ControllerTests.swift" -o "$PROJECT_DIR/build/ControllerTests"
"$PROJECT_DIR/build/ControllerTests" "$PROJECT_DIR/Tests/fixture.cjs"

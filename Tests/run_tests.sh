#!/bin/bash
# Compiles the test harness directly against the real logic files (no
# XCTest, no Xcode project/SwiftPM package — matches the rest of this
# project's swiftc-only build) and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc -O \
  Tests/main.swift \
  Sources/Models.swift \
  Sources/DuplicateGrouping.swift \
  Sources/FileCategory.swift \
  Sources/Services/HashService.swift \
  Sources/Services/DuplicateScanner.swift \
  -o /tmp/mactwin-tests

/tmp/mactwin-tests

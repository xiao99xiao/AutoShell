#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary=$(mktemp -t AutoShell-integration)
trap 'rm -f "$test_binary"' EXIT
xcrun swiftc -parse-as-library -swift-version 6 \
  AutoShell/ShellTask.swift AutoShell/TaskRunner.swift AutoShell/TaskStore.swift \
  Tests/IntegrationTests.swift -o "$test_binary"
"$test_binary"

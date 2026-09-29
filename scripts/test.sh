#!/bin/sh
# Runs the tests for the decision logic (Sources/Logic.swift).
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -o build/logic-tests Sources/Logic.swift Tests/main.swift
build/logic-tests

#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
mkdir -p build/tests
swiftc Sources/AudioModel.swift Tests/main.swift -o build/tests/check
build/tests/check

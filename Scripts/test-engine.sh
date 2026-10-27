#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p .build/engine-tests
clang++ -std=c++17 -O2 -Wall -Wextra \
    -I Sources/DiskMarkEngineCore/include \
    Sources/DiskMarkEngineCore/*.cpp \
    Tests/EngineCoreTests/main.cpp \
    -pthread \
    -o .build/engine-tests/engine-core-tests

.build/engine-tests/engine-core-tests

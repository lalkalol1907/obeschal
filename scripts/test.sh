#!/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$ROOT/.build/module-cache"
FLAGS=(--disable-sandbox --cache-path "$ROOT/.build/cache"
    --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security")

# CLT 6.4 ships Testing but its swiftbuild backend does not load this macro automatically.
SWIFT_BIN="$(dirname -- "$(xcrun --find swiftc)")"
TESTING_MACRO="$SWIFT_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TESTING_MACRO" ]]; then
    FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$TESTING_MACRO")
fi
xcrun swift test "${FLAGS[@]}" "$@"

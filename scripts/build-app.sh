#!/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p .build/module-cache .build/cache .build/config .build/security
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"
# shortcut: native avoids CLT swiftbuild dSYM failures; switch when that backend works here.
BUILD_FLAGS=(--build-system native --disable-sandbox --scratch-path "$ROOT/.build" --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security")
xcrun swift build -c release "${BUILD_FLAGS[@]}" -Xswiftc -module-cache-path -Xswiftc "$ROOT/.build/module-cache"
BIN_DIR="$(xcrun swift build -c release "${BUILD_FLAGS[@]}" --show-bin-path)"
APP="$ROOT/dist/Обещал.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Obeshchal" "$APP/Contents/MacOS/Obeshchal"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ru</string>
    <key>CFBundleDisplayName</key><string>Обещал</string>
    <key>CFBundleName</key><string>Обещал</string>
    <key>CFBundleExecutable</key><string>Obeshchal</string>
    <key>CFBundleIdentifier</key><string>local.obeshchal.app</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Обещал</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Готово: $APP"
echo "Запуск: open \"$APP\""

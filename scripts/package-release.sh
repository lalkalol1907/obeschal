#!/bin/bash
set -euo pipefail

fail() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }

[[ $# -le 1 ]] || fail "Использование: $0 vMAJOR.MINOR.PATCH[-prerelease]"
TAG="${1-${RELEASE_TAG:-}}"
NUMBER='(0|[1-9][0-9]*)'
TAG_PATTERN="^v${NUMBER}\.${NUMBER}\.${NUMBER}(-[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)?$"
[[ "$TAG" =~ $TAG_PATTERN ]] || fail "Нужен тег vMAJOR.MINOR.PATCH, например v1.0.0 или v1.0.0-rc.1."
APP_VERSION="${TAG#v}"
APP_VERSION="${APP_VERSION%%-*}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
[[ "$APP_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "APP_BUILD_NUMBER должен быть положительным целым числом."

ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) fail "Архитектура $ARCH не поддерживается." ;; esac
if [[ -n "${RELEASE_ARCH:-}" ]]; then
    case "$RELEASE_ARCH" in arm64|x86_64) ;; *) fail "RELEASE_ARCH должен быть arm64 или x86_64." ;; esac
    [[ "$RELEASE_ARCH" == "$ARCH" ]] || fail "RELEASE_ARCH=$RELEASE_ARCH не совпадает с архитектурой компьютера $ARCH."
fi

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
APP_VERSION="$APP_VERSION" APP_BUILD_NUMBER="$APP_BUILD_NUMBER" ./scripts/build-app.sh
APP="$ROOT/dist/Обещал.app"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/Obeshchal" -verify_arch "$ARCH"

STAGE_ROOT="$ROOT/.build/release-stage"
mkdir -p "$STAGE_ROOT"
STAGE="$(mktemp -d "$STAGE_ROOT/package.XXXXXX")"
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BASE="Obeshchal-${TAG}-macos-${ARCH}"
mkdir "$STAGE/volume"
ditto "$APP" "$STAGE/volume/Обещал.app"
ln -s /Applications "$STAGE/volume/Applications"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGE/$BASE.zip"
hdiutil create -srcfolder "$STAGE/volume" -volname "Обещал" -format UDZO -ov "$STAGE/$BASE.dmg"
(
    cd "$STAGE"
    shasum -a 256 "$BASE.zip" "$BASE.dmg" > "$BASE.sha256"
)
OUTPUT="$ROOT/dist/release"
mkdir -p "$OUTPUT"
mv -f -- "$STAGE/$BASE.zip" "$STAGE/$BASE.dmg" "$STAGE/$BASE.sha256" "$OUTPUT/"
printf 'Готово: %s/%s.{zip,dmg,sha256}\n' "$OUTPUT" "$BASE"

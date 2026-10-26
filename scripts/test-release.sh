#!/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/obeshchal-release-test.XXXXXX")"
trap 'rm -rf -- "$FIXTURE"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
PROJECT="$FIXTURE/project"
mkdir -p "$PROJECT/scripts" "$FIXTURE/bin"
cp "$ROOT/scripts/package-release.sh" "$PROJECT/scripts/package-release.sh"
PACKAGE="$PROJECT/scripts/package-release.sh"
export BUILD_LOG="$FIXTURE/build.log" TOOLS_LOG="$FIXTURE/tools.log"
export PATH="$FIXTURE/bin:$PATH" RELEASE_ARCH=arm64 APP_BUILD_NUMBER=1 RELEASE_TAG=

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_rejected() {
    if "$@" > "$FIXTURE/rejected.log" 2>&1; then fail "Команда должна была отклонить ввод: $*"; fi
    [[ ! -e "$BUILD_LOG" && ! -e "$PROJECT/.build" && ! -e "$PROJECT/dist" ]] || fail "Некорректный ввод вызвал сборку или создал файлы."
}

cat > "$PROJECT/scripts/build-app.sh" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s|%s\n' "$APP_VERSION" "$APP_BUILD_NUMBER" >> "$BUILD_LOG"
mkdir -p dist/Обещал.app/Contents/MacOS
printf '#!/bin/bash\nexit 0\n' > dist/Обещал.app/Contents/MacOS/Obeshchal
chmod +x dist/Обещал.app/Contents/MacOS/Obeshchal
STUB
cat > "$FIXTURE/bin/uname" <<'STUB'
#!/bin/bash
printf 'arm64\n'
STUB
chmod +x "$PACKAGE" "$PROJECT/scripts/build-app.sh" "$FIXTURE/bin/uname"
for tag in '' 'v01.2.3' 'v1.02.3' 'v1.2.03' 'v1.2' 'v1.2.3-' 'v1.2.3-rc..1' 'v1.2.3+build' '../../outside' 'v1.2.3;touch injected' 'v1.2.3/../../outside'; do
    assert_rejected "$PACKAGE" "$tag"
done
assert_rejected "$PACKAGE" $'v1.2.3\nbad'
assert_rejected "$PACKAGE" v1.2.3 extra
assert_rejected env RELEASE_ARCH=x86_64 "$PACKAGE" v1.2.3
assert_rejected env RELEASE_ARCH=universal "$PACKAGE" v1.2.3
for build in 0 01 1.2 '1;touch injected'; do
    assert_rejected env APP_BUILD_NUMBER="$build" "$PACKAGE" v1.2.3
done

cat > "$FIXTURE/bin/codesign" <<'STUB'
#!/bin/bash
set -euo pipefail
[[ "$1" == --verify && -d "${@: -1}" ]]
printf 'codesign\n' >> "$TOOLS_LOG"
STUB
cat > "$FIXTURE/bin/lipo" <<'STUB'
#!/bin/bash
set -euo pipefail
[[ "$1" == -verify_arch && "$2" == arm64 && -x "$3" ]]
printf 'lipo\n' >> "$TOOLS_LOG"
STUB
cat > "$FIXTURE/bin/hdiutil" <<'STUB'
#!/bin/bash
set -euo pipefail
[[ "${FAIL_DMG:-0}" != 1 ]] || exit 9
[[ "$1" == create ]]
shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        -srcfolder) source="$2"; shift 2 ;;
        -volname) [[ "$2" == Обещал ]]; shift 2 ;;
        -format) [[ "$2" == UDZO ]]; shift 2 ;;
        -ov) shift ;;
        *) output="$1"; shift ;;
    esac
done
[[ -d "$source/Обещал.app" && -L "$source/Applications" ]]
[[ "$(readlink "$source/Applications")" == /Applications ]]
shopt -s dotglob nullglob
entries=("$source"/*)
[[ ${#entries[@]} == 2 ]]
printf 'DMG fixture\n' > "$output"
printf 'hdiutil\n' >> "$TOOLS_LOG"
STUB
chmod +x "$PROJECT/scripts/build-app.sh" "$FIXTURE/bin/codesign" "$FIXTURE/bin/lipo" "$FIXTURE/bin/hdiutil"

env RELEASE_TAG=v9.9.9 APP_BUILD_NUMBER=7 "$PACKAGE" v2.12.3-rc.1 > "$FIXTURE/package.log"
[[ "$(cat "$BUILD_LOG")" == '2.12.3|7' ]] || fail "Версия или номер сборки переданы неверно."
BASE=Obeshchal-v2.12.3-rc.1-macos-arm64
OUTPUT="$PROJECT/dist/release"
[[ -f "$OUTPUT/$BASE.zip" && -f "$OUTPUT/$BASE.dmg" && -f "$OUTPUT/$BASE.sha256" ]] || fail "Нет всех трёх файлов релиза."
[[ "$(cat "$TOOLS_LOG")" == $'codesign\nlipo\nhdiutil' ]] || fail "Подпись, архитектура или DMG не проверены."
(
    cd "$OUTPUT"
    shasum -a 256 -c "$BASE.sha256"
)
[[ "$(wc -l < "$OUTPUT/$BASE.sha256")" -eq 2 ]] || fail "Checksum должен включать ZIP и DMG."
while read -r digest filename; do
    [[ "$filename" == "$BASE.zip" || "$filename" == "$BASE.dmg" ]] || fail "Checksum должен содержать относительные имена файлов."
done < "$OUTPUT/$BASE.sha256"
ditto -x -k "$OUTPUT/$BASE.zip" "$FIXTURE/extracted"
[[ -x "$FIXTURE/extracted/Обещал.app/Contents/MacOS/Obeshchal" ]] || fail "ZIP потерял имя приложения или executable permission."
[[ ! -e "$FIXTURE/extracted/scripts" ]] || fail "ZIP содержит исходники проекта."

if env APP_BUILD_NUMBER=7 FAIL_DMG=1 "$PACKAGE" v2.12.3-rc.1 > "$FIXTURE/failure.log" 2>&1; then
    fail "Ошибка hdiutil должна останавливать упаковку."
fi
(
    cd "$OUTPUT"
    shasum -a 256 -c "$BASE.sha256"
)
shopt -s nullglob
stages=("$PROJECT/.build/release-stage"/package.*)
[[ ${#stages[@]} == 0 ]] || fail "Временная папка упаковки не удалена."

env RELEASE_TAG=v0.0.0 "$PACKAGE" > "$FIXTURE/environment-tag.log"
[[ -f "$OUTPUT/Obeshchal-v0.0.0-macos-arm64.zip" ]] || fail "RELEASE_TAG не используется без аргумента."
printf 'Release packaging tests passed.\n'

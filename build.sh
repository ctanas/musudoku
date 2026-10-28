#!/bin/bash
# muSudoku: build script
#
#   ./build.sh          build the muOS package  -> build/muSudoku_vX.Y.Z.muxapp
#   ./build.sh love     build a .love file for testing on a PC -> build/muSudoku.love
#   ./build.sh test     run the engine and puzzle pack tests (needs luajit)
#   ./build.sh run      run the game on this PC (needs love 11.5)
#
# The muxapp bundles an aarch64 LÖVE 11.5 runtime (bin/love + bin/libs.aarch64).
# By default it is taken from the 2048 Plus project (MIT licensed, already
# proven on muOS H700 devices) at a pinned tag. To use your own runtime, set
# LOVE_RUNTIME=/path/to/dir containing love and libs.aarch64/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/musudoku"
APP_NAME="muSudoku"
RUNTIME_REPO="https://github.com/saitamasahil/2048plus.git"
RUNTIME_TAG="v7.0.1"

VERSION="$(grep -oE 'VERSION = "[0-9.]+"' "$ROOT/game/main.lua" | grep -oE '[0-9.]+')"
[ -n "$VERSION" ] || { echo "Could not read VERSION from game/main.lua"; exit 1; }

fetch_runtime() {
    if [ -n "${LOVE_RUNTIME:-}" ]; then
        [ -x "$LOVE_RUNTIME/love" ] && [ -d "$LOVE_RUNTIME/libs.aarch64" ] || {
            echo "LOVE_RUNTIME must contain 'love' and 'libs.aarch64/'"; exit 1; }
        RUNTIME_DIR="$LOVE_RUNTIME"
        return
    fi
    RUNTIME_DIR="$CACHE/runtime-$RUNTIME_TAG"
    if [ ! -x "$RUNTIME_DIR/bin/love" ]; then
        echo "Downloading aarch64 LÖVE runtime ($RUNTIME_TAG)..."
        rm -rf "$RUNTIME_DIR"
        mkdir -p "$CACHE"
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$RUNTIME_TAG" --filter=blob:none --sparse \
            "$RUNTIME_REPO" "$RUNTIME_DIR"
        git -C "$RUNTIME_DIR" sparse-checkout set bin licenses >/dev/null
    fi
    RUNTIME_DIR="$RUNTIME_DIR/bin"
    RUNTIME_LICENSES="$CACHE/runtime-$RUNTIME_TAG/licenses"
}

copy_game() {
    local dest="$1"
    mkdir -p "$dest"
    (cd "$ROOT/game" && tar --exclude='./dev' -cf - .) | (cd "$dest" && tar -xf -)
}

build_muos() {
    fetch_runtime
    local stage="$BUILD/stage"
    local app="$stage/$APP_NAME"
    local out="$BUILD/${APP_NAME}_v${VERSION}.muxapp"
    rm -rf "$stage" "$out"
    mkdir -p "$app/glyph" "$app/.game/bin" "$app/.game/licenses"

    cp "$ROOT/mux_launch.sh" "$ROOT/mux_lang.ini" "$app/"
    cp "$ROOT/glyph/musudoku.svg" "$ROOT/glyph/musudoku.png" "$app/glyph/"
    mkdir -p "$app/packs"
    cp "$ROOT"/packs/*.txt "$app/packs/" 2>/dev/null || true
    copy_game "$app/.game"
    cp "$RUNTIME_DIR/love" "$app/.game/bin/"
    cp -r "$RUNTIME_DIR/libs.aarch64" "$app/.game/bin/"

    cp "$ROOT/LICENSE" "$app/.game/licenses/musudoku.LICENSE"
    cp "$ROOT/game/assets/fonts/OFL.txt" "$app/.game/licenses/AtkinsonHyperlegible.OFL.txt"
    if [ -n "${RUNTIME_LICENSES:-}" ] && [ -f "$RUNTIME_LICENSES/love.LICENSE" ]; then
        cp "$RUNTIME_LICENSES/love.LICENSE" "$app/.game/licenses/love.LICENSE"
        cp "$RUNTIME_LICENSES/2048plus.LICENSE" "$app/.game/licenses/runtime-from-2048plus.LICENSE" 2>/dev/null || true
    fi

    chmod +x "$app/mux_launch.sh" "$app/.game/bin/love"
    mkdir -p "$BUILD"
    (cd "$stage" && zip -qr -X "$out" "$APP_NAME")
    rm -rf "$stage"
    echo "Built $(basename "$out") ($(du -h "$out" | cut -f1))"
    echo "Copy it to /mnt/mmc/MUOS/ARCHIVE/ and install with Applications > Archive Manager."
}

build_love() {
    local stage="$BUILD/love-stage"
    local out="$BUILD/${APP_NAME}.love"
    rm -rf "$stage" "$out"
    copy_game "$stage"
    mkdir -p "$BUILD"
    (cd "$stage" && zip -qr -X "$out" .)
    rm -rf "$stage"
    echo "Built $(basename "$out")  (run with: love build/${APP_NAME}.love)"
}

find_love() {
    if command -v love >/dev/null 2>&1; then
        echo love
    elif [ -x /Applications/love.app/Contents/MacOS/love ]; then
        echo /Applications/love.app/Contents/MacOS/love
    else
        echo "LÖVE 11.5 not found. Install it from https://love2d.org" >&2
        return 1
    fi
}

case "${1:-muos}" in
    muos) build_muos ;;
    love) build_love ;;
    test) (cd "$ROOT" && luajit tests/test_sudoku.lua "${2:-10}" && luajit tests/test_packs.lua && luajit tests/test_hints.lua) ;;
    run)
        shift
        LOVE_BIN="$(find_love)"
        export MUSUDOKU_PACKS="${MUSUDOKU_PACKS:-$ROOT/packs}"
        cd "$ROOT" && "$LOVE_BIN" game "$@"
        ;;
    *) echo "Usage: ./build.sh [muos|love|test|run]"; exit 1 ;;
esac

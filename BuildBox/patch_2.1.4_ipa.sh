#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

UPSTREAM_VERSION="v2.1.4"
WORK_DIR="/tmp/buildbox-patch"
mkdir -p "$WORK_DIR"

ORIG_IPA="$WORK_DIR/BuildBox-2.1.4-upstream.ipa"
if [ ! -f "$ORIG_IPA" ]; then
    echo "==> Downloading official upstream BuildBox 2.1.4 IPA..."
    gh release download "$UPSTREAM_VERSION" --repo mikevillarroel/buildbox-ios --pattern "*.ipa" --output "$ORIG_IPA"
fi

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "==> Compiling BuildBoxRunnerHook.dylib..."
xcrun clang -target arm64-apple-ios17.0 \
    -isysroot "$SDK_PATH" \
    -dynamiclib \
    -fobjc-arc \
    -framework Foundation \
    hooks/BuildBoxRunnerHook.m \
    -install_name @rpath/BuildBoxRunnerHook.dylib \
    -o "$WORK_DIR/BuildBoxRunnerHook.dylib"

OUT_IPA="$DIR/BuildBox-2.1.4-selfhosted.ipa"
echo "==> Injecting hook into BuildBox 2.1.4 IPA..."
zsign -l "$WORK_DIR/BuildBoxRunnerHook.dylib" -a -o "$OUT_IPA" "$ORIG_IPA"

echo "==> Successfully created: $OUT_IPA"
ls -lh "$OUT_IPA"

# Mirror to iCloud Drive for iPhone (local builds)
ICLOUD_BASE="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
if [ -z "$CI" ] && [ -z "$GITHUB_ACTIONS" ] && [ -d "$ICLOUD_BASE" ]; then
    echo "==> Mirroring to iCloud Drive..."
    cp "$OUT_IPA" "$ICLOUD_BASE/" 2>/dev/null || true
    if [ -d "$ICLOUD_BASE/Downloads" ]; then
        cp "$OUT_IPA" "$ICLOUD_BASE/Downloads/" 2>/dev/null || true
    fi
    echo "  Synced to iCloud: $ICLOUD_BASE/$(basename "$OUT_IPA")"
fi

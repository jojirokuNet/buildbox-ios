#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
BUILD_DIR="$DIR/build"
OBJ_DIR="$BUILD_DIR/obj"
APP_DIR="$BUILD_DIR/Payload/BuildBox.app"

rm -rf "$BUILD_DIR"
mkdir -p "$OBJ_DIR" "$APP_DIR/Frameworks"

echo "==> 1. Compiling C files..."
C_FLAGS="-target arm64-apple-ios17.0 -isysroot $SDK_PATH -O2 -Isrc/zsign/third-party/zlib -Isrc/zsign/third-party/minizip -w"
for f in $(find src -name "*.c"); do
    obj="$OBJ_DIR/$(basename "${f%.c}").o"
    echo "  clang: $f -> $obj"
    xcrun clang $C_FLAGS -c "$f" -o "$obj"
done

echo "==> 2. Compiling C++ files..."
CXX_FLAGS="-target arm64-apple-ios17.0 -isysroot $SDK_PATH -O2 -std=c++17 -Isrc/zsign -Isrc/zsign/common -Isrc/zsign/include -Iframeworks/OpenSSL.framework/Headers -Fframeworks -fno-modules -w"
for f in $(find src -name "*.cpp"); do
    obj="$OBJ_DIR/$(basename "${f%.cpp}").o"
    echo "  clang++: $f -> $obj"
    xcrun clang++ $CXX_FLAGS -c "$f" -o "$obj"
done

echo "==> 3. Compiling ObjC++ files..."
OBJCXX_FLAGS="-target arm64-apple-ios17.0 -isysroot $SDK_PATH -O2 -std=c++17 -fobjc-arc -Isrc/zsign -Isrc/zsign/common -Isrc/zsign/include -Iframeworks/OpenSSL.framework/Headers -Fframeworks -fno-modules -w"
for f in $(find src -name "*.mm"); do
    obj="$OBJ_DIR/$(basename "${f%.mm}").o"
    echo "  clang++ (mm): $f -> $obj"
    xcrun clang++ $OBJCXX_FLAGS -c "$f" -o "$obj"
done

echo "==> 4. Compiling Swift files and linking binary..."
SWIFT_FILES=$(find src -name "*.swift" | sort)
ALL_OBJS=$(find "$OBJ_DIR" -name "*.o")

xcrun swiftc \
    -target arm64-apple-ios17.0 \
    -sdk "$SDK_PATH" \
    -O \
    -import-objc-header src/Bridging.h \
    -I src/zsign \
    -I src/zsign/common \
    -I src/zsign/include \
    -I frameworks/OpenSSL.framework/Headers \
    -F frameworks \
    -framework Foundation \
    -framework UIKit \
    -framework SwiftUI \
    -framework Security \
    -framework CryptoKit \
    -framework Network \
    -framework OpenSSL \
    -lc++ \
    -lz \
    -lcompression \
    -Xlinker -rpath -Xlinker @executable_path/Frameworks \
    -o "$APP_DIR/BuildBox" \
    $SWIFT_FILES \
    $ALL_OBJS

echo "==> 5. Preparing app bundle..."
# Frameworks
cp -R frameworks/OpenSSL.framework "$APP_DIR/Frameworks/"

# Resources
if [ -d res ]; then
    cp -R res/* "$APP_DIR/" 2>/dev/null || true
fi

# Info.plist & PkgInfo
if [ -f Info.plist ]; then
    cp Info.plist "$APP_DIR/"
fi
if [ -f PkgInfo ]; then
    cp PkgInfo "$APP_DIR/"
fi

echo "==> 6. Creating unsigned IPA..."
cd "$BUILD_DIR"
zip -qry "$DIR/BuildBox-unsigned.ipa" Payload
echo "==> Done! Created: $DIR/BuildBox-unsigned.ipa"
ls -lh "$DIR/BuildBox-unsigned.ipa"

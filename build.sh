#!/bin/bash
# 构建 PortDock.app（universal binary，零运行时依赖）
# 用法: ./build.sh          → ad-hoc 签名（本机开发用）
#       SIGN_ID="Developer ID Application: ..." ./build.sh  → 分发签名
set -euo pipefail
cd "$(dirname "$0")"

APP=build/PortDock.app
SIGN_ID="${SIGN_ID:--}"
SOURCES=(Sources/Main.swift Sources/Models.swift Sources/Monitor.swift Sources/AppState.swift Sources/Views.swift)

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target "$arch-apple-macos14.0" \
    "${SOURCES[@]}" -o "build/PortDock-$arch"
done
lipo -create build/PortDock-arm64 build/PortDock-x86_64 -output "$APP/Contents/MacOS/PortDock"
rm build/PortDock-arm64 build/PortDock-x86_64

cp Info.plist "$APP/Contents/"
cp icon/AppIcon.icns "$APP/Contents/Resources/"

if [ "$SIGN_ID" = "-" ]; then
  codesign --force -s - "$APP"
else
  # 公证硬要求：hardened runtime + 时间戳
  codesign --force --options runtime --timestamp -s "$SIGN_ID" "$APP"
fi

echo "构建完成: $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/PortDock"))"

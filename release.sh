#!/bin/bash
# 发布 PortDock：构建 → Developer ID 签名 → 公证 → staple → DMG
# 前提（一次性）:
#   1. 钥匙串里有 "Developer ID Application" 证书
#   2. xcrun notarytool store-credentials portdock --apple-id <邮箱> --team-id 8YN9YJS5TL --password <App专用密码>
# 用法: ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
SIGN_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[ -n "$SIGN_ID" ] || { echo "错误: 钥匙串里没有 Developer ID Application 证书"; exit 1; }
echo "签名身份: $SIGN_ID  版本: $VERSION"

SIGN_ID="$SIGN_ID" ./build.sh
APP=build/PortDock.app

# 公证（zip 提交）→ 给 .app 盖章（staple，离线也能过 Gatekeeper）
ditto -c -k --keepParent "$APP" build/PortDock.zip
xcrun notarytool submit build/PortDock.zip --keychain-profile portdock --wait
xcrun stapler staple "$APP"
rm build/PortDock.zip

# 打 DMG（含 Applications 快捷方式）并签名
DMG="build/PortDock-$VERSION.dmg"
STAGE=build/dmg-stage
rm -rf "$STAGE" "$DMG"
mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "PortDock" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp -s "$SIGN_ID" "$DMG"
rm -rf "$STAGE"

spctl -a -vv "$APP" && echo "Gatekeeper 校验通过"
echo "发布物: $(pwd)/$DMG"
echo "下一步: gh release create v$VERSION $DMG --title \"PortDock $VERSION\""

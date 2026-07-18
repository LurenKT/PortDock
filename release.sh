#!/bin/bash
# 发布 PortDock：构建 → Developer ID 签名 → 公证 → staple → DMG
# 前提（一次性）:
#   1. 钥匙串里有 "Developer ID Application" 证书
#   2. xcrun notarytool store-credentials portdock --apple-id <邮箱> --team-id HMUSRH2JG9 --password <App专用密码>
# 用法: ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
SIGN_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[ -n "$SIGN_ID" ] || { echo "错误: 钥匙串里没有 Developer ID Application 证书"; exit 1; }
echo "签名身份: $SIGN_ID  版本: $VERSION"

SIGN_ID="$SIGN_ID" ./build.sh
# 公证排队可长达 1 小时+，期间 build/ 可能被并发 ./build.sh 覆盖（1.0.0 首发就栽在这）
# ——签名后的 app 先挪进独立暂存目录，公证、盖章、打 DMG 全在暂存里做
WORK=$(mktemp -d /tmp/portdock-release.XXXXXX)
APP="$WORK/PortDock.app"
ditto build/PortDock.app "$APP"

# 公证（zip 提交）
ditto -c -k --keepParent "$APP" "$WORK/PortDock.zip"
xcrun notarytool submit "$WORK/PortDock.zip" --keychain-profile portdock --wait

# 盖章（staple，离线也能过 Gatekeeper）。票据同步到 Apple CDN 有延迟，失败等 1 分钟重试
stapled=0
for i in $(seq 1 30); do
  if xcrun stapler staple "$APP"; then stapled=1; break; fi
  echo "票据未同步（第 $i/30 次），60 秒后重试"; sleep 60
done
[ "$stapled" = 1 ] || { echo "盖章重试耗尽"; exit 1; }

# 打 DMG（含 Applications 快捷方式）并签名，产物放 dist/（build/ 会被下次构建清掉）
mkdir -p dist
DMG="dist/PortDock-$VERSION.dmg"
STAGE="$WORK/dmg-stage"
mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "PortDock" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp -s "$SIGN_ID" "$DMG"

spctl -a -vv "$APP" && echo "Gatekeeper 校验通过"
rm -rf "$WORK"
echo "发布物: $(pwd)/$DMG"
echo "下一步: gh release create v$VERSION $DMG --title \"PortDock $VERSION\""

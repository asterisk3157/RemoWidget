#!/bin/bash
# RemoWidget のビルドとインストール。
#
#   ./build.sh          ビルドのみ
#   ./build.sh install  ビルドして ~/Applications へ配置し、アプリを起動する
#   ./build.sh reregister  ビルドせず、配置済みアプリの Intent 登録をやり直す
#                          （ボタンが反応しないとき。README のトラブルシュート参照）
#
# ウィジェットは「アプリが Launch Services に登録されている」ことで
# ウィジェットギャラリーに現れる。DerivedData 内のままだと不安定なため
# インストール先へ配置してから起動する。
set -euo pipefail

cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# アプリと拡張を登録し直し、Intent を管理する linkd / chronod を再起動する。
# 登録が外れると「There is no metadata for ... Intent」でボタンだけ無反応になる。
reregister() {
  local app="$1"
  "$LSREGISTER" -f -R -trusted "$app"
  pluginkit -a "$app/Contents/PlugIns/RemoWidgetExtension.appex"
  killall linkd chronod 2>/dev/null || true
}

if [ "${1:-}" = "reregister" ]; then
  reregister "$HOME/Applications/RemoWidget.app"
  echo "==> reregistered"
  exit 0
fi

PROJECT=RemoWidget.xcodeproj
SCHEME=RemoWidget
DEST="$HOME/Applications"

# .xcodeproj は毎回作り直す。
# project.yml の変更だけを条件にすると、ソースファイルを新規追加したときに
# 生成が走らず「cannot find type」で落ちる（実際に踏んだ）。生成は一瞬なので常に実行する。
echo "==> xcodegen"
xcodegen generate --quiet

echo "==> build"
# パイプで grep すると xcodebuild の終了コードが隠れるので PIPESTATUS で拾う。
# これを見ないとビルド失敗時に古いバイナリをインストールしてしまう。
set +e
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  build | grep -E "error:|warning:|BUILD"
STATUS=${PIPESTATUS[0]}
set -e

if [ "$STATUS" -ne 0 ]; then
  echo "ビルドに失敗しました (exit $STATUS)。インストールは行いません。"
  exit "$STATUS"
fi

APP="build/Build/Products/Debug/RemoWidget.app"
[ -d "$APP" ] || { echo "ビルド成果物が見つかりません"; exit 1; }

if [ "${1:-}" = "install" ]; then
  mkdir -p "$DEST"

  # 起動中なら止めてから差し替える（ウィジェット拡張が掴んだままだと失敗する）
  osascript -e 'quit app "RemoWidget"' 2>/dev/null || true
  pkill -f "RemoWidgetExtension" 2>/dev/null || true

  # 旧版は削除せず ~/.trash へ退避する
  if [ -d "$DEST/RemoWidget.app" ]; then
    mkdir -p "$HOME/.trash"
    mv "$DEST/RemoWidget.app" "$HOME/.trash/RemoWidget.app.$(date +%s)"
  fi

  cp -R "$APP" "$DEST/"
  # Launch Services に登録し直してウィジェットギャラリーへ反映させる
  reregister "$DEST/RemoWidget.app"

  echo "==> installed: $DEST/RemoWidget.app"
  open "$DEST/RemoWidget.app"
fi

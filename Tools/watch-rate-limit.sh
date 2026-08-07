#!/bin/bash
# レート制限の消費量を観測する（NFR-2 の検証）。
#
#   ./Tools/watch-rate-limit.sh [間隔秒] [回数]
#
# ウィジェットが記録した値を App Group の UserDefaults から読むだけなので、
# 観測そのものが API を消費しない。上限は 30 リクエスト / 5 分。
set -euo pipefail

INTERVAL=${1:-60}
COUNT=${2:-60}
# Team ID は環境によって違うので、グループコンテナを名前で探す
GROUP_DIR=$(find "$HOME/Library/Group Containers" -maxdepth 1 -name "*.com.shironoir.remowidget" 2>/dev/null | head -1)
PLIST="$GROUP_DIR/Library/Preferences/$(basename "$GROUP_DIR").plist"
LOG="$(cd "$(dirname "$0")/.." && pwd)/rate-limit.log"

[ -f "$PLIST" ] || { echo "App Group の設定が見つかりません: $PLIST"; exit 1; }

echo "# 観測開始 $(date '+%Y-%m-%d %H:%M:%S') / ${INTERVAL}秒 x ${COUNT}回" | tee -a "$LOG"
echo "# time	remaining/limit	fetchedAt" | tee -a "$LOG"

for _ in $(seq "$COUNT"); do
  # snapshot は JSON を Data として保存しているので、plutil で取り出して復号する
  JSON=$(plutil -extract snapshot raw -o - "$PLIST" 2>/dev/null | base64 -d 2>/dev/null || true)

  if [ -n "$JSON" ]; then
    LINE=$(printf '%s' "$JSON" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("(解析できません)"); raise SystemExit
r = d.get("rateLimit")
if r:
    print(f'"'"'{r["remaining"]}/{r["limit"]}\t{d.get("fetchedAt","-")}'"'"')
else:
    print("(レート制限情報なし)")
' 2>/dev/null || echo "(読み取り失敗)")
  else
    LINE="(スナップショット未保存)"
  fi

  printf '%s\t%s\n' "$(date '+%H:%M:%S')" "$LINE" | tee -a "$LOG"
  sleep "$INTERVAL"
done

echo "# 観測終了 $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG"

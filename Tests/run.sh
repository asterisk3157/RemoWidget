#!/bin/bash
# AirconLogic の単体テスト。Xcode を起動せず swiftc だけで走る。
# ネットワークに触れないので実機・API 制限と無関係に何度でも実行できる。
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

# トップレベルの実行文を許すため main.swift という名前で渡す
cp Tests/LogicTests.swift "$OUT/main.swift"

swiftc -O \
  Sources/RemoKit/Models.swift \
  Sources/RemoKit/AirconLogic.swift \
  Sources/RemoKit/LightLogic.swift \
  "$OUT/main.swift" \
  -o "$OUT/logictests"

"$OUT/logictests"

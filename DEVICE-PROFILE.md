# M0: 実機プロファイル（実測記録）

取得日: 2026-08-07 / `GET /1/appliances` `GET /1/devices` の実レスポンスより作成。
機器 ID・MAC アドレス・シリアル番号は本書に載せない（生レスポンスは `.gitignore` 済み）。

---

## レート制限（実測・確定）

```
x-rate-limit-limit: 30
x-rate-limit-remaining: 28
x-rate-limit-reset: <epoch>
```

要件書 §5 の推定どおり **30 リクエスト / 5 分**。ヘッダ名はすべて小文字（HTTP/2）なので、**大文字小文字を区別せずに読む**こと。

---

## Remo 本体

| 項目 | 値 |
|------|-----|
| モデル | **Remo mini** (`Remo-mini/1.14.8`) |
| 台数 | 1 |
| 提供センサー | **温度のみ**（`newest_events.te`） |
| オンライン状態 | `online: true` フィールドあり |
| 補正値 | `temperature_offset: 0` / `humidity_offset: 0` |

```json
"newest_events": { "te": { "val": 24.1, "created_at": "..." } }
```

### ⚠️ 湿度は取得できない
Remo mini には**湿度センサーが無い**（`hu` キーが存在しない）。Remo 3 / Remo nano 等への買い替えなしに FR-9 の湿度表示は実現不可。
→ **v1 は室温のみ**。ただし実装は `hu` / `il` / `mo` が存在すれば表示する条件分岐にし、機器を買い替えた時点でコード変更なしに湿度が出るようにする。

### 注意: フィールド名
`/1/devices` の機器名は `nickname` **ではなく `name`**（`/1/appliances` 側は `nickname`）。混同しやすい。

---

## 登録機器（3 台）

| type | 名称 | 備考 |
|------|------|------|
| AC | エアコン | 操作対象（D-4 のエアコン 1 台） |
| LIGHT | 照明 A | |
| LIGHT | 照明 B | `on-favorite` ボタンを追加で持つ |

### ライトの状態取得 ✅
両機とも `light.state` を返す。**R-4 のリスクは解消**、トグル UI で問題ない。

```json
"state": { "brightness": "100", "power": "on", "last_button": "on" }
```

利用可能ボタン（2 台で微差あり。**機器ごとに `light.buttons` を読んで UI を作ること**）:

| ボタン | 照明 A | 照明 B |
|--------|:---:|:---:|
| `on` / `off` | ✅ | ✅ |
| `on-100` (All) | ✅ | ✅ |
| `on-favorite` | ❌ | ✅ |
| `night` | ✅ | ✅ |
| `bright-up` / `bright-down` | ✅ | ✅ |
| `colortemp-up` / `colortemp-down` | ✅ | ✅ |

---

## エアコン `aircon.range`（最重要）

`tempUnit: "c"` / `fixedButtons: null`

| mode | temp | vol | dir / dirh |
|------|------|-----|-----|
| **cool** | 18 〜 30（**0.5 刻み**, 25 段） | 1,2,3,4,auto | auto, swing |
| **warm** | 16 〜 30（**0.5 刻み**, 29 段） | 1,2,3,4,auto | auto, swing |
| **dry** | 18 〜 30（0.5 刻み） | **`[""]` = 風量指定不可** | auto, swing |
| **blow** | **`[""]` = 温度指定不可** | 1,2,3,4,auto | auto, swing |
| **auto** | **`-2` 〜 `+2`（0.5 刻みの相対値）** | 1,2,3,4,auto | auto, swing |

現在の設定（取得時点）:
```json
{ "temp": "22", "temp_unit": "c", "mode": "cool", "vol": "4",
  "dir": "auto", "dirh": "auto", "button": "" }
```

### ここから確定する設計判断

1. **温度は 0.5℃ 刻み** — 「現在値 ±1」の単純加算は破綻する。要件書 FR-14 の「range のリストを 1 ステップ移動」が必須であることが実データで裏付けられた。
2. **auto モードの temp は絶対温度ではなく相対値**（`-2`〜`+2`）。UI では `24.5℃` ではなく `+0.5` のように**モードによって表示を切り替える**必要がある。
3. **モードごとに操作できる軸が違う** — `dry` は風量不可、`blow` は温度不可。UI はモードに応じて要素を出し分ける（無効なパラメータを送らない）。
4. **モード間で温度範囲が違う**（cool は 18〜、warm は 16〜）。`warm 16.0℃ → cool` の切替では 16.0 が範囲外になるため、FR-15 のフォールバックが実際に必要。
5. **風量は 1〜4 と auto の 5 段**（API 仕様上の上限 10 ではない）。ハードコードせず `range` から読む。

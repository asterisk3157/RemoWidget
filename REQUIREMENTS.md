# RemoWidget — Nature Remo 家電操作 macOS ウィジェット 要件定義書

- 版: v1.0（2026-08-07）
- 起点資料: [Mac から Nature Remo を操作する（note / motolyo）](https://note.com/motolyo/n/n02724d6d7d40)

---

## 1. 背景と目的

Nature Remo には **公式 macOS アプリが存在しない**。iPhone を取り出すか、ブラウザで Nature のコンソールを開くしかない。
起点資料は Cloud API を curl で叩き、Stream Deck からシェルスクリプトを実行する方法を示した。これは有効だが、

- Stream Deck という**専用ハードに依存**する
- **一方通行**（送りっぱなしで、現在の設定も室温も見えない）
- ボタンごとに `.sh` を作る**静的な構成**（温度を 1℃ 上げる、が作れない）

本プロジェクトは同じ Cloud API を使いつつ、**macOS のウィジェット（通知センター / デスクトップ）から、状態を見ながら双方向に操作する**ことを目的とする。

### ゴール（この定義で「完成」とする）
デスクトップに置いたウィジェットに現在の室温・湿度とエアコンの設定が表示され、そこから **アプリを開かずに** エアコンの電源・モード・温度・風量とライトの ON/OFF を操作できる。

### 非ゴール（v1 では作らない）
- 一般公開・配布（個人利用に限定。`~/Production` への移行は将来判断）
- テレビ / カーテン等、エアコンとライト以外の機器
- スケジュール実行・オートメーション（Nature 本体アプリの領分）
- iOS / iPadOS 版

---

## 2. 決定事項（本要件の前提）

| # | 論点 | 決定 | 理由 |
|---|------|------|------|
| D-1 | アプリ形態 | **WidgetKit の通知センター / デスクトップウィジェット** | 「常時見えて、その場で押せる」が要件の核。メニューバー常駐は却下 |
| D-2 | エアコン操作粒度 | **電源・3 モード（冷房 / 暖房 / 除湿）・温度 ±**。<br>**風量は最大固定・風向は swing 固定**。`auto` / `blow` モードは扱わない | 2026-08-07 確定。風量と風向を固定値にできるため選択 UI が不要になり、Medium サイズに全機能が収まる |
| D-2b | ライト操作 | **2 台を常に同時操作**する 3 ボタンのみ（全灯 / 豆電球 / 消灯）。個別操作はしない | 2026-08-07 確定。2 台の照明を別々に制御する運用が無い |
| D-3 | センサー表示 | **室温のみ**（当初は室温・湿度で合意したが、実機 Remo mini に湿度センサーが無いことが M0 で判明） | 実機制約。`hu` が来れば表示する実装にして買い替えに備える |
| D-4 | 対象機器 | エアコン **1 台** + ライト **2 台**（常に同時操作） | 実機構成どおり |
| D-5 | 配布 | しない。ローカル開発署名でローカルインストールのみ | Developer ID を使わない方針を維持する |

---

## 3. 前提条件（着手前に満たす必要がある）

| # | 項目 | 現状 | 必要な対応 |
|---|------|------|-----------|
| P-1 | **Xcode 本体** | ✅ 26.5 導入済み（`/Applications/Xcode.app`） | `xcode-select` が CommandLineTools を指しているため、Xcode 側へ切り替える（sudo 必要） |
| P-2 | macOS バージョン | ✅ 26.2 | インタラクティブウィジェットは macOS 14+。問題なし |
| P-3 | Apple Developer Team | ✅ 加入中 | App Group / Keychain Access Group に Team ID が必要。**配布には使わない**（ローカル署名のみ） |
| P-4 | Nature アカウント | 要確認 | `https://home.nature.global/` でアクセストークン発行 |
| P-5 | Nature Remo 実機 | 要確認 | エアコンとライトが登録済みであること |

> `~/tmp` の「Swift 単一ファイル + build.sh」方針は WidgetKit では成立しないため、本プロジェクトのみ Xcode プロジェクト構成を採る（§10 で検討済み・B-3 を採用）。

---

## 4. システム構成

```
RemoWidget.xcodeproj
├── RemoKit                (共有フレームワーク / ローカル Swift Package)
│   ├── NatureAPIClient    … Cloud API 呼び出し・レート制限管理
│   ├── Models             … Appliance / AirconSettings / Light / SensorReading
│   ├── TokenStore         … Keychain (Access Group 共有)
│   └── SharedCache        … App Group UserDefaults 上のスナップショット + TTL
├── RemoWidget             (コンテナアプリ / メインアプリ)
│   └── 設定 UI: トークン入力・機器選択・接続テスト
└── RemoWidgetExtension    (Widget Extension)
    ├── TimelineProvider   … SharedCache 経由で表示データを供給
    ├── SwiftUI Views      … Small / Medium / Large
    └── AppIntents         … ボタン押下 → API 送信 → リロード
```

- **App Group**: `group.<TeamID>.com.shironoir.remowidget` — キャッシュ・設定の共有
- **Keychain Access Group**: 同上 — アクセストークンをアプリと拡張の両方から読む
- **App Sandbox**: 有効（`com.apple.security.network.client` のみ許可）

### なぜコンテナアプリが要るか
ウィジェット拡張には設定入力の UI を持てない。トークン入力・機器選択・接続テストはコンテナアプリ側で行い、結果を App Group / Keychain 経由で拡張に渡す。

---

## 5. 外部インターフェース（Nature Cloud API）

ベース URL: `https://api.nature.global/1`
認証: `Authorization: Bearer <ACCESS_TOKEN>`（起点資料と同じ）

| 用途 | メソッド | パス | 主なパラメータ / 戻り |
|------|---------|------|----------------------|
| 機器一覧・現在設定 | GET | `/appliances` | 各 appliance の `id` `type` `nickname` `aircon`(range) `settings` `light.state` |
| Remo 本体・センサー | GET | `/devices` | `newest_events.te.val`(温度) `hu.val`(湿度) と各々の `created_at` |
| エアコン操作 | POST | `/appliances/{id}/aircon_settings` | `button`(""=ON / "power-off") `operation_mode`(cool/warm/dry/blow/auto) `temperature` `air_volume`(auto/1〜10) `air_direction` |
| ライト操作 | POST | `/appliances/{id}/light` | `button`: `on` / `off` / `on-100` / `night` / `bright-up` / `bright-down` |

- リクエストボディは `application/x-www-form-urlencoded`
- 操作系 API は**成功すると更新後の設定オブジェクトを返す**ため、追加の GET は不要
- **`aircon.range` に機種ごとの選択可能値**（モード別の温度リスト・風量リスト）が入る。UI はこれを読んで動的に構成し、機種にない値を送らない

### レート制限（設計上の最重要制約）
- **30 リクエスト / 5 分**（M0 で実測確定）。応答ヘッダ `x-rate-limit-limit` / `x-rate-limit-remaining` / `x-rate-limit-reset`(epoch) を参照する
- HTTP/2 のためヘッダ名は小文字で返る。**大文字小文字を区別せずに読む**こと

### 実機で確定した仕様（詳細は [DEVICE-PROFILE.md](DEVICE-PROFILE.md)）
- 温度は **0.5℃ 刻み**（cool 18〜30 / warm 16〜30）
- `auto` モードの `temp` は絶対温度でなく **相対値 `-2`〜`+2`**
- `dry` は風量指定不可、`blow` は温度指定不可（`range` が `[""]`）
- 風量は **1〜4 + auto の 5 段**（API 仕様上限の 10 ではない）
- ライトは `light.state`（`power` / `brightness`）を返す → **R-4 解消**
- ライトの利用可能ボタンは**機器ごとに異なる**（`on-favorite` の有無）
- `/1/devices` の機器名フィールドは `nickname` ではなく **`name`**、`online` フラグあり

---

## 6. 機能要件（FR）

### 6.1 設定（コンテナアプリ）

| ID | 要件 |
|----|------|
| FR-1 | アクセストークンを入力・保存できる。保存先は **Keychain**（Access Group 共有）。UserDefaults / 平文ファイルには**書かない** |
| FR-2 | 「接続テスト」ボタンで `GET /appliances` を実行し、成功/失敗と機器数を表示する |
| FR-3 | 取得した機器一覧から、ウィジェットで操作する **エアコン 1 台** を選択できる |
| FR-4 | 同様に、操作する **ライトを複数選択** できる（順序も指定可能） |
| FR-5 | センサー値の取得元となる Remo 本体を選択できる（複数台ある場合。1 台なら自動選択） |
| FR-6 | 設定変更時、`WidgetCenter.shared.reloadAllTimelines()` でウィジェットを即時更新する |

### 6.2 表示（ウィジェット）

| ID | 要件 |
|----|------|
ウィジェットに載る操作要素は以下がすべて（風量・風向は固定値のため UI を持たない）。

| ID | 要件 |
|----|------|
| FR-7 | **systemSmall**: 室温 / エアコンの現在設定（モード・温度）/ 電源トグル。ライトは載せない |
| FR-8 | **systemMedium**: 室温 / エアコンの現在設定 / モード 3 ボタン（冷房・暖房・除湿）/ 温度 − + / 停止 / ライト 3 ボタン（全灯・豆電球・消灯）。**これが主力サイズで、全機能が収まる** |
| FR-9 | **systemLarge**: Medium と同一機能を、余白を取って大きなタップ領域で配置する |
| FR-9b | センサー表示は**取得できた項目だけを描画**する。湿度 `hu` / 照度 `il` / 人感 `mo` は、`newest_events` に存在する場合のみ表示する（Remo 買い替え時にコード変更なしで湿度が出るようにするため） |
| FR-10 | センサー値には**取得時刻**を併記する（ウィジェットの更新は OS 都合で遅れうるため、鮮度をユーザーに委ねる） |
| FR-11 | エアコン OFF 時は温度・モードを淡色表示にする |
| FR-11b | **除湿モードでは温度の − + を非表示にしない**（除湿は温度指定可・風量指定不可のため、温度 UI はそのまま使える） |
| FR-11d | Remo 本体が `online: false` の場合、その旨をバッジ表示する |
| FR-11e | ライトの 3 ボタンは**現在の状態を反映しない**（2 台の状態が食い違いうるため、トグルではなく「押すとその状態にする」片方向ボタンとする）。したがって**どのボタンも強調表示しない** — 強調すると「今それが選ばれている」と誤読される |
| FR-11f | **vibrant レンダリング対策**（実機で判明）: デスクトップに置いたウィジェットは色が輝度に変換される。濃い色で塗ると白い塊になり、その上の白文字は消える。よって<br>・前景色に白や黒を明示せず `.primary` に委ねる<br>・選択状態は**同系色の濃さの差 + 縁取り**で表し、色相では表さない |
| FR-11g | 全ボタンにカスタム ButtonStyle で**押下フィードバック**（縮み + 明滅）を付ける。OS 既定のハイライトは vibrant で白飽和するため使わない。`.invalidatableContent()` は更新中に全ボタンへ一括で効いてしまうので、押下フィードバックには使わない |
| FR-12 | 未設定時（トークン未入力・機器未選択）は「設定を開く」導線を表示する |

### 6.3 操作（AppIntent）

| ID | 要件 |
|----|------|
#### エアコン

| ID | 要件 |
|----|------|
| FR-13 | 電源: 停止は `button=power-off`。ON は各モードボタンが兼ねる（モードを押せば運転開始） |
| FR-14 | 温度 − +: `aircon.range.modes[現在モード].temp` のリスト上を **1℃ 単位で移動**する（実機は 0.5℃ 刻みなので 2 要素分。0.5 刻みでは押下回数が倍になり実用的でないため）。リストの端では押下を無効化する。**リスト外の値を組み立てて送らない** |
| FR-15 | モード切替: `operation_mode` を `cool` / `warm` / `dry` のいずれかで送信。切替先の温度リストに現在温度が無い場合（例: 暖房 16.0℃ → 冷房は 18.0℃ 始まり）、**そのリスト内で最も近い値**へ丸めて送る |
| FR-16 | **風量・風向は固定値を毎回同送する**: 冷房・暖房は `air_volume=4`（最大）＋ `air_direction=swing`。除湿は風量指定不可のため `air_direction=swing` のみ。値は `range` から読み、リストに無ければ送信しない |
| FR-17 | ライト（**2 台同時**、片方向の 3 ボタン）:<br>・**全灯** → 2 台に `button=on-100`<br>・**豆電球** → 2 台に `button=night`<br>・**消灯** → 2 台に `button=off`<br>1 ボタン押下で 2 リクエストを**並行**送信する。片方が失敗した場合はその機器名を添えてエラー表示する |
| FR-18 | **楽観的更新**: ボタン押下時、API 応答を待たずに表示を先に変える。応答が返ったら正とし、失敗したら元に戻してエラー表示する。<br>⚠️ このとき**キャッシュの取得時刻も進める**こと。進めないと直後の再描画が TTL 切れと判定され、`/appliances` と `/devices` を叩き直して数秒のラグになる（実機で確認） |
| FR-19 | 操作の API 応答に含まれる更新後設定を SharedCache に書き戻し、追加の GET を発生させない。応答が楽観的に描いた値と一致する場合は**再描画を送らない**（ちらつき防止） |
| FR-19b | 全 AppIntent に `openAppWhenRun = false` を**明示**する。省略すると押すたびに設定ウィンドウが前面に出てくる（実機で確認） |

### 6.4 エラー処理

| ID | 要件 |
|----|------|
| FR-20 | `401`: 「トークンが無効です」と表示し、コンテナアプリの設定画面へ誘導する |
| FR-21 | `429` / `X-Rate-Limit-Remaining` 枯渇: 「制限中（あと N 秒）」と表示し、リセット時刻まで**新規リクエストを送らない**（操作ボタンも無効化） |
| FR-22 | ネットワーク不通・タイムアウト: 直前のキャッシュ値を「オフライン」バッジ付きで表示し続ける。空表示にはしない |
| FR-23 | すべてのエラーで、**アクセストークンをログ・エラーメッセージに含めない** |

---

## 7. 非機能要件（NFR）

| ID | 要件 | 検証方法 |
|----|------|---------|
| NFR-1 | **応答性**: ボタン押下から表示変化まで体感即時（楽観的更新により 100ms 以内） | 実機で目視 |
| NFR-2 | **レート制限順守**（上限 30 req / 5 分）: 定常状態で 5 分あたり 10 リクエストを超えない。内訳は表示更新 2（`/appliances` + `/devices`）＋ 操作。**ライトの 3 ボタンは 1 押下あたり 2 リクエストを消費する**点に注意 | `x-rate-limit-remaining` を記録して 1 時間観測 |
| NFR-3 | **キャッシュ共有**: ウィジェットを複数配置しても API 呼び出しが増えない。TTL（既定 300 秒）内は SharedCache を再利用 | ウィジェット 3 個配置してリクエスト数を計測 |
| NFR-4 | **秘匿情報**: トークンは Keychain のみ。Git 管理下に平文で入らない | コミット前に全ファイルを grep でスキャン |
| NFR-5 | **サンドボックス**: `network.client` 以外の権限を要求しない | entitlements を確認 |
| NFR-6 | **対応 OS**: macOS 14 以降（インタラクティブウィジェット必須）。開発は macOS 26.2 | — |
| NFR-7 | **AppIntent の実行時間**: ウィジェット拡張のインテントは短時間で終える必要があるため、API タイムアウトを **5 秒** に設定する | タイムアウト時の挙動を意図的に再現して確認 |
| NFR-8 | **ライセンス**: MIT。個人情報（絶対パス・メール・ユーザー名）をリポジトリに残さない | 公開判断時にスキャン |

---

## 8. データモデル（概略）

```swift
struct AirconState {           // ウィジェットが描画する唯一の真実
    var isOn: Bool             // settings.button != "power-off"
    var mode: String           // cool / warm / dry / blow / auto
    var temperature: String    // 文字列のまま扱う（"26" / "26.5" 両対応）
    var airVolume: String      // auto / 1...10
    var availableTemps: [String]   // range.modes[mode].temp
    var availableVolumes: [String]
    var updatedAt: Date
}

struct SensorReading { var temperature: Double?; var humidity: Double?; var measuredAt: Date }

struct Snapshot {              // App Group に保存する共有キャッシュ
    var aircon: AirconState?
    var lights: [LightState]
    var sensor: SensorReading?
    var fetchedAt: Date
    var rateLimit: RateLimitInfo?
}
```

温度を `Double` でなく `String` で保持するのは、API が返す表現（`"26"` / `"26.5"`）と送信値を一致させ、0.5℃ 刻み機種で丸め誤差による不一致を起こさないため。

---

## 9. リスクと対策

| # | リスク | 影響 | 対策 |
|---|--------|------|------|
| R-1 | ~~Xcode 未インストール~~ | — | **解消済み**（26.5 導入確認。`xcode-select` の切替のみ残） |
| R-2 | **ウィジェットの更新頻度は OS が決める**。5 分ごとの更新を要求しても保証されない | 室温が古いまま見える | FR-10 で取得時刻を必ず併記。ユーザー操作時は必ず最新化する |
| R-3 | API の設定値は **Remo が記憶している送信値**であり、エアコン実機の実状態ではない | リモコン直操作後にズレる | 仕様として受け入れ、README に明記。ズレたら一度ウィジェットから操作すれば同期される |
| R-4 | ~~ライトの状態が返らない~~ | — | **解消済み**（M0 で 2 台とも `light.state` を返すことを確認） |
| R-8 | **Remo mini に湿度センサーが無い** | 当初要件の湿度表示が不可 | v1 は室温のみ（D-3 変更済み）。FR-9b で将来対応 |
| R-9 | `auto` モードの温度が相対値のため、他モードと同じ UI で扱うと誤解を招く | 「-2℃」と誤読 | FR-11c で表示を分ける |
| R-5 | App Group / Keychain Access Group は **Team ID 前提**。署名設定を誤ると拡張がトークンを読めない | ウィジェットが常に未設定表示 | 最初のマイルストーンで「拡張から Keychain 読み出し成功」を単独で検証する |
| R-6 | レート制限をデバッグ中に使い切る | 開発が止まる | 開発用のモック API クライアントを最初に用意し、UI 開発は実 API を叩かずに行う |
| R-7 | トークンの有効期限・失効 | 突然使えなくなる | FR-20 で明示的に検知・誘導 |

---

## 10. Plan B（Xcode を入れない場合）

`~/tmp` の既定方針（Swift 単一ファイル + `build.sh` + ad-hoc 署名）を維持したい場合の選択肢：

| 案 | 実現性 | 評価 |
|----|--------|------|
| B-1: `swiftc` で `.appex` を手組み | 理論上は可能（バイナリ + Info.plist の `NSExtension` + `codesign`）だが、WidgetKit 拡張の手組みは前例が乏しく、失敗時の切り分けコストが極めて高い | **非推奨** |
| B-2: メニューバー常駐アプリに変更 | 単一ファイルで完結。ただし「常時見える」という D-1 の核を失う | 要件の後退 |
| B-3: Xcode を入れて WidgetKit（本命） | 素直。15GB のディスクと初回ビルド環境構築のみがコスト | **推奨** |

---

## 11. マイルストーン

| M | 内容 | 完了条件 |
|---|------|---------|
| ~~**M0**~~ | 環境準備 | ✅ **完了**（2026-08-07）。Xcode 26.5 / トークン Keychain 保存 / 実データ取得 → [DEVICE-PROFILE.md](DEVICE-PROFILE.md) |
| **M1** | RemoKit + コンテナアプリ | 設定画面でトークンを保存し、接続テストが通り、機器を選択できる（FR-1〜FR-6） |
| **M2** | 表示のみのウィジェット | 拡張が Keychain と App Group を読めることを実証（R-5 の解消）。室温・湿度・エアコン設定を Medium に表示（FR-7〜FR-12） |
| ~~**M1**~~ | RemoKit + コンテナアプリ | ✅ **完了**（2026-08-07）。トークン保存・接続テスト・機器選択が動作 |
| ~~**M2**~~ | 表示のみのウィジェット | ✅ **完了**。拡張から Keychain / App Group を読めることを実証（R-5 解消） |
| ~~**M3**~~ | 操作の実装 | ✅ **完了**。停止・モード 3 種・温度 −+・ライト 3 ボタンが実機で動作 |
| **M3.5** | UI の作り込み | ✅ 概ね完了。vibrant 対策・英語ラベル・押下エフェクト・ラグ解消（FR-11f, FR-11g, FR-18, FR-19b）。デザイン検討は [mock/large.html](mock/large.html) |
| **M4** | 堅牢化 | Small / Medium の実機確認、エラー処理一式、レート制限の実測（FR-20〜FR-23, NFR-2） |
| **M5** | 仕上げ | README / portfolio.md、個人情報スキャン、ローカルインストール |

---

## 12. 未決事項

| # | 論点 | 決める時期 |
|---|------|-----------|
| ~~Q-1~~ | ~~Xcode を導入するか~~ | **決着**: B-3（Xcode + WidgetKit）を採用 |
| Q-2 | Bundle ID の名前空間（`com.shironoir.remowidget` で良いか） | M1 |
| Q-3 | 将来 GitHub 公開して `~/Production/app/` へ移すか | M5 |
| ~~Q-4~~ | ~~ライトの明るさ ± を v1 に含めるか~~ | **決着**: 含めない。全灯 / 豆電球 / 消灯の 3 ボタンのみ（D-2b） |
| Q-5 | 除湿時の風向も `swing` 固定でよいか（明示指定が無かったため暫定で swing にしている） | M3 の実機確認時 |

---

## 参考

- [Mac から Nature Remo を操作する（note / motolyo）](https://note.com/motolyo/n/n02724d6d7d40) — 起点資料
- [Nature Remo Cloud API でより快適なスマートホームライフを（メンバーズエッジ）](https://www.membersedge.co.jp/blog/nature-remo-cloud-api/)
- [nature-remo/nature-remo（JS クライアント）](https://github.com/nature-remo/nature-remo) — レスポンス構造の参照実装
- [natureremo（Go クライアント）](https://pkg.go.dev/github.com/tenntenn/natureremo) — 型定義の参照

import AppIntents
import WidgetKit

// ウィジェットのボタンから呼ばれる操作（FR-13〜FR-19）。
// perform() はウィジェット拡張プロセス内で短時間しか動けないため、
// API のタイムアウトは 5 秒に切ってある（NFR-7）。

/// 楽観的更新（FR-18）の共通処理。
/// API 応答を待たずに共有スナップショットを書き換えて再描画し、
/// 応答が返ったら確定値で上書きする。失敗したら元に戻す。
enum IntentRunner {

    static func runAircon(optimistic: (inout AirconSettings) -> Void,
                          parameters: [String: String]) async {
        guard let state = SharedStore.loadSnapshot()?.aircon else { return }

        let original = state.settings
        var optimisticSettings = original
        optimistic(&optimisticSettings)

        // ① 応答を待たずに新しい値を書き、先に再描画させる（FR-18）。
        //    confirmed: true にしてキャッシュを新鮮扱いにすることで、
        //    この reload が API を叩き直さず即座に返るようにする。
        SharedStore.update(airconSettings: optimisticSettings, confirmed: true)
        WidgetCenter.shared.reloadAllTimelines()

        // ② 実際の送信。ここで待つのは避けられないが、表示はもう変わっている。
        do {
            let client = try NatureAPIClient.fromKeychain()
            let (confirmed, rate) = try await client.sendAircon(applianceId: state.applianceId,
                                                                parameters: parameters)
            SharedStore.update(airconSettings: confirmed, confirmed: true)
            SharedStore.update(rateLimit: rate)

            // 楽観的に描いた値と実際が一致していれば再描画は不要。
            // 余計な reload はちらつきの原因になるので送らない。
            guard confirmed != optimisticSettings else { return }
        } catch {
            SharedStore.update(airconSettings: original, confirmed: true)   // ロールバック
            SharedStore.update(error: (error as? LocalizedError)?.errorDescription ?? "操作に失敗しました")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - エアコン

struct SetAirconModeIntent: AppIntent {
    static let title: LocalizedStringResource = "エアコンのモードを変更"
    /// ウィジェット拡張内で完結させる。true だと押すたびに設定ウィンドウが開いてしまう。
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "モード")
    var mode: String

    init() {}
    init(mode: AirconLogic.Mode) { self.mode = mode.rawValue }

    func perform() async throws -> some IntentResult {
        guard let target = AirconLogic.Mode(rawValue: mode),
              let state = SharedStore.loadSnapshot()?.aircon else { return .result() }

        let parameters = AirconLogic.parameters(switchingTo: target, from: state)
        await IntentRunner.runAircon(optimistic: { settings in
            settings.mode = target.rawValue
            settings.button = ""                          // モード押下は運転開始を兼ねる
            if let temp = parameters["temperature"] { settings.temp = temp }
            if let vol = parameters["air_volume"] { settings.vol = vol }
            if let dir = parameters["air_direction"] { settings.dir = dir }
        }, parameters: parameters)

        return .result()
    }
}

struct StepTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "エアコンの温度を変更"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    /// +1 / -1（℃）。実機は 0.5 刻みだがリスト上を 1℃ 分移動する（FR-14）。
    @Parameter(title: "変化量")
    var degrees: Int

    init() {}
    init(degrees: Int) { self.degrees = degrees }

    func perform() async throws -> some IntentResult {
        guard let state = SharedStore.loadSnapshot()?.aircon,
              let parameters = AirconLogic.parameters(steppingBy: degrees, from: state)
        else { return .result() }

        await IntentRunner.runAircon(optimistic: { settings in
            if let temp = parameters["temperature"] { settings.temp = temp }
        }, parameters: parameters)

        return .result()
    }
}

struct PowerOffAirconIntent: AppIntent {
    static let title: LocalizedStringResource = "エアコンを停止"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await IntentRunner.runAircon(optimistic: { settings in
            settings.button = "power-off"
        }, parameters: AirconLogic.powerOffParameters)
        return .result()
    }
}

// MARK: - ライト（2 台同時・片方向の 3 ボタン / FR-17）

struct LightSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "照明を操作"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    /// on-100（全灯）/ night（豆電球）/ off（消灯）
    @Parameter(title: "ボタン")
    var button: String

    init() {}
    init(scene: LightScene) { self.button = scene.button }

    func perform() async throws -> some IntentResult {
        let ids = SharedStore.loadConfiguration().lightIds
        guard !ids.isEmpty else { return .result() }

        let scene = LightScene.allCases.first { $0.button == button }
        let previous = SharedStore.loadSnapshot()?.lightScene

        // エアコンと同じく、応答を待たずに選択状態を先に動かす（FR-18）
        SharedStore.update(lightScene: scene, confirmed: true)
        WidgetCenter.shared.reloadAllTimelines()

        do {
            let client = try NatureAPIClient.fromKeychain()
            let rate = try await client.sendLight(applianceIds: ids, button: button)
            SharedStore.update(rateLimit: rate)
            SharedStore.update(error: nil)
            // 表示はもう更新済みなので再描画しない＝ちらつきと余計な取得を避ける
        } catch {
            SharedStore.update(lightScene: previous, confirmed: true)   // ロールバック
            SharedStore.update(error: (error as? LocalizedError)?.errorDescription ?? "照明の操作に失敗しました")
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}

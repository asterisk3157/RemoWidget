import Foundation

/// エアコンの温度・モード・風量に関する純粋なロジック。
/// ネットワークに触れないので単体テストできる。
///
/// 実機の range（DEVICE-PROFILE.md）:
///   cool 18〜30 / warm 16〜30 / dry 18〜30 いずれも 0.5 刻み
///   vol  1,2,3,4,auto（dry は指定不可）
public enum AirconLogic {

    /// ウィジェットで扱うモード。auto / blow は D-2 により対象外。
    public enum Mode: String, CaseIterable, Sendable {
        case cool, warm, dry

        public var label: String {
            switch self {
            case .cool: return "冷房"
            case .warm: return "暖房"
            case .dry:  return "除湿"
            }
        }

        /// ウィジェット上の表記。狭い領域で日本語より読み取りやすいため英語を使う。
        public var englishLabel: String {
            switch self {
            case .cool: return "Cool"
            case .warm: return "Heat"
            case .dry:  return "Dry"
            }
        }

        public var symbolName: String {
            switch self {
            case .cool: return "snowflake"
            case .warm: return "sun.max"
            case .dry:  return "drop"
            }
        }
    }

    // MARK: - 温度

    /// 温度リストの刻み幅（℃）。要素が 1 つ以下なら nil。
    static func stepSize(of list: [String]) -> Double? {
        let values = list.compactMap(Double.init).sorted()
        guard values.count >= 2 else { return nil }
        return values[1] - values[0]
    }

    /// 1℃ 動かすのに必要なリスト上の要素数。
    /// 0.5 刻みなら 2、1.0 刻みなら 1。FR-14 が「押下回数を倍にしない」ための計算。
    public static func indexStride(for list: [String]) -> Int {
        guard let step = stepSize(of: list), step > 0 else { return 1 }
        return max(1, Int((1.0 / step).rounded()))
    }

    /// 現在温度から `degrees` ℃ 分ずらした、**リスト内に実在する値**を返す。
    /// 端を超える場合は nil（呼び出し側はボタンを無効化する）。
    /// リストに無い値を組み立てて送らないための関数（FR-14）。
    public static func steppedTemperature(from current: String,
                                          in list: [String],
                                          degrees: Int) -> String? {
        let values = list.filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }

        let stride = indexStride(for: values)
        // 現在値がリストに無い場合（モード切替直後など）は最も近い値を起点にする。
        guard let currentIndex = values.firstIndex(of: current)
                ?? nearestTemperature(to: current, in: values).flatMap({ values.firstIndex(of: $0) })
        else { return nil }

        let target = currentIndex + stride * degrees
        guard values.indices.contains(target) else { return nil }
        return values[target]
    }

    /// リスト内で `target` に最も近い値。FR-15 のモード切替フォールバック用。
    /// 例: 暖房 16.0℃ → 冷房（18.0 始まり）では "18" を返す。
    public static func nearestTemperature(to target: String, in list: [String]) -> String? {
        let values = list.filter { !$0.isEmpty }
        guard let t = Double(target) else { return values.first }
        return values.min { a, b in
            guard let da = Double(a), let db = Double(b) else { return false }
            return abs(da - t) < abs(db - t)
        }
    }

    // MARK: - 風量・風向（FR-16: UI を持たず固定値を毎回同送する）

    /// そのモードで送るべき風量。最大値を選ぶ。
    /// "auto" は数値でないため最大値の候補から除く。dry のように指定不可なら nil。
    public static func fixedVolume(for range: ModeRange) -> String? {
        guard range.supportsVolume else { return nil }
        let numeric = range.vol.compactMap { Int($0) }
        guard let maxValue = numeric.max() else { return nil }
        return String(maxValue)
    }

    /// 風向は swing 固定。range に swing が無ければ送らない。
    public static func fixedDirection(for range: ModeRange) -> String? {
        guard let dir = range.dir else { return nil }
        return dir.contains("swing") ? "swing" : nil
    }

    // MARK: - リクエスト組み立て

    /// モードボタン押下時に送るパラメータ一式。
    /// モード切替と同時に温度の丸め・風量・風向の固定値を載せる。
    public static func parameters(switchingTo mode: Mode,
                                  from state: AirconState) -> [String: String] {
        var params = ["operation_mode": mode.rawValue]
        guard let range = state.modes[mode.rawValue] else { return params }

        if range.supportsTemperature {
            let temps = range.temperatures
            // 切替先に現在温度が無ければ最も近い値へ丸める（FR-15）
            let temp = temps.contains(state.settings.temp)
                ? state.settings.temp
                : nearestTemperature(to: state.settings.temp, in: temps)
            if let temp { params["temperature"] = temp }
        }
        if let vol = fixedVolume(for: range) { params["air_volume"] = vol }
        if let dir = fixedDirection(for: range) { params["air_direction"] = dir }
        return params
    }

    /// 温度 − + 押下時に送るパラメータ。押せない場合は nil。
    public static func parameters(steppingBy degrees: Int,
                                  from state: AirconState) -> [String: String]? {
        guard let range = state.currentRange, range.supportsTemperature else { return nil }
        guard let next = steppedTemperature(from: state.settings.temp,
                                            in: range.temperatures,
                                            degrees: degrees) else { return nil }
        var params = ["temperature": next]
        // 温度だけ送ると機種によって風量が既定へ戻ることがあるため固定値を同送する
        if let vol = fixedVolume(for: range) { params["air_volume"] = vol }
        if let dir = fixedDirection(for: range) { params["air_direction"] = dir }
        return params
    }

    /// 停止（FR-13）。
    public static var powerOffParameters: [String: String] { ["button": "power-off"] }

    // MARK: - 表示

    /// 温度の表示文字列。auto モードの相対値（-2〜+2）には符号を付ける。
    /// ※ auto は D-2 で対象外だが、リモコン等で auto にされた状態を
    ///    ウィジェットが受け取ることはあるため表示だけは正しく扱う。
    public static func displayTemperature(_ settings: AirconSettings) -> String {
        guard !settings.temp.isEmpty else { return "—" }
        if settings.mode == "auto" {
            guard let v = Double(settings.temp) else { return settings.temp }
            return v > 0 ? "+\(settings.temp)" : settings.temp
        }
        return "\(settings.temp)℃"
    }
}

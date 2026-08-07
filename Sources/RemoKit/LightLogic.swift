import Foundation

/// ウィジェットに並ぶ 3 つの照明ボタン（FR-17）。
/// 2 台を常に同時操作するため、機器ごとの区別は持たない。
public enum LightScene: String, CaseIterable, Codable, Sendable {
    case all, night, off

    /// Nature API に送る button 名。
    public var button: String {
        switch self {
        case .all:   return "on-100"
        case .night: return "night"
        case .off:   return "off"
        }
    }

    public var label: String {
        switch self {
        case .all:   return "全灯"
        case .night: return "豆電球"
        case .off:   return "消灯"
        }
    }

    /// ウィジェット上の表記（エアコンのモードと揃えて英語）。
    public var englishLabel: String {
        switch self {
        case .all:   return "Bright"
        case .night: return "Night"
        case .off:   return "Off"
        }
    }

    public var symbolName: String {
        // 全灯は塗りつぶし、豆電球は月（常夜灯）で、一目で区別できるようにする
        switch self {
        case .all:   return "lightbulb.max.fill"
        case .night: return "moon.fill"
        case .off:   return "lightbulb.slash"
        }
    }

    /// 1 台分の `light.state` から現在のシーンを推定する。
    ///
    /// `last_button` にはウィジェット以外（Nature アプリ・物理リモコン）で押された値も入る。
    /// 実機では素の `"on"` が観測されており、これは全灯扱いにする。
    /// 判断できない値のときは nil を返し、UI では「どれも選ばれていない」と表示する。
    public static func scene(from state: LightState?) -> LightScene? {
        guard let state else { return nil }
        if state.power == "off" { return .off }
        switch state.lastButton {
        case "off":            return .off
        case "night":          return .night
        case "on-100", "on":   return .all
        default:               return nil
        }
    }

    /// 複数台の状態をまとめる。
    /// **全台が同じシーンのときだけ**そのシーンを返す。
    /// 食い違っている場合に片方だけ強調すると誤解を招くため nil にする。
    public static func commonScene(from states: [LightState?]) -> LightScene? {
        let scenes = states.map(scene(from:))
        guard let first = scenes.first, scenes.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

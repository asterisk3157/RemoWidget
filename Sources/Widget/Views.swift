import SwiftUI
import WidgetKit

// FR-7〜FR-11e。デザインは mock/large.html に準拠。
// - 絵文字は使わず SF Symbols のみ
// - モードは英語ラベルを併記
// - 選択中は単一のアクセント色で塗り、前景色を明示してホバー時の白飽和で消えないようにする

struct RemoWidgetView: View {
    let entry: RemoEntry

    var body: some View {
        Group {
            if SharedStore.loadConfiguration().isComplete == false {
                UnconfiguredView()
            } else {
                LargeView(entry: entry)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 共通の見た目

private enum Style {
    static let corner: CGFloat = 12

    /// ⚠️ デスクトップに置いたウィジェットは vibrant レンダリングになり、
    /// 色は「輝度」に変換される。accentColor のような濃い色で塗ると白い塊になり、
    /// その上の白文字も白に潰れて消える（実機で確認）。
    /// そのため選択状態は **同系色の濃さの差** だけで表し、
    /// 前景は常に .primary（材質に応じて OS が読める色にしてくれる）にする。
    static let fill = Color.primary.opacity(0.12)
    /// 選択中は差を大きく取る。0.32 では明るい壁紙の上で差が潰れて見えなかった。
    static let fillSelected = Color.primary.opacity(0.48)
}

/// タイルの強調度。
private enum Emphasis {
    case normal
    case selected   // 現在のモード / 全灯のように強く見せたいボタン
}

/// 押した瞬間のフィードバック。
/// `.plain` だと押下時に何も起きず「効いたのか」が分からないため、
/// 縮み + 明滅を自前で当てる。OS 既定のハイライト（vibrant で白飽和する）も
/// カスタム ButtonStyle にすることで避けられる。
private struct TileButtonStyle: ButtonStyle {
    // ⚠️ 型名は ButtonStyleConfiguration と明示する。
    // 単に Configuration と書くと RemoKit の設定モデル（Configuration）に解決されてしまう。
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// ウィジェットのボタン共通の見た目。
/// カスタム ButtonStyle にして OS 既定のハイライトに前景色を奪われないようにする。
///
/// ⚠️ `.invalidatableContent()` はここには付けない。
/// 付けると更新中の演出が全ボタンに走り、温度以外まで一緒に光ってしまう。
private struct TileLabel: View {
    let symbol: String
    var title: String? = nil
    var emphasis: Emphasis = .normal
    var height: CGFloat = 52

    private var background: Color {
        emphasis == .selected ? Style.fillSelected : Style.fill
    }

    private var isSelected: Bool { emphasis == .selected }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: isSelected ? .bold : .medium))
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: isSelected ? .bold : .semibold))
                    .kerning(0.5)
            }
            // 色の差は壁紙次第で潰れるので、選択中は「形」でも示す。
            // vibrant でも図形は輪郭が残るため、これが一番確実に伝わる。
            Capsule()
                .fill(Color.primary)
                .frame(width: isSelected ? 16 : 0, height: 2.5)
                .opacity(isSelected ? 1 : 0)
                .padding(.top, 1)
        }
        // 白を明示しない（vibrant で背景ごと白に潰れて消えるため）。
        // ライトもエアコンと同じ扱いに揃える。
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: Style.corner, style: .continuous)
                .fill(background)
                .overlay(
                    // 縁取りも強めに足して、濃さの差が出にくい材質でも分かるようにする
                    RoundedRectangle(cornerRadius: Style.corner, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0),
                                      lineWidth: 2)
                )
        )
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

// MARK: - 未設定（FR-12）

private struct UnconfiguredView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gearshape").font(.title2)
            Text("設定が必要です").font(.headline)
            Text("RemoWidget を開いてトークンと機器を設定してください")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}

// MARK: - Large（FR-9 / mock の案A）

private struct LargeView: View {
    let entry: RemoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoomTemperature(sensor: entry.snapshot.sensor)
                Spacer()
                if let aircon = entry.snapshot.aircon {
                    StatusBadge(state: aircon, sensor: entry.snapshot.sensor)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.bottom, 14)

            if let aircon = entry.snapshot.aircon {
                BigTemperature(state: aircon)
                    .padding(.bottom, 16)

                SectionLabel(text: "Air conditioner").padding(.bottom, 6)
                ModeRow(state: aircon, height: 54, showLabels: true)
                    .padding(.bottom, 14)
            }

            SectionLabel(text: "Light").padding(.bottom, 6)
            LightRow(selected: entry.snapshot.lightScene, height: 54, showLabels: true)

            LastUpdate(snapshot: entry.snapshot)
        }
    }
}

// MARK: - 部品

private struct RoomTemperature: View {
    let sensor: SensorReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let temperature = sensor?.temperature {
                    Text(String(format: "%.1f", temperature))
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                    Text("℃")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: 30, weight: .medium))
                }
                // 存在する項目だけ描画（FR-9b）。Remo mini は湿度を返さない。
                if let humidity = sensor?.humidity {
                    Text(String(format: "%.0f%%", humidity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            SectionLabel(text: "Room")
        }
    }
}

/// 右上のバッジ。運転中はモード名、停止中は OFF、オフラインは OFFLINE。
private struct StatusBadge: View {
    let state: AirconState
    let sensor: SensorReading?

    var body: some View {
        HStack(spacing: 4) {
            if sensor?.isOnline == false {                       // FR-11d
                Image(systemName: "wifi.slash")
                Text("OFFLINE")
            } else if state.settings.isOn,
                      let mode = AirconLogic.Mode(rawValue: state.settings.mode) {
                Image(systemName: mode.symbolName)
                Text(mode.englishLabel.uppercased())
            } else {
                Text("OFF")
            }
        }
        .foregroundStyle(sensor?.isOnline == false ? Color.orange
                         : (state.settings.isOn ? Color.primary : Color.secondary))
    }
}

/// Large 用の大きな温度 − ＋（mock 案A）。
private struct BigTemperature: View {
    let state: AirconState

    private func canStep(_ degrees: Int) -> Bool {
        AirconLogic.parameters(steppingBy: degrees, from: state) != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            StepButton(symbol: "minus", degrees: -1, enabled: canStep(-1))

            Text(AirconLogic.displayTemperature(state.settings))
                .font(.system(size: 40, weight: .light))
                .monospacedDigit()
                // 数字が転がるように切り替わる（楽観的更新が即座に見える）
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.25), value: state.settings.temp)
                .frame(minWidth: 110)
                .opacity(state.settings.isOn ? 1 : 0.45)      // FR-11
                .invalidatableContent()

            StepButton(symbol: "plus", degrees: 1, enabled: canStep(1))
            Spacer()
        }
    }
}

private struct StepButton: View {
    let symbol: String
    let degrees: Int
    let enabled: Bool

    var body: some View {
        Button(intent: StepTemperatureIntent(degrees: degrees)) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 50, height: 50)
                .background(Style.fill, in: Circle())
        }
        .buttonStyle(TileButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

private struct ModeRow: View {
    let state: AirconState
    let height: CGFloat
    let showLabels: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AirconLogic.Mode.allCases, id: \.self) { mode in
                let isCurrent = state.settings.isOn && state.settings.mode == mode.rawValue
                Button(intent: SetAirconModeIntent(mode: mode)) {
                    TileLabel(symbol: mode.symbolName,
                              title: showLabels ? mode.englishLabel : nil,
                              emphasis: isCurrent ? .selected : .normal,
                              height: height)
                }
                .buttonStyle(TileButtonStyle())
                .disabled(state.modes[mode.rawValue] == nil)
            }

            Button(intent: PowerOffAirconIntent()) {
                TileLabel(symbol: "power",
                          title: showLabels ? "Off" : nil,
                          height: height)
            }
            .buttonStyle(TileButtonStyle())
            .disabled(!state.settings.isOn)
            .opacity(state.settings.isOn ? 1 : 0.4)
        }
        // 温度変化では動かず、モード切替のときだけ滑らかに変わる
        .animation(.snappy(duration: 0.22), value: state.settings.mode)
        .animation(.snappy(duration: 0.22), value: state.settings.button)
    }
}

/// 照明 3 ボタン（FR-17 / FR-11e）。
/// 2 台の状態が食い違いうるため、トグルではなく片方向ボタンにする。
private struct LightRow: View {
    /// 全台が同じシーンのときだけ値が入る。食い違い時は nil でどれも強調しない。
    let selected: LightScene?
    let height: CGFloat
    let showLabels: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LightScene.allCases, id: \.self) { scene in
                Button(intent: LightSceneIntent(scene: scene)) {
                    TileLabel(symbol: scene.symbolName,
                              title: showLabels ? scene.englishLabel : nil,
                              emphasis: scene == selected ? .selected : .normal,
                              height: height)
                }
                .buttonStyle(TileButtonStyle())
            }
        }
        .animation(.snappy(duration: 0.22), value: selected)
    }
}

/// 取得時刻（FR-10）。秒刻みの相対表示はやめ、時刻で示す。
private struct LastUpdate: View {
    let snapshot: Snapshot

    private var timeText: String {
        guard let date = snapshot.sensor?.measuredAt ?? Optional(snapshot.fetchedAt),
              date != .distantPast else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let error = snapshot.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error).lineLimit(1)
            } else {
                Text("Last update \(timeText)")
            }
        }
        .font(.system(size: 9))
        .kerning(0.3)
        .foregroundStyle(snapshot.lastError == nil ? Color.secondary : Color.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

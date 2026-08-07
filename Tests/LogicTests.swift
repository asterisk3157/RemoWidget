import Foundation
// 実機 range（DEVICE-PROFILE.md）を使った AirconLogic の検証
let coolTemps = stride(from: 18.0, through: 30.0, by: 0.5).map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
let warmTemps = stride(from: 16.0, through: 30.0, by: 0.5).map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
let cool = ModeRange(temp: coolTemps, vol: ["1","2","3","4","auto"], dir: ["auto","swing"], dirh: ["auto","swing"])
let warm = ModeRange(temp: warmTemps, vol: ["1","2","3","4","auto"], dir: ["auto","swing"], dirh: ["auto","swing"])
let dry  = ModeRange(temp: coolTemps, vol: [""], dir: ["auto","swing"], dirh: ["auto","swing"])
let modes = ["cool": cool, "warm": warm, "dry": dry]

var pass = 0, fail = 0
func check(_ label: String, _ actual: String?, _ expected: String?) {
    if actual == expected { pass += 1; print("  ok   \(label) => \(actual ?? "nil")") }
    else { fail += 1; print("  FAIL \(label) => \(actual ?? "nil") (期待 \(expected ?? "nil"))") }
}

print("[1℃ステップ = 0.5刻みリストを2要素移動]")
check("indexStride(cool)", String(AirconLogic.indexStride(for: coolTemps)), "2")
check("22 → +1", AirconLogic.steppedTemperature(from: "22", in: coolTemps, degrees: 1), "23")
check("22 → -1", AirconLogic.steppedTemperature(from: "22", in: coolTemps, degrees: -1), "21")
check("22.5 → +1", AirconLogic.steppedTemperature(from: "22.5", in: coolTemps, degrees: 1), "23.5")

print("[端では nil を返しボタンを無効化]")
check("30 → +1 (上端)", AirconLogic.steppedTemperature(from: "30", in: coolTemps, degrees: 1), nil)
check("18 → -1 (下端)", AirconLogic.steppedTemperature(from: "18", in: coolTemps, degrees: -1), nil)

print("[FR-15 モード切替の丸め]")
let warmState = AirconState(applianceId: "x",
    settings: AirconSettings(temp: "16", mode: "warm", vol: "4", dir: "swing", button: ""), modes: modes)
check("暖房16 → 冷房 (18始まり)", AirconLogic.parameters(switchingTo: .cool, from: warmState)["temperature"], "18")
let coolState = AirconState(applianceId: "x",
    settings: AirconSettings(temp: "26", mode: "cool", vol: "4", dir: "swing", button: ""), modes: modes)
check("冷房26 → 暖房 (範囲内は維持)", AirconLogic.parameters(switchingTo: .warm, from: coolState)["temperature"], "26")

print("[FR-16 風量・風向の固定値]")
check("冷房の風量 (最大, autoは除外)", AirconLogic.fixedVolume(for: cool), "4")
check("除湿の風量 (指定不可)", AirconLogic.fixedVolume(for: dry), nil)
check("風向", AirconLogic.fixedDirection(for: cool), "swing")
let dryParams = AirconLogic.parameters(switchingTo: .dry, from: coolState)
check("除湿は air_volume を送らない", dryParams["air_volume"], nil)
check("除湿でも温度は送る", dryParams["temperature"], "26")
check("除湿でも風向は送る", dryParams["air_direction"], "swing")

print("[表示]")
check("通常モード", AirconLogic.displayTemperature(coolState.settings), "26℃")
check("autoの相対値", AirconLogic.displayTemperature(AirconSettings(temp: "1.5", mode: "auto", vol: "4", dir: "auto", button: "")), "+1.5")

// ── 照明シーンの判定（LightLogic）──────────────────────────
print("\n[照明シーンの判定]")
func light(_ power: String?, _ last: String?) -> LightState {
    LightState(brightness: nil, power: power, lastButton: last)
}
func checkScene(_ label: String, _ actual: LightScene?, _ expected: LightScene?) {
    if actual == expected { pass += 1; print("  ok   \(label) => \(actual?.rawValue ?? "nil")") }
    else { fail += 1; print("  FAIL \(label) => \(actual?.rawValue ?? "nil") (期待 \(expected?.rawValue ?? "nil"))") }
}

checkScene("power=off は消灯", LightScene.scene(from: light("off", "on")), .off)
checkScene("last_button=night", LightScene.scene(from: light("on", "night")), .night)
checkScene("last_button=on-100 は全灯", LightScene.scene(from: light("on", "on-100")), .all)
// リモコンやアプリで押された素の "on" も全灯扱い（実機で観測される値）
checkScene("last_button=on も全灯", LightScene.scene(from: light("on", "on")), .all)
checkScene("未知の値は判断しない", LightScene.scene(from: light("on", "favorite")), nil)
checkScene("state が無い", LightScene.scene(from: nil), nil)

print("[複数台のまとめ]")
checkScene("2台とも全灯", LightScene.commonScene(from: [light("on","on-100"), light("on","on")]), .all)
checkScene("2台とも消灯", LightScene.commonScene(from: [light("off","off"), light("off","off")]), .off)
// 食い違うときに片方だけ強調すると誤解を招くので、どれも選択しない
checkScene("食い違いは無選択", LightScene.commonScene(from: [light("on","on-100"), light("off","off")]), nil)
checkScene("片方が不明なら無選択", LightScene.commonScene(from: [light("on","on-100"), light("on","favorite")]), nil)

print("\n\(pass) passed, \(fail) failed")
if fail > 0 { exit(1) }

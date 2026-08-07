import SwiftUI
import WidgetKit

/// 設定画面（FR-1〜FR-6）。
/// ウィジェット拡張は UI を持てないため、トークン入力と機器選択はここで行い、
/// 結果を Keychain / App Group 経由で拡張へ渡す。
struct SettingsView: View {

    @State private var token: String = ""
    @State private var tokenSaved: Bool = TokenStore.exists
    @State private var appliances: [Appliance] = []
    @State private var config: Configuration = SharedStore.loadConfiguration()
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle
        case loading
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            tokenSection
            if tokenSaved {
                applianceSection
            }
            statusSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task { if tokenSaved && appliances.isEmpty { await testConnection() } }
    }

    // MARK: - トークン

    private var tokenSection: some View {
        Section("アクセストークン") {
            if tokenSaved {
                LabeledContent("状態") {
                    Label("保存済み", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                Button("トークンを削除", role: .destructive) {
                    try? TokenStore.delete()
                    tokenSaved = false
                    appliances = []
                    status = .idle
                }
            } else {
                SecureField("Bearer トークン", text: $token, prompt: Text("home.nature.global で発行"))
                Button("保存して接続テスト") {
                    Task { await saveToken() }
                }
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - 機器選択

    private var applianceSection: some View {
        Section("操作する機器") {
            Picker("エアコン", selection: Binding(
                get: { config.airconId ?? "" },
                set: { config.airconId = $0.isEmpty ? nil : $0; persist() }
            )) {
                Text("選択してください").tag("")
                ForEach(appliances.filter { $0.type == "AC" }, id: \.id) { appliance in
                    Text(appliance.nickname).tag(appliance.id)
                }
            }

            // ライトは 2 台同時操作のため、個別選択ではなく「含める / 含めない」（D-2b）
            let lights = appliances.filter { $0.type == "LIGHT" }
            if lights.isEmpty {
                Text("ライトが見つかりません").foregroundStyle(.secondary)
            } else {
                ForEach(lights, id: \.id) { light in
                    Toggle(light.nickname, isOn: Binding(
                        get: { config.lightIds.contains(light.id) },
                        set: { isOn in
                            if isOn {
                                if !config.lightIds.contains(light.id) { config.lightIds.append(light.id) }
                            } else {
                                config.lightIds.removeAll { $0 == light.id }
                            }
                            persist()
                        }
                    ))
                }
                Text("チェックした照明は 3 つのボタンで**同時に**操作されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("再読み込み") { Task { await testConnection() } }
        }
    }

    // MARK: - 状態表示

    @ViewBuilder
    private var statusSection: some View {
        switch status {
        case .idle:
            EmptyView()
        case .loading:
            Section { ProgressView().controlSize(.small) }
        case .success(let message):
            Section {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failure(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 処理

    private func saveToken() async {
        do {
            try TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
            token = ""
            tokenSaved = true
            await testConnection()
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    private func testConnection() async {
        status = .loading
        do {
            let result = try await SnapshotLoader.fetchAppliances()
            appliances = result
            let acCount = result.filter { $0.type == "AC" }.count
            let lightCount = result.filter { $0.type == "LIGHT" }.count
            status = .success("接続成功 — エアコン \(acCount) 台 / ライト \(lightCount) 台")
            applyDefaultsIfNeeded()
        } catch {
            // トークン自体はメッセージに載せない（FR-23）
            status = .failure(error.localizedDescription)
        }
    }

    /// 初回は素直に「エアコン 1 台目 + 全ライト」を既定選択にする。
    private func applyDefaultsIfNeeded() {
        var changed = false
        if config.airconId == nil, let ac = appliances.first(where: { $0.type == "AC" }) {
            config.airconId = ac.id
            changed = true
        }
        if config.lightIds.isEmpty {
            config.lightIds = appliances.filter { $0.type == "LIGHT" }.map(\.id)
            changed = !config.lightIds.isEmpty
        }
        if changed { persist() }
    }

    private func persist() {
        SharedStore.save(config)
        // 設定変更を即座にウィジェットへ反映（FR-6）
        WidgetCenter.shared.reloadAllTimelines()
    }
}

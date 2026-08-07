import Foundation

/// App Group / Keychain Access Group の識別子。
///
/// macOS では Team ID を前置する必要があるが、Team ID は環境ごとに異なるうえ
/// リポジトリに残したくないため、**ソースには直書きしない**。
/// Info.plist の `AppGroupIdentifier`（値は `$(TeamIdentifierPrefix)$(...)`）に
/// Xcode がビルド時に埋め込んだものを実行時に読む。
public enum AppGroup {
    public static let identifier: String = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !value.isEmpty else {
            // ここに来るのはビルド設定の不備。黙って別の場所に読み書きすると
            // 「設定したのにウィジェットが未設定のまま」という分かりにくい壊れ方をする。
            assertionFailure("Info.plist に AppGroupIdentifier がありません")
            return ""
        }
        return value
    }()
}

/// アプリ ↔ ウィジェット拡張で共有する状態の置き場（NFR-3）。
/// ウィジェットを複数配置しても API 呼び出しが増えないよう、
/// 取得結果をここにキャッシュし TTL 内は再利用する。
public enum SharedStore {

    /// スナップショットの有効期限。レート制限（30 req / 5 分）に合わせる。
    public static let ttl: TimeInterval = 300

    private static let snapshotKey = "snapshot"
    private static let configKey = "configuration"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    // MARK: - Snapshot

    public static func loadSnapshot() -> Snapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder.nature.decode(Snapshot.self, from: data)
    }

    public static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder.nature.encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    /// TTL 内なら再取得不要。
    public static func isFresh(_ snapshot: Snapshot?) -> Bool {
        guard let snapshot else { return false }
        return Date().timeIntervalSince(snapshot.fetchedAt) < ttl
    }

    /// 操作 API のレスポンスで得た最新設定を書き戻す（FR-19）。
    /// 追加の GET を発生させないための経路。
    ///
    /// - Parameter confirmed: API 応答で確定した値なら true。
    ///   このとき `fetchedAt` も進めてキャッシュを新鮮扱いにする。
    ///   そうしないと操作直後の再描画で TTL 切れと判定され、
    ///   `/appliances` と `/devices` を叩き直して数秒のラグになる。
    ///   センサーの鮮度は `sensor.measuredAt` で別に持っているので表示は狂わない。
    public static func update(airconSettings: AirconSettings, confirmed: Bool = false) {
        guard var snapshot = loadSnapshot(), var aircon = snapshot.aircon else { return }
        aircon.settings = airconSettings
        snapshot.aircon = aircon
        snapshot.lastError = nil
        if confirmed { snapshot.fetchedAt = Date() }
        save(snapshot)
    }

    /// 照明の選択シーンを書き戻す。`confirmed` の意味は上と同じ。
    public static func update(lightScene: LightScene?, confirmed: Bool = false) {
        var snapshot = loadSnapshot() ?? Snapshot()
        snapshot.lightScene = lightScene
        snapshot.lastError = nil
        if confirmed { snapshot.fetchedAt = Date() }
        save(snapshot)
    }

    public static func update(rateLimit: RateLimitInfo?) {
        guard var snapshot = loadSnapshot() else { return }
        snapshot.rateLimit = rateLimit
        save(snapshot)
    }

    public static func update(error: String?) {
        var snapshot = loadSnapshot() ?? Snapshot()
        snapshot.lastError = error
        save(snapshot)
    }

    // MARK: - Configuration

    public static func loadConfiguration() -> Configuration {
        guard let data = defaults?.data(forKey: configKey),
              let config = try? JSONDecoder.nature.decode(Configuration.self, from: data)
        else { return Configuration() }
        return config
    }

    public static func save(_ configuration: Configuration) {
        guard let data = try? JSONEncoder.nature.encode(configuration) else { return }
        defaults?.set(data, forKey: configKey)
    }
}

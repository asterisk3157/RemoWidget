import Foundation

/// API から表示用スナップショットを組み立てる。
/// アプリとウィジェット拡張の双方から使う唯一の取得経路。
public enum SnapshotLoader {

    /// TTL 内ならキャッシュを返し、API を叩かない（NFR-3）。
    /// - Parameter force: 操作直後など、必ず最新を取りたい場合に true。
    public static func load(force: Bool = false) async -> Snapshot {
        let cached = SharedStore.loadSnapshot()
        if !force, SharedStore.isFresh(cached), let cached { return cached }

        // 制限中は新規リクエストを送らない（FR-21）
        if let rate = cached?.rateLimit, rate.isExhausted {
            var snapshot = cached ?? Snapshot()
            snapshot.lastError = NatureAPIClient.APIError
                .rateLimited(resetAt: rate.resetAt).errorDescription
            return snapshot
        }

        let config = SharedStore.loadConfiguration()
        guard let client = try? NatureAPIClient.fromKeychain() else {
            var snapshot = cached ?? Snapshot()
            snapshot.lastError = TokenStore.StoreError.notFound.errorDescription
            return snapshot
        }

        var snapshot = cached ?? Snapshot()
        snapshot.lastError = nil

        do {
            let (appliances, rate1) = try await client.appliances()
            snapshot.rateLimit = rate1

            if let aircon = pickAircon(from: appliances, preferring: config.airconId) {
                snapshot.aircon = aircon
            }
            snapshot.lightScene = pickLightScene(from: appliances, ids: config.lightIds)

            let (devices, rate2) = try await client.devices()
            snapshot.rateLimit = rate2 ?? snapshot.rateLimit
            snapshot.sensor = pickSensor(from: devices, preferring: config.deviceId)

            snapshot.fetchedAt = Date()
            SharedStore.save(snapshot)
            return snapshot
        } catch {
            // 取得に失敗しても直前の値を保持し続ける（FR-22）
            snapshot.lastError = (error as? LocalizedError)?.errorDescription ?? "取得に失敗しました"
            SharedStore.save(snapshot)
            return snapshot
        }
    }

    static func pickAircon(from appliances: [Appliance], preferring id: String?) -> AirconState? {
        let candidates = appliances.filter { $0.type == "AC" }
        let target = candidates.first { $0.id == id } ?? candidates.first
        guard let target, let settings = target.settings, let aircon = target.aircon else { return nil }
        return AirconState(applianceId: target.id, settings: settings, modes: aircon.range.modes)
    }

    /// 対象の照明が全台とも同じシーンなら、そのシーンを返す（FR-11e 改）。
    static func pickLightScene(from appliances: [Appliance], ids: [String]) -> LightScene? {
        guard !ids.isEmpty else { return nil }
        let states = appliances
            .filter { ids.contains($0.id) }
            .map { $0.light?.state }
        guard states.count == ids.count else { return nil }   // 取得できない機器がある
        return LightScene.commonScene(from: states)
    }

    static func pickSensor(from devices: [Device], preferring id: String?) -> SensorReading? {
        let target = devices.first { $0.id == id } ?? devices.first
        guard let target else { return nil }
        let events = target.newestEvents ?? [:]
        // 存在する項目だけを拾う（FR-9b）。Remo mini は "te" のみ。
        return SensorReading(
            temperature: events["te"]?.val,
            humidity: events["hu"]?.val,
            illuminance: events["il"]?.val,
            measuredAt: events["te"]?.createdAt ?? events["hu"]?.createdAt,
            isOnline: target.online ?? true
        )
    }

    /// コンテナアプリの「接続テスト」用（FR-2）。機器一覧をそのまま返す。
    public static func fetchAppliances() async throws -> [Appliance] {
        let client = try NatureAPIClient.fromKeychain()
        let (appliances, rate) = try await client.appliances()
        SharedStore.update(rateLimit: rate)
        return appliances
    }
}

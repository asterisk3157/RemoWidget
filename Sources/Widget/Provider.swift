import WidgetKit
import SwiftUI

struct RemoEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot

    /// プレビュー・ギャラリー表示用のダミー。
    static var placeholder: RemoEntry {
        let range = ModeRange(temp: ["18", "18.5", "26", "26.5", "30"],
                              vol: ["1", "2", "3", "4", "auto"],
                              dir: ["auto", "swing"], dirh: nil)
        let settings = AirconSettings(temp: "26", mode: "cool", vol: "4",
                                      dir: "swing", button: "")
        return RemoEntry(date: Date(), snapshot: Snapshot(
            aircon: AirconState(applianceId: "-", settings: settings, modes: ["cool": range]),
            sensor: SensorReading(temperature: 24.1, measuredAt: Date()),
            fetchedAt: Date()
        ))
    }
}

struct RemoProvider: TimelineProvider {

    func placeholder(in context: Context) -> RemoEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (RemoEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            let snapshot = await SnapshotLoader.load()
            completion(RemoEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemoEntry>) -> Void) {
        Task {
            let snapshot = await SnapshotLoader.load()
            let entry = RemoEntry(date: Date(), snapshot: snapshot)

            // 次回更新の希望時刻。OS は保証しないため、表示側では
            // 取得時刻を併記して鮮度をユーザーに委ねる（FR-10 / R-2）。
            // 制限中はリセット時刻まで待つ（FR-21）。
            let nextRefresh: Date
            if let rate = snapshot.rateLimit, rate.isExhausted {
                nextRefresh = rate.resetAt
            } else {
                nextRefresh = Date().addingTimeInterval(SharedStore.ttl)
            }

            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

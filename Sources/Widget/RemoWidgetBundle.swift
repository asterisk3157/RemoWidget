import WidgetKit
import SwiftUI

@main
struct RemoWidgetBundle: WidgetBundle {
    var body: some Widget {
        RemoWidget()
    }
}

struct RemoWidget: Widget {
    let kind = "RemoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RemoProvider()) { entry in
            RemoWidgetView(entry: entry)
        }
        .configurationDisplayName("Remo")
        .description("エアコンと照明を操作します。")
        // Large のみ。Small / Medium では温度 −+ とモード 4 つ・照明 3 つが
        // 十分なタップ領域で収まらないため提供しない（2026-08-08 決定）。
        .supportedFamilies([.systemLarge])
    }
}

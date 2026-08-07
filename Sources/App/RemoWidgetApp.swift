import SwiftUI
import AppKit

@main
struct RemoWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("RemoWidget 設定", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

/// このアプリは「設定を書き込むためだけ」に起動する。
/// ウィジェット拡張は別プロセスで動くので、常駐する必要がない。
/// - Dock に出さない（Info.plist の LSUIElement と対）
/// - 設定ウィンドウを閉じたら終了する
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement アプリは前面に来ないため、明示的にアクティブにする。
        // これをしないと設定ウィンドウが他のウィンドウの裏に開く。
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

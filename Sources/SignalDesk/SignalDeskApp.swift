import SwiftUI

@main
struct SignalDeskApp: App {
    @StateObject private var store = SignalStore()
    @StateObject private var investorStore = InvestorHoldingsStore()
    @StateObject private var investorWritingStore = InvestorWritingStore()
    @StateObject private var qdiiQuotaStore = QDIIQuotaStore()
    @StateObject private var fontScaleStore = SignalDeskFontScaleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(investorStore)
                .environmentObject(investorWritingStore)
                .environmentObject(qdiiQuotaStore)
                .environment(\.signalDeskFontScaleFactor, fontScaleStore.scale.factor)
                .frame(minWidth: 1_040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新全部") {
                    Task {
                        await store.refresh()
                        await qdiiQuotaStore.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    NotificationCenter.default.post(name: .signalDeskOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("显示") {
                Button("放大字体") {
                    fontScaleStore.adjust(by: 1)
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])
                .disabled(fontScaleStore.scale == .extraLarge)

                Button("缩小字体") {
                    fontScaleStore.adjust(by: -1)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(fontScaleStore.scale == .small)

                Button("恢复标准字体") {
                    fontScaleStore.reset()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(fontScaleStore.scale == .standard)

                Divider()
                Text("当前字号：\(fontScaleStore.scale.title)")
            }
        }
    }
}

extension Notification.Name {
    static let signalDeskOpenSettings = Notification.Name("SignalDesk.openSettings")
}

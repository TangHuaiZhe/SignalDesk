import SwiftUI
import UserNotifications

@MainActor
final class SignalNotificationRouter: ObservableObject {
    static let shared = SignalNotificationRouter()

    @Published private(set) var pendingEventID: String?

    private init() {}

    func open(eventID: String) {
        pendingEventID = eventID
    }

    func clear(eventID: String) {
        guard pendingEventID == eventID else { return }
        pendingEventID = nil
    }
}

final class SignalDeskAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let eventID = SignalStore.notificationEventID(from: response.notification.request.content.userInfo)
        Task { @MainActor in
            if let eventID {
                SignalNotificationRouter.shared.open(eventID: eventID)
            }
            NSApp.activate(ignoringOtherApps: true)
            completionHandler()
        }
    }
}

@main
struct SignalDeskApp: App {
    @NSApplicationDelegateAdaptor(SignalDeskAppDelegate.self) private var appDelegate
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

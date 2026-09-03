import Foundation
import Testing
@testable import SignalDesk

struct SignalStoreNotificationTests {
    @Test @MainActor
    func notificationUsesLatestPublishedEvent() {
        let sourceID = UUID()
        let older = event(id: "older", title: "最早的通知", publishedAt: 100, sourceID: sourceID)
        let newer = event(id: "newer", title: "最新的通知", publishedAt: 200, sourceID: sourceID)

        let notification = SignalStore.notificationContent(for: [older, newer])
        #expect(notification.title == "最新的通知")
        #expect(notification.body == "最新消息内容 等 2 条")
    }

    private func event(id: String, title: String, publishedAt: TimeInterval, sourceID: UUID) -> SignalEvent {
        SignalEvent(
            id: id,
            sourceID: sourceID,
            sourceName: "Test",
            title: title,
            summary: id == "newer" ? "最新消息内容" : "旧消息内容",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: publishedAt),
            category: .activity,
            importance: 80,
            matchedTopics: []
        )
    }
}

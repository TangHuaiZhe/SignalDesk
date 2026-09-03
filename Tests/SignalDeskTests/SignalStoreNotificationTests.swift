import Foundation
import Testing
@testable import SignalDesk

struct SignalStoreNotificationTests {
    @Test @MainActor
    func notificationUsesOnlyLatestTriggeringEvent() throws {
        let sourceID = UUID()
        let older = event(id: "older", title: "最早的通知", publishedAt: 100, sourceID: sourceID)
        let newer = event(id: "newer", title: "最新的通知", publishedAt: 200, sourceID: sourceID)

        let triggeringEvent = try #require(SignalStore.triggeringNotificationEvent(in: [older, newer]))
        #expect(triggeringEvent.id == newer.id)

        let notification = SignalStore.notificationContent(for: triggeringEvent)
        #expect(notification.title == "最新的通知")
        #expect(notification.body == "最新消息内容")
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

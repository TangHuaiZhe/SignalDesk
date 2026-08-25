import Foundation
import Testing
@testable import SignalDesk

struct SignalStoreNotificationTests {
    @Test @MainActor
    func notificationUsesLatestPublishedEvent() {
        let sourceID = UUID()
        let older = event(id: "older", title: "最早的通知", publishedAt: 100, sourceID: sourceID)
        let newer = event(id: "newer", title: "最新的通知", publishedAt: 200, sourceID: sourceID)

        #expect(SignalStore.notificationBody(for: [older, newer]) == "最新的通知 等 2 条")
    }

    private func event(id: String, title: String, publishedAt: TimeInterval, sourceID: UUID) -> SignalEvent {
        SignalEvent(
            id: id,
            sourceID: sourceID,
            sourceName: "Test",
            title: title,
            summary: "",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: publishedAt),
            category: .activity,
            importance: 80,
            matchedTopics: []
        )
    }
}

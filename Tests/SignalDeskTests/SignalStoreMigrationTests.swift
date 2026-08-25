import Foundation
import Testing
@testable import SignalDesk

struct SignalStoreMigrationTests {
    @Test @MainActor
    func installsRequestedPeopleOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SignalStore(stateURL: stateURL)
        let firstKeys = Set(first.sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL.lowercased())" })
        let second = SignalStore(stateURL: stateURL)

        #expect(first.sources.count == 39)
        #expect(firstKeys.count == first.sources.count)
        #expect(first.sources.filter { $0.sourceKind == .x }.isEmpty)
        #expect(first.sources.filter { $0.sourceKind == .mediaSearch }.count == 12)
        #expect(first.sources.filter { $0.name.contains("李飞飞 / Fei-Fei Li · a16z") }.count == 1)
        #expect(first.sources.filter { $0.name.contains("SemiAnalysis") }.count == 1)
        #expect(first.sources.filter { $0.channel == .chinaEconomy }.count == 6)
        #expect(first.sources.filter { $0.channel == .magazines }.count == 4)
        #expect(second.sources.count == first.sources.count)
    }

    @Test @MainActor
    func addsRayDalioToExistingLongFormCatalog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let snapshot = AppSnapshot(
            sources: TrackedSource.starterSources,
            events: [],
            lastRefreshAt: nil,
            installedCatalogIDs: ["ai-robotics-longform-v4", "signal-domains-v3"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: stateURL)

        let migrated = SignalStore(stateURL: stateURL)
        let raySources = migrated.sources.filter {
            $0.name.localizedCaseInsensitiveContains("Ray Dalio")
        }

        #expect(raySources.count == 2)
        #expect(raySources.contains { $0.sourceKind == .mediaSearch })
        #expect(raySources.contains { $0.sourceKind == .rss })
    }

    @Test @MainActor
    func markReadUpdatesAndPersistsEvent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SignalStore(stateURL: stateURL)
        let eventID = try #require(store.events.first?.id)
        #expect(store.events.first { $0.id == eventID }?.isRead == false)

        store.markRead(eventID)

        #expect(store.events.first { $0.id == eventID }?.isRead == true)
        let reloaded = SignalStore(stateURL: stateURL)
        #expect(reloaded.events.first { $0.id == eventID }?.isRead == true)
    }

    @Test @MainActor
    func migratesLegacyEventsToCanonicalDomains() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = TrackedSource(
            name: "Legacy feed",
            role: "Test",
            topics: ["robot", "GPU"],
            sourceKind: .rss,
            feedURL: "https://example.com/feed.xml"
        )
        let event = SignalEvent(
            id: "legacy-domain-event",
            sourceID: source.id,
            sourceName: source.name,
            title: "Humanoid robot inference moves to a new GPU",
            summary: "A physical AI system runs on an edge accelerator.",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            category: .viewpoint,
            importance: 80,
            matchedTopics: ["robot", "GPU"]
        )
        let snapshot = AppSnapshot(
            sources: [source],
            events: [event],
            lastRefreshAt: nil,
            installedCatalogIDs: ["ai-robotics-longform-v4"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: stateURL)

        let migrated = SignalStore(stateURL: stateURL)
        let domains = try #require(migrated.events.first?.domains)

        #expect(domains.contains(.robotics))
        #expect(domains.contains(.compute))
    }

    @Test @MainActor
    func migratesLegacyDailyBriefAndPreservesHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let older = DailyBrief(
            id: "2026-08-07",
            generatedAt: Date(timeIntervalSince1970: 1_754_260_000),
            windowStart: Date(timeIntervalSince1970: 1_754_173_600),
            windowEnd: Date(timeIntervalSince1970: 1_754_260_000),
            trackedEventCount: 4,
            newsItemCount: 8,
            provider: .ollama,
            content: "# 旧快报"
        )
        let newer = DailyBrief(
            id: "2026-08-08",
            generatedAt: Date(timeIntervalSince1970: 1_754_346_400),
            windowStart: Date(timeIntervalSince1970: 1_754_260_000),
            windowEnd: Date(timeIntervalSince1970: 1_754_346_400),
            trackedEventCount: 6,
            newsItemCount: 10,
            provider: .ollama,
            content: "# 新快报"
        )
        let snapshot = AppSnapshot(
            sources: TrackedSource.starterSources,
            events: [],
            lastRefreshAt: nil,
            dailyBrief: older,
            dailyBriefs: [newer]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: stateURL)

        let store = SignalStore(stateURL: stateURL)

        #expect(store.dailyBriefs.map(\.id) == ["2026-08-08", "2026-08-07"])
        #expect(store.dailyBrief?.id == "2026-08-08")
    }

    @Test @MainActor
    func keepsIndependentXAndRSSHistoryLimits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let rss = TrackedSource(
            name: "News",
            role: "News",
            topics: ["AI"],
            sourceKind: .rss,
            feedURL: "https://example.com/news.xml"
        )
        let x = TrackedSource.x(
            name: "李飞飞 / Fei-Fei Li",
            role: "X",
            username: "drfeifei",
            topics: ["AI", "robot"]
        )
        let recentNews = (0..<1_200).map { index in
            SignalEvent(
                id: "news-\(index)", sourceID: rss.id, sourceName: rss.name,
                title: "News \(index)", summary: "News", url: nil,
                publishedAt: Date(timeIntervalSince1970: 2_000_000_000 - Double(index)),
                category: .activity, importance: 40, matchedTopics: ["AI"]
            )
        }
        let olderX = (0..<1_100).map { index in
            SignalEvent(
                id: "x-\(index)", sourceID: x.id, sourceName: x.name,
                title: "Post \(index)", summary: "Post", url: nil,
                publishedAt: Date(timeIntervalSince1970: 1_000_000_000 - Double(index)),
                category: .viewpoint, importance: 40, matchedTopics: ["AI"]
            )
        }
        let snapshot = AppSnapshot(
            sources: [rss, x],
            events: recentNews + olderX,
            lastRefreshAt: nil,
            installedCatalogIDs: [
                "ai-robotics-longform-v4", "fei-fei-li-a16z-v1", "ray-dalio-v1",
                "research-sources-v1", "signal-domains-v3"
            ]
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: stateURL)

        let store = SignalStore(stateURL: stateURL)

        #expect(store.events.filter { $0.sourceID == x.id }.count == 1_000)
        #expect(store.events.filter { $0.sourceID == rss.id }.count == 1_000)
        #expect(store.events.count == 2_000)
    }
}

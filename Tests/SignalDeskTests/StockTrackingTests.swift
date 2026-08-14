import Foundation
import Testing
@testable import SignalDesk

struct StockTrackingTests {
    @Test
    func refreshCoordinatorDeduplicatesUpdatesAndSkipsDisabledStocks() async {
        let enabled = StockWatchlistItem(symbol: "NVDA", name: "NVIDIA", market: "US")
        let disabled = StockWatchlistItem(symbol: "600519", name: "贵州茅台", market: "CN", isEnabled: false)
        let existing = update(id: "existing", stock: enabled, kind: .news)
        let incoming = update(id: "existing", stock: enabled, kind: .news)
        let fresh = update(id: "fresh", stock: enabled, kind: .announcements)
        let fetcher = StubStockFetcher(updates: [enabled.id: [incoming, fresh]])

        let result = await StockRefreshCoordinator(client: fetcher, now: { Date(timeIntervalSince1970: 10_000) })
            .refresh(watchlist: [enabled, disabled], existingUpdates: [existing])

        #expect(fetcher.fetchedStockIDs == [enabled.id])
        #expect(result.addedUpdates.map(\.id) == ["fresh"])
        #expect(result.checkedAtByStockID[enabled.id] == Date(timeIntervalSince1970: 10_000))
        #expect(result.checkedAtByStockID[disabled.id] == nil)
    }

    @Test @MainActor
    func stockWatchlistAddsNormalizesAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SignalStore(stateURL: stateURL)
        #expect(store.addStock(symbol: "  nvda ", name: "NVIDIA", market: "us"))
        #expect(!store.addStock(symbol: "NVDA", name: "NVIDIA duplicate", market: "US"))
        #expect(store.stockWatchlist.first?.symbol == "NVDA")
        #expect(store.stockWatchlist.first?.market == "US")

        let reloaded = SignalStore(stateURL: stateURL)
        #expect(reloaded.stockWatchlist.count == 1)
        #expect(reloaded.stockWatchlist.first?.displayName == "NVIDIA（NVDA）")
    }

    @Test @MainActor
    func migratesLegacyShortNumericOtherMarketToHongKong() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacy = StockWatchlistItem(symbol: "00700", name: "腾讯控股", market: "OTHER")
        let snapshot = AppSnapshot(
            sources: [],
            events: [],
            lastRefreshAt: nil,
            installedCatalogIDs: [
                "ai-robotics-longform-v4", "fei-fei-li-a16z-v1", "ray-dalio-v1",
                "research-sources-v1", "china-economy-sources-v1", "signal-domains-v3"
            ],
            stockWatchlist: [legacy]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: stateURL)

        let store = SignalStore(stateURL: stateURL)

        #expect(store.stockWatchlist.first?.market == "HK")
    }

    @Test
    func exposesHongKongMarketCodeForStockQueries() {
        #expect(StockMarket.hk.code == "HK")
        #expect(StockMarket.hk.title == "香港市场")
    }

    @Test
    func deepReportsRequireTenPagesAndRecentPublicationDate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let old = Calendar.current.date(byAdding: .month, value: -7, to: now)!

        #expect(StockResearchReportFilter.isEligible(publishedAt: recent, pageCount: 10, now: now))
        #expect(!StockResearchReportFilter.isEligible(publishedAt: recent, pageCount: 9, now: now))
        #expect(!StockResearchReportFilter.isEligible(publishedAt: old, pageCount: 30, now: now))
    }

    @Test
    func resolvesHongKongCodeAndDualListedCompanyChoices() async {
        let tencent = await StockLookupClient().search("00700")
        #expect(tencent.count == 1)
        #expect(tencent.first?.symbol == "00700")
        #expect(tencent.first?.market == "HK")

        let alibaba = await StockLookupClient().search("阿里巴巴")
        #expect(Set(alibaba.map(\.market)) == Set(["HK", "US"]))
    }

    @Test @MainActor
    func deletesInformationAcrossSignalStockAndBriefStores() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = TrackedSource(
            name: "Test source",
            role: "Test",
            topics: [],
            sourceKind: .rss,
            feedURL: "https://example.com/feed.xml"
        )
        let event = SignalEvent(
            id: "deletable-event",
            sourceID: source.id,
            sourceName: source.name,
            title: "Event",
            summary: "",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 1),
            category: .activity,
            importance: 50,
            matchedTopics: []
        )
        let stock = StockWatchlistItem(symbol: "00700", name: "腾讯控股", market: "HK")
        let update = StockUpdate(
            id: "deletable-stock-update",
            stockID: stock.id,
            symbol: stock.symbol,
            stockName: stock.name,
            kind: .news,
            title: "Stock update",
            summary: "",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 1),
            importance: 50
        )
        let brief = DailyBrief(
            id: "deletable-brief",
            generatedAt: Date(timeIntervalSince1970: 1),
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 1),
            trackedEventCount: 1,
            newsItemCount: 1,
            provider: .ollama,
            content: "# Brief"
        )
        let snapshot = AppSnapshot(
            sources: [source],
            events: [event],
            lastRefreshAt: nil,
            installedCatalogIDs: [
                "ai-robotics-longform-v4", "fei-fei-li-a16z-v1", "ray-dalio-v1",
                "research-sources-v1", "china-economy-sources-v1", "signal-domains-v3"
            ],
            dailyBriefs: [brief],
            stockWatchlist: [stock],
            stockUpdates: [update]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: stateURL)

        let store = SignalStore(stateURL: stateURL)
        store.deleteEvent(event.id)
        store.deleteStockUpdate(update.id)
        store.deleteDailyBrief(brief.id)

        let reloaded = SignalStore(stateURL: stateURL)
        #expect(!reloaded.events.contains { $0.id == event.id })
        #expect(!reloaded.stockUpdates.contains { $0.id == update.id })
        #expect(!reloaded.dailyBriefs.contains { $0.id == brief.id })
    }

    private func update(id: String, stock: StockWatchlistItem, kind: StockInfoKind) -> StockUpdate {
        StockUpdate(
            id: id,
            stockID: stock.id,
            symbol: stock.symbol,
            stockName: stock.name,
            kind: kind,
            title: id,
            summary: "summary",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 1),
            importance: 60
        )
    }
}

private final class StubStockFetcher: StockFetching, @unchecked Sendable {
    let updates: [UUID: [StockUpdate]]
    private(set) var fetchedStockIDs: [UUID] = []

    init(updates: [UUID: [StockUpdate]]) {
        self.updates = updates
    }

    func fetch(_ stock: StockWatchlistItem) async throws -> [StockUpdate] {
        fetchedStockIDs.append(stock.id)
        return updates[stock.id] ?? []
    }
}

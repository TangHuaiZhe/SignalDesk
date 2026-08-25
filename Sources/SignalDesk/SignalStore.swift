import Combine
import Foundation
import UserNotifications

@MainActor
final class SignalStore: ObservableObject {
    @Published private(set) var sources: [TrackedSource] = []
    @Published private(set) var events: [SignalEvent] = []
    @Published private(set) var stockWatchlist: [StockWatchlistItem] = []
    @Published private(set) var stockUpdates: [StockUpdate] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var dailyBriefs: [DailyBrief] = []
    @Published var isGeneratingDailyBrief = false
    @Published var isRefreshing = false
    @Published var statusMessage: String?

    private let refreshCoordinator: RefreshCoordinator
    private let stockRefreshCoordinator: StockRefreshCoordinator
    private let persistence: SignalStatePersistence
    private var installedCatalogIDs = Set<String>()
    private static let requestedPeopleCatalogID = "ai-robotics-longform-v4"
    private static let feiFeiA16ZCatalogID = "fei-fei-li-a16z-v1"
    private static let rayDalioCatalogID = "ray-dalio-v1"
    private static let domainTaxonomyID = "signal-domains-v3"
    private static let researchSourcesCatalogID = "research-sources-v1"
    private static let chinaEconomySourcesCatalogID = "china-economy-sources-v1"
    private static let magazineSourcesCatalogID = "english-magazine-sources-v1"

    init(
        stateURL: URL? = nil,
        refreshCoordinator: RefreshCoordinator = RefreshCoordinator(),
        stockRefreshCoordinator: StockRefreshCoordinator = StockRefreshCoordinator()
    ) {
        self.refreshCoordinator = refreshCoordinator
        self.stockRefreshCoordinator = stockRefreshCoordinator
        self.persistence = SignalStatePersistence(url: stateURL)
        load()
        installRequestedPeopleIfNeeded()
        installFeiFeiA16ZIfNeeded()
        installRayDalioIfNeeded()
        installResearchSourcesIfNeeded()
        installChinaEconomySourcesIfNeeded()
        installMagazineSourcesIfNeeded()
        installDomainTaxonomyIfNeeded()
    }

    var unreadCount: Int { events.filter { !$0.isRead }.count }
    var highValueCount: Int { events.filter { $0.importance >= 75 }.count }
    var dailyBrief: DailyBrief? { dailyBriefs.first }

    func add(_ source: TrackedSource) {
        sources.append(source)
        save()
    }

    @discardableResult
    func addStock(symbol: String, name: String, market: String) -> Bool {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedMarket = market.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let effectiveMarket = normalizedMarket.isEmpty ? "CN" : normalizedMarket
        guard !normalizedSymbol.isEmpty else { return false }
        guard !stockWatchlist.contains(where: {
            $0.symbol.caseInsensitiveCompare(normalizedSymbol) == .orderedSame &&
            $0.market.caseInsensitiveCompare(effectiveMarket) == .orderedSame
        }) else { return false }

        stockWatchlist.append(
            StockWatchlistItem(
                symbol: normalizedSymbol,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                market: effectiveMarket
            )
        )
        save()
        return true
    }

    @discardableResult
    func addStock(_ candidate: StockCandidate) -> Bool {
        addStock(symbol: candidate.symbol, name: candidate.name, market: candidate.market)
    }

    func removeStocks(at offsets: IndexSet) {
        let ids = offsets.map { stockWatchlist[$0].id }
        stockWatchlist.remove(atOffsets: offsets)
        stockUpdates.removeAll { ids.contains($0.stockID) }
        save()
    }

    func toggleStock(_ stock: StockWatchlistItem) {
        guard let index = stockWatchlist.firstIndex(where: { $0.id == stock.id }) else { return }
        stockWatchlist[index].isEnabled.toggle()
        save()
    }

    func markStockUpdateRead(_ id: String) {
        guard let index = stockUpdates.firstIndex(where: { $0.id == id }) else { return }
        stockUpdates[index].isRead = true
        save()
    }

    func markAllStockUpdatesRead() {
        for index in stockUpdates.indices {
            stockUpdates[index].isRead = true
        }
        save()
    }

    func toggleStockUpdateBookmark(_ id: String) {
        guard let index = stockUpdates.firstIndex(where: { $0.id == id }) else { return }
        stockUpdates[index].isBookmarked.toggle()
        save()
    }

    func deleteStockUpdates(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        stockUpdates.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteStockUpdate(_ id: String) {
        deleteStockUpdates([id])
    }

    @discardableResult
    func importPeople(_ people: [PersonPreset]) -> Int {
        var keys = Set(sources.map(Self.sourceKey))
        var added = 0

        for source in people.flatMap({ $0.trackedSources() }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        statusMessage = added == 0
            ? "这些人物已经在监控列表中"
            : "已导入 \(people.count) 位人物的 \(added) 个来源"
        save()
        return added
    }

    @discardableResult
    func importXBloggers(_ bloggers: [XBloggerPreset], isEnabled: Bool? = nil) -> Int {
        var keys = Set(sources.map(Self.sourceKey))
        let enablesX = isEnabled ?? (XProvider.selected.apiKey != nil)
        var added = 0

        for blogger in bloggers {
            let source = blogger.trackedSource(isEnabled: enablesX)
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        statusMessage = added == 0
            ? "这些 X 博主已经在监控列表中"
            : "已导入 \(added) 位 X 博主"
        save()
        return added
    }

    func enableXSources() {
        var changed = false
        for index in sources.indices where sources[index].sourceKind == .x && !sources[index].isEnabled {
            sources[index].isEnabled = true
            changed = true
        }
        if changed { save() }
    }

    func removeSources(at offsets: IndexSet) {
        let ids = offsets.map { sources[$0].id }
        sources.remove(atOffsets: offsets)
        events.removeAll { ids.contains($0.sourceID) }
        save()
    }

    func toggleSource(_ source: TrackedSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].isEnabled.toggle()
        save()
    }

    func markRead(_ id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].isRead = true
        save()
    }

    func toggleBookmark(_ id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].isBookmarked.toggle()
        save()
    }

    func deleteEvents(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        events.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteEvent(_ id: String) {
        deleteEvents([id])
    }

    func deleteDailyBrief(_ id: String) {
        guard dailyBriefs.contains(where: { $0.id == id }) else { return }
        dailyBriefs.removeAll { $0.id == id }
        save()
    }

    func saveSummary(_ summary: AISummary, for id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].aiSummary = summary
        save()
    }

    func saveTranslation(_ translation: AITranslation, for id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].aiTranslation = translation
        save()
    }

    func clearTranslation(for id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].aiTranslation = nil
        save()
    }

    func clearSummary(for id: String) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].aiSummary = nil
        save()
    }

    func markAllRead() {
        for index in events.indices { events[index].isRead = true }
        save()
    }

    func refreshDailyBrief() async {
        await refresh()
        await generateDailyBrief(force: true)
    }

    func generateDailyBriefIfNeeded(now: Date = Date()) async {
        let calendar = Calendar.current
        guard let scheduledAt = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: now
        ), now >= scheduledAt else {
            return
        }
        let dayID = String(ISO8601DateFormatter().string(from: now).prefix(10))
        let generatedAt = dailyBrief?.generatedAt ?? .distantPast
        guard dailyBrief?.id != dayID || generatedAt < scheduledAt else {
            return
        }
        await generateDailyBrief(force: true, now: now)
    }

    func generateDailyBrief(force: Bool = false, now: Date = Date()) async {
        guard !isGeneratingDailyBrief else { return }
        let calendar = Calendar.current
        let dayID = String(ISO8601DateFormatter().string(from: now).prefix(10))
        if !force,
           dailyBrief?.id == dayID,
           let scheduledAt = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now),
           dailyBrief?.generatedAt ?? .distantPast >= scheduledAt {
            return
        }

        isGeneratingDailyBrief = true
        statusMessage = "正在搜索全网新闻并生成每日快报…"
        defer { isGeneratingDailyBrief = false }

        do {
            let windowEnd = now
            let windowStart = now.addingTimeInterval(-24 * 3_600)
            let recentEvents = events.filter {
                $0.publishedAt >= windowStart && $0.publishedAt <= windowEnd
            }
            let news = try await NewsSearchClient().search(now: now)
            let brief = try await DailyBriefService().generate(
                events: recentEvents,
                news: news,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
            dailyBriefs.removeAll { $0.id == brief.id }
            dailyBriefs.append(brief)
            dailyBriefs.sort { $0.generatedAt > $1.generatedAt }
            statusMessage = "每日快报已更新 · \(recentEvents.count) 条情报 · \(news.count) 条新闻"
            save()
        } catch {
            statusMessage = "每日快报生成失败：\(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = nil
        defer { isRefreshing = false }

        let result = await refreshCoordinator.refresh(
            sources: sources,
            existingEvents: events,
            provider: XProvider.selected
        )
        for (sourceID, checkedAt) in result.checkedAtBySourceID {
            guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { continue }
            sources[index].lastCheckedAt = checkedAt
        }

        events.append(contentsOf: result.addedEvents)
        events = trimEvents(events)
        lastRefreshAt = result.refreshedAt

        let stockResult = await stockRefreshCoordinator.refresh(
            watchlist: stockWatchlist,
            existingUpdates: stockUpdates
        )
        for (stockID, checkedAt) in stockResult.checkedAtByStockID {
            guard let index = stockWatchlist.firstIndex(where: { $0.id == stockID }) else { continue }
            stockWatchlist[index].lastCheckedAt = checkedAt
        }
        stockUpdates.append(contentsOf: stockResult.addedUpdates)
        stockUpdates = trimStockUpdates(stockUpdates)

        let failures = result.failures + stockResult.failures
        let addedCount = result.addedEvents.count + stockResult.addedUpdates.count
        if failures.isEmpty {
            statusMessage = addedCount == 0 ? "已是最新" : "新增 \(addedCount) 条信息"
        } else {
            let firstFailure = failures.first.map { "；\($0)" } ?? ""
            statusMessage = "新增 \(addedCount) 条；\(failures.count) 个来源失败\(firstFailure)"
        }
        save()
        await notify(for: result.addedEvents.filter { $0.importance >= 80 })
    }

    private func load() {
        do {
            let snapshot = try persistence.load()
            sources = snapshot.sources
            events = trimEvents(snapshot.events)
            let migratedStocks = Self.migrateStockMarkets(snapshot.stockWatchlist ?? [])
            stockWatchlist = migratedStocks
            stockUpdates = trimStockUpdates(snapshot.stockUpdates ?? [])
            lastRefreshAt = snapshot.lastRefreshAt
            var briefs = snapshot.dailyBriefs ?? []
            if let legacyBrief = snapshot.dailyBrief,
               !briefs.contains(where: { $0.id == legacyBrief.id }) {
                briefs.append(legacyBrief)
            }
            dailyBriefs = briefs.sorted { $0.generatedAt > $1.generatedAt }
            installedCatalogIDs = Set(snapshot.installedCatalogIDs ?? [])
            if migratedStocks != (snapshot.stockWatchlist ?? []) {
                save()
            }
        } catch {
            sources = TrackedSource.starterSources
            events = Self.welcomeEvents(for: sources)
            save()
        }
    }

    private func save() {
        do {
            let snapshot = AppSnapshot(
                sources: sources,
                events: events,
                lastRefreshAt: lastRefreshAt,
                installedCatalogIDs: Array(installedCatalogIDs).sorted(),
                dailyBrief: dailyBrief,
                dailyBriefs: dailyBriefs,
                stockWatchlist: stockWatchlist,
                stockUpdates: stockUpdates
            )
            try persistence.save(snapshot)
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func notify(for newEvents: [SignalEvent]) async {
        guard !newEvents.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "SignalDesk 捕捉到高价值信号"
        content.body = Self.notificationBody(for: newEvents)
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    static func notificationBody(for events: [SignalEvent]) -> String {
        let latestEvent = events.max { $0.publishedAt < $1.publishedAt } ?? events[0]
        return events.count == 1
            ? latestEvent.title
            : "\(latestEvent.title) 等 \(events.count) 条"
    }

    private static func welcomeEvents(for sources: [TrackedSource]) -> [SignalEvent] {
        guard let first = sources.first else { return [] }
        return [
            SignalEvent(
                id: "welcome",
                sourceID: first.id,
                sourceKind: first.sourceKind,
                sourceName: "SignalDesk",
                title: "你的高价值人物情报台已就绪",
                summary: "点击右上角刷新可拉取官方 RSS。添加 SEC 13F 来源时只需填写机构 CIK；所有数据默认保存在本机。",
                url: nil,
                publishedAt: Date(),
                category: .activity,
                importance: 92,
                matchedTopics: ["AI", "投资"],
                domains: []
            )
        ]
    }

    private func trimEvents(_ candidates: [SignalEvent]) -> [SignalEvent] {
        let sorted = candidates.sorted { $0.publishedAt > $1.publishedAt }
        let xSourceIDs = Set(sources.filter { $0.sourceKind == .x }.map(\.id))
        let rssSourceIDs = Set(sources.filter { $0.sourceKind == .rss }.map(\.id))
        let xEvents = sorted.filter { xSourceIDs.contains($0.sourceID) }.prefix(1_000)
        let rssEvents = sorted.filter { rssSourceIDs.contains($0.sourceID) }.prefix(1_000)
        let otherEvents = sorted.filter {
            !xSourceIDs.contains($0.sourceID) && !rssSourceIDs.contains($0.sourceID)
        }.prefix(600)
        return (Array(xEvents) + Array(rssEvents) + Array(otherEvents))
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private func trimStockUpdates(_ candidates: [StockUpdate]) -> [StockUpdate] {
        let sorted = candidates.sorted { $0.publishedAt > $1.publishedAt }
        let stockIDs = Set(stockWatchlist.map(\.id))
        return sorted
            .filter { stockIDs.contains($0.stockID) }
            .prefix(500)
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private static func migrateStockMarkets(_ stocks: [StockWatchlistItem]) -> [StockWatchlistItem] {
        stocks.map { stock in
            guard stock.market.uppercased() == StockMarket.other.code,
                  stock.symbol.allSatisfy(\.isNumber),
                  stock.symbol.count <= 5 else {
                return stock
            }
            var migrated = stock
            migrated.market = StockMarket.hk.code
            return migrated
        }
    }

    private func installRequestedPeopleIfNeeded() {
        guard installedCatalogIDs.insert(Self.requestedPeopleCatalogID).inserted else { return }

        let removedSourceIDs = sources
            .filter {
                ($0.sourceKind == .x &&
                 PersonPreset.legacyXUsernames.contains($0.feedURL.lowercased())) ||
                $0.sourceKind == .mediaSearch
            }
            .map(\.id)
        sources.removeAll { removedSourceIDs.contains($0.id) }
        events.removeAll { removedSourceIDs.contains($0.sourceID) }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0

        for source in PersonPreset.aiRoboticsLeaders.flatMap({ $0.trackedSources() }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        statusMessage = "已切换长内容追踪：移除 \(removedSourceIDs.count) 个 X 来源，新增 \(added) 个媒体来源"
        save()
    }

    private static func sourceKey(_ source: TrackedSource) -> String {
        "\(source.sourceKind.rawValue)|\(source.feedURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func installRayDalioIfNeeded() {
        guard installedCatalogIDs.insert(Self.rayDalioCatalogID).inserted,
              let rayDalio = PersonPreset.aiRoboticsLeaders.first(where: { $0.id == "ray-dalio" }) else {
            return
        }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0
        for source in rayDalio.trackedSources() {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        if added > 0 {
            statusMessage = "已新增瑞·达利欧的 \(added) 个情报来源"
        }
        save()
    }

    private func installFeiFeiA16ZIfNeeded() {
        guard installedCatalogIDs.insert(Self.feiFeiA16ZCatalogID).inserted,
              let feiFeiLi = PersonPreset.aiRoboticsLeaders.first(where: { $0.id == "fei-fei-li" }) else {
            return
        }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0
        for source in feiFeiLi.trackedSources().filter({ $0.name.contains("a16z") }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        if added > 0 {
            statusMessage = "已新增李飞飞的 a16z 播客与访谈来源"
        }
        save()
    }

    private func installDomainTaxonomyIfNeeded() {
        guard installedCatalogIDs.insert(Self.domainTaxonomyID).inserted else { return }
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        for index in events.indices {
            let event = events[index]
            let source = sourcesByID[event.sourceID]
            let text = "\(event.title) \(event.summary)"
            events[index].domains = SignalDomainClassifier.classify(
                text: text,
                fallbackDomains: source.map(PersonPreset.defaultDomains) ?? [],
                kind: source?.sourceKind
            )
        }
        save()
    }

    private func installResearchSourcesIfNeeded() {
        guard installedCatalogIDs.insert(Self.researchSourcesCatalogID).inserted else { return }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0
        for source in CuratedSourcePreset.researchSources.map({ $0.trackedSource() }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        if added > 0 {
            statusMessage = "已新增 (added) 个研究与产业链来源"
        }
        save()
    }

    private func installChinaEconomySourcesIfNeeded() {
        guard installedCatalogIDs.insert(Self.chinaEconomySourcesCatalogID).inserted else { return }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0
        for source in CuratedSourcePreset.chinaEconomySources.map({ $0.trackedSource() }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        if added > 0 {
            statusMessage = "已新增 \(added) 个海外看中国来源"
        }
        save()
    }

    private func installMagazineSourcesIfNeeded() {
        guard installedCatalogIDs.insert(Self.magazineSourcesCatalogID).inserted else { return }

        var keys = Set(sources.map(Self.sourceKey))
        var added = 0
        for source in CuratedSourcePreset.magazineSources.map({ $0.trackedSource() }) {
            guard keys.insert(Self.sourceKey(source)).inserted else { continue }
            sources.append(source)
            added += 1
        }
        if added > 0 {
            statusMessage = "已新增 \(added) 个英语杂志来源"
        }
        save()
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SignalStore
    @EnvironmentObject private var investorStore: InvestorHoldingsStore
    @EnvironmentObject private var qdiiQuotaStore: QDIIQuotaStore
    @Environment(\.openURL) private var openURL
    @ObservedObject private var notificationRouter = SignalNotificationRouter.shared
    @State private var section: AppSection? = .longForm
    @State private var selection: String?
    @State private var showingAddSource = false
    @State private var query = ""
    @State private var category: SignalCategory?
    @State private var sortOptions: [AppSection: SignalSortOption] = [:]
    @State private var selectedTopic: SignalDomain?
    @State private var selectedSourceGroupKey: String?
    @State private var expandedSourceSections: Set<AppSection> = []
    @State private var selectedDailyBriefID: String?
    @State private var selectedInvestorID = InvestorPreset.featured.first?.id
    @State private var selectedInvestorTab = InvestorPageTab.investors
    @State private var showingAddStock = false
    @State private var selectedStockID: UUID?
    @State private var showingAddQDII = false
    @State private var selectedQDIIID: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if section == .sources {
                SourcesView(showingAddSource: $showingAddSource)
            } else if section == .dailyBrief {
                DailyBriefIndexView(selection: $selectedDailyBriefID)
            } else if section == .investors {
                InvestorListView(
                    selection: $selectedInvestorID,
                    selectedTab: $selectedInvestorTab
                )
            } else if section == .settings {
                SettingsView()
            } else if section == .stocks {
                StockTimelineView(
                    selectedStockID: $selectedStockID,
                    selection: $selection,
                    showingAddStock: $showingAddStock
                )
            } else if section == .qdiiQuotas {
                QDIIQuotaView(selection: $selectedQDIIID, showingAddFund: $showingAddQDII)
            } else {
                timeline
            }
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onDeleteCommand {
            deleteSelectedInformation()
        }
        .sheet(isPresented: $showingAddSource) {
            AddSourceView()
        }
        .sheet(isPresented: $showingAddStock) {
            AddStockView()
        }
        .sheet(isPresented: $showingAddQDII) {
            AddQDIIQuotaView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .signalDeskOpenSettings)) { _ in
            section = .settings
            selection = nil
            selectedTopic = nil
            selectedSourceGroupKey = nil
        }
        .onReceive(notificationRouter.$pendingEventID.compactMap { $0 }) { eventID in
            openNotificationEvent(eventID)
        }
        .task {
            await store.clearLegacySignalNotifications()
            await store.refresh()
            await qdiiQuotaStore.refreshIfStale()
            await store.generateDailyBriefIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(secondsUntilNextBriefCheck()))
                guard !Task.isCancelled else { break }
                await store.refresh()
                await qdiiQuotaStore.refreshIfStale()
                await store.generateDailyBriefIfNeeded()
            }
        }
    }

    private func secondsUntilNextBriefCheck(now: Date = Date()) -> Double {
        let calendar = Calendar.current
        guard let todayAtEight = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: now
        ) else {
            return 900
        }
        if now < todayAtEight {
            return max(60, min(900, todayAtEight.timeIntervalSince(now)))
        }
        return 900
    }

    private func openNotificationEvent(_ eventID: String) {
        defer { notificationRouter.clear(eventID: eventID) }
        guard store.events.contains(where: { $0.id == eventID }) else { return }

        section = .highValue
        selection = eventID
        query = ""
        category = nil
        selectedTopic = nil
        selectedSourceGroupKey = nil
        selectedStockID = nil
        selectedQDIIID = nil
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                brand
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 10, bottom: 20, trailing: 8))
            }

            Section {
                ForEach(AppSection.allCases) { item in
                    if isSourceSection(item) {
                        HStack(spacing: 4) {
                            Button {
                                toggleSourceSection(item)
                            } label: {
                                Image(systemName: expandedSourceSections.contains(item) ? "chevron.down" : "chevron.right")
                                    .scaledFont(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                expandedSourceSections.contains(item) ? "收起\(item.title)" : "展开\(item.title)"
                            )

                            Button {
                                selectSection(item)
                            } label: {
                                sectionLabel(item)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(
                            section == item && (selectedSourceGroupKey == nil || !expandedSourceSections.contains(item))
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                    } else if item == .stocks {
                        HStack(spacing: 4) {
                            Button {
                                toggleSourceSection(item)
                            } label: {
                                Image(systemName: expandedSourceSections.contains(item) ? "chevron.down" : "chevron.right")
                                    .scaledFont(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, height: 24)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                expandedSourceSections.contains(item) ? "收起(item.title)" : "展开(item.title)"
                            )

                            Button {
                                selectSection(item)
                            } label: {
                                sectionLabel(item)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(
                            section == item && selectedStockID == nil
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                    } else if item == .qdiiQuotas {
                        Button {
                            selectSection(item)
                        } label: {
                            sectionLabel(item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(section == item ? Color.accentColor.opacity(0.15) : Color.clear)
                    } else {
                        Label {
                            HStack {
                                Text(item.title)
                                Spacer()
                                if let count = badgeCount(for: item), count > 0 {
                                    Text("\(count)")
                                        .scaledFont(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: item.icon)
                                .foregroundStyle(item == .highValue ? .orange : .blue)
                        }
                        .tag(item)
                    }

                    if isSourceSection(item) && expandedSourceSections.contains(item) {
                        ForEach(sourceGroups(for: item)) { group in
                            Button {
                                selectSourceGroup(group.key, in: item)
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(group.sources.contains(where: { $0.isEnabled }) ? Color.blue : Color.secondary)
                                        .frame(width: 6, height: 6)
                                    Text(group.title)
                                        .lineLimit(1)
                                    Spacer()
                                    let unread = unreadCount(for: group)
                                    if unread > 0 {
                                        Text("\(unread)")
                                            .scaledFont(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 23)
                            .listRowBackground(
                                section == item && selectedSourceGroupKey == group.key
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        }
                    }

                    if item == .stocks && expandedSourceSections.contains(item) {
                        ForEach(store.stockWatchlist) { stock in
                            Button {
                                selectStock(stock)
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(stock.isEnabled ? Color.blue : Color.secondary)
                                        .frame(width: 6, height: 6)
                                    Text(stock.displayName)
                                        .lineLimit(1)
                                    Spacer()
                                    let unread = store.stockUpdates.filter {
                                        $0.stockID == stock.id && !$0.isRead
                                    }.count
                                    if unread > 0 {
                                        Text("\(unread)")
                                            .scaledFont(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 23)
                            .listRowBackground(
                                section == .stocks && selectedStockID == stock.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("监控")
                    Spacer()
                    Button {
                        toggleAllSourceSections()
                    } label: {
                        Image(systemName: allSourceSectionsExpanded ? "chevron.up.2" : "chevron.down.2")
                            .scaledFont(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(allSourceSectionsExpanded ? "收起所有 tab" : "展开所有 tab")
                    .accessibilityLabel(allSourceSectionsExpanded ? "收起所有 tab" : "展开所有 tab")
                }
            }

            Section("主题") {
                ForEach(SignalDomain.allCases) { domain in
                    topicRow(domain)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 280)
        .safeAreaInset(edge: .bottom) {
            Button {
                if section == .stocks {
                    showingAddStock = true
                } else if section == .qdiiQuotas {
                    showingAddQDII = true
                } else {
                    showingAddSource = true
                }
            } label: {
                Label(
                    section == .stocks ? "添加股票" : (section == .qdiiQuotas ? "添加基金" : "添加监控对象"),
                    systemImage: "plus"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(LinearGradient(colors: [.indigo, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .scaledFont(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("SignalDesk")
                    .scaledFont(.title3.weight(.bold))
                Text("重要人物情报台")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    "暂无匹配信号",
                    systemImage: "waveform.path.ecg",
                    description: Text("添加来源或调整筛选条件后刷新。")
                )
            } else {
                List(selection: $selection) {
                    ForEach(filteredEvents) { event in
                        eventRow(event)
                    }
                    .onDelete { offsets in
                        store.deleteEvents(offsets.map { filteredEvents[$0].id })
                        selection = nil
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 420, ideal: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedTopic.map { "\($0.title)主题" } ?? selectedSourceName ?? section?.title ?? "情报流")
                        .scaledFont(.largeTitle.weight(.bold))
                    Text(refreshSubtitle)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                if let selectedTopic {
                    Button {
                        self.selectedTopic = nil
                        selection = nil
                    } label: {
                        Label("清除 \(selectedTopic.title)筛选", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
                if let message = store.statusMessage {
                    Text(message)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(store.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
                Button("全部已读") { store.markAllRead() }
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索人物、观点或关键词", text: $query)
                    .textFieldStyle(.plain)
                Divider().frame(height: 18)
                Picker("类型", selection: $category) {
                    Text("全部类型").tag(SignalCategory?.none)
                    ForEach(SignalCategory.allCases) { item in
                        Text(item.title).tag(Optional(item))
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Divider().frame(height: 18)
                Text("排序")
                    .foregroundStyle(.secondary)
                Picker("排序", selection: sortBinding(for: section ?? .longForm)) {
                    ForEach(SignalSortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(20)
    }

    @ViewBuilder
    private var detail: some View {
        if section == .investors {
            ZStack(alignment: .topLeading) {
                Color(nsColor: .controlBackgroundColor)
                if selectedInvestorTab == .consensus {
                    InvestorConsensusView()
                } else {
                    InvestorPortfolioView(investorID: selectedInvestorID)
                }
            }
        } else if section == .dailyBrief {
            DailyBriefView(selection: $selectedDailyBriefID)
        } else if section == .stocks {
            if let update = selectedStockUpdate {
                StockUpdateDetail(update: update)
                    .onChange(of: update.id, initial: true) { _, updateID in
                        store.markStockUpdateRead(updateID)
                    }
            } else {
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    ContentUnavailableView(
                        "选择一条股票信息",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("从基本面、新闻或重要公告中选择一条信息查看详情。")
                    )
                }
            }
        } else if section == .qdiiQuotas {
            if let selectedQDIIID,
               let item = qdiiQuotaStore.watchlist.first(where: { $0.fundCode == selectedQDIIID }),
               item.market == .exchangeTraded {
                QDIIExchangeDetail(observation: qdiiQuotaStore.exchangeObservation(for: selectedQDIIID))
            } else {
                QDIIQuotaDetail(
                    tiantianObservation: selectedQDIIID.flatMap { qdiiQuotaStore.observation(for: $0, channel: .tiantian) },
                    directObservation: selectedQDIIID.flatMap { qdiiQuotaStore.observation(for: $0, channel: .direct) },
                    xueqiuObservation: selectedQDIIID.flatMap { qdiiQuotaStore.observation(for: $0, channel: .xueqiu) },
                    changes: qdiiQuotaStore.changes.filter { $0.fundCode == selectedQDIIID }
                )
            }
        } else if let event = selectedEvent {
            EventDetail(event: event)
                .onChange(of: event.id, initial: true) { _, eventID in
                    store.markRead(eventID)
                }
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                ContentUnavailableView(
                    "选择一条信号",
                    systemImage: "scope",
                    description: Text("查看摘要、价值评分与原始来源。")
                )
            }
        }
    }

    private var selectedEvent: SignalEvent? {
        guard let selection else { return nil }
        return store.events.first { $0.id == selection }
    }

    private var selectedStockUpdate: StockUpdate? {
        guard let selection else { return nil }
        return store.stockUpdates.first { $0.id == selection }
    }

    private var filteredEvents: [SignalEvent] {
        let filtered = store.events.filter { event in
            let sectionMatches: Bool
            switch section {
            case .xFeed:
                sectionMatches = xSourceIDs.contains(event.sourceID) &&
                    (selectedSourceGroupKey == nil || selectedSourceGroupKey == sourceGroupKey(for: event.sourceID))
            case .longForm:
                sectionMatches = longFormSourceIDs.contains(event.sourceID) &&
                    (selectedSourceGroupKey == nil || selectedSourceGroupKey == sourceGroupKey(for: event.sourceID))
            case .chinaEconomy:
                sectionMatches = chinaEconomySourceIDs.contains(event.sourceID) &&
                    ChinaEconomyRelevance.matches(title: event.title, summary: event.summary) &&
                    (selectedSourceGroupKey == nil || selectedSourceGroupKey == sourceGroupKey(for: event.sourceID))
            case .magazines:
                sectionMatches = magazineSourceIDs.contains(event.sourceID) &&
                    (selectedSourceGroupKey == nil || selectedSourceGroupKey == sourceGroupKey(for: event.sourceID))
            case .highValue: sectionMatches = event.importance >= 75
            case .bookmarks: sectionMatches = event.isBookmarked
            default: sectionMatches = true
            }
            let categoryMatches = category == nil || event.category == category
            let topicMatches = selectedTopic.map { event.domains?.contains($0) == true } ?? true
            let queryMatches = query.isEmpty ||
                "\(event.sourceName) \(event.title) \(event.summary) \(event.matchedTopics.joined(separator: " "))"
                .localizedCaseInsensitiveContains(query)
            return sectionMatches && categoryMatches && topicMatches && queryMatches
        }
        return sortOptions[section ?? .longForm, default: .updatedAt].sorted(filtered)
    }

    private func sortBinding(for section: AppSection) -> Binding<SignalSortOption> {
        Binding(
            get: { sortOptions[section, default: .updatedAt] },
            set: { sortOptions[section] = $0 }
        )
    }

    private var refreshSubtitle: String {
        let activeSourceCount: Int
        switch section {
        case .xFeed:
            activeSourceCount = store.sources.filter { $0.sourceKind == .x && $0.isEnabled }.count
        case .longForm:
            activeSourceCount = store.sources.filter { isLongFormSource($0) && $0.isEnabled }.count
        case .chinaEconomy:
            activeSourceCount = store.sources.filter { $0.channel == .chinaEconomy && $0.isEnabled }.count
        case .magazines:
            activeSourceCount = store.sources.filter { $0.channel == .magazines && $0.isEnabled }.count
        default:
            activeSourceCount = store.sources.filter(\.isEnabled).count
        }
        if let date = store.lastRefreshAt {
            return "上次刷新 \(date.formatted(date: .omitted, time: .shortened)) · \(activeSourceCount) 个活跃来源"
        }
        return "\(activeSourceCount) 个活跃来源"
    }

    private var xSourceIDs: Set<UUID> {
        Set(store.sources.filter { $0.sourceKind == .x }.map(\.id))
    }

    private var longFormSourceIDs: Set<UUID> {
        Set(store.sources.filter(isLongFormSource).map(\.id))
    }

    private func isLongFormSource(_ source: TrackedSource) -> Bool {
        source.sourceKind != .x && source.channel == nil
    }

    private var chinaEconomySourceIDs: Set<UUID> {
        Set(store.sources.filter { $0.channel == .chinaEconomy }.map(\.id))
    }

    private var magazineSourceIDs: Set<UUID> {
        Set(store.sources.filter { $0.channel == .magazines }.map(\.id))
    }

    private var selectedSourceName: String? {
        guard let selectedSourceGroupKey else { return nil }
        return sourceGroups(for: section ?? .longForm)
            .first(where: { $0.key == selectedSourceGroupKey })?.title
            ?? selectedSourceGroupKey
    }

    private func isSourceSection(_ section: AppSection) -> Bool {
        section == .xFeed || section == .longForm || section == .chinaEconomy || section == .magazines
    }

    private func sourceGroups(for section: AppSection) -> [SourceGroup] {
        let filteredSources: [TrackedSource]
        switch section {
        case .xFeed:
            filteredSources = store.sources.filter { $0.sourceKind == .x }
        case .longForm:
            filteredSources = store.sources.filter(isLongFormSource)
        case .chinaEconomy:
            filteredSources = store.sources.filter { $0.channel == .chinaEconomy }
        case .magazines:
            filteredSources = store.sources.filter { $0.channel == .magazines }
        default:
            filteredSources = []
        }
        let grouped = Dictionary(grouping: filteredSources, by: \.groupKey)
        return grouped.map { key, sources in
            SourceGroup(
                key: key,
                title: sources.first?.groupTitle ?? key,
                sources: sources.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
        .sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
    }

    private func selectSection(_ section: AppSection) {
        self.section = section
        if section == .stocks,
           selectedStockID == nil || !store.stockWatchlist.contains(where: { $0.id == selectedStockID }) {
            selectedStockID = store.stockWatchlist.first?.id
        }
        if section == .qdiiQuotas,
           selectedQDIIID == nil || !qdiiQuotaStore.watchlist.contains(where: { $0.fundCode == selectedQDIIID }) {
            selectedQDIIID = qdiiQuotaStore.watchlist.first?.fundCode
        }
        selectedSourceGroupKey = nil
        selection = nil
    }

    private func selectStock(_ stock: StockWatchlistItem) {
        section = .stocks
        selectedStockID = stock.id
        selectedSourceGroupKey = nil
        selection = nil
    }

    private func selectSourceGroup(_ groupKey: String, in section: AppSection) {
        self.section = section
        selectedSourceGroupKey = groupKey
        selection = nil
    }

    private func toggleSourceSection(_ section: AppSection) {
        if expandedSourceSections.contains(section) {
            expandedSourceSections.remove(section)
        } else {
            expandedSourceSections.insert(section)
        }
    }

    private var expandableSourceSections: Set<AppSection> {
        Set(AppSection.allCases.filter(isExpandableSourceSection))
    }

    private var allSourceSectionsExpanded: Bool {
        expandedSourceSections == expandableSourceSections
    }

    private func isExpandableSourceSection(_ section: AppSection) -> Bool {
        isSourceSection(section) || section == .stocks
    }

    private func toggleAllSourceSections() {
        expandedSourceSections = allSourceSectionsExpanded ? [] : expandableSourceSections
    }

    private func unreadCount(for group: SourceGroup) -> Int {
        store.events.filter { event in
            group.sources.contains { source in source.id == event.sourceID } && !event.isRead
        }.count
    }

    private func sourceGroupKey(for sourceID: UUID) -> String? {
        store.sources.first { $0.id == sourceID }?.groupKey
    }

    @ViewBuilder
    private func sectionLabel(_ item: AppSection) -> some View {
        HStack {
            Label {
                Text(item.title)
            } icon: {
                Image(systemName: item.icon)
                    .foregroundStyle(item == .highValue ? .orange : .blue)
            }
            Spacer()
            if let count = badgeCount(for: item), count > 0 {
                Text("\(count)")
                    .scaledFont(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func eventRow(_ event: SignalEvent) -> some View {
        EventRow(event: event)
            .tag(event.id)
            .contextMenu {
                Button(event.isBookmarked ? "取消收藏" : "收藏") {
                    store.toggleBookmark(event.id)
                }
                Button("删除信息", role: .destructive) {
                    store.deleteEvent(event.id)
                    if selection == event.id { selection = nil }
                }
                if let rawURL = event.url, let url = URL(string: rawURL) {
                    Button("打开原文") { openURL(url) }
                }
            }
    }

    private func deleteSelectedInformation() {
        switch section {
        case .stocks:
            guard let selection else { return }
            store.deleteStockUpdate(selection)
            self.selection = nil
        case .qdiiQuotas:
            guard let selectedQDIIID else { return }
            qdiiQuotaStore.removeFund(selectedQDIIID)
            self.selectedQDIIID = nil
        case .dailyBrief:
            guard let selectedDailyBriefID else { return }
            store.deleteDailyBrief(selectedDailyBriefID)
            self.selectedDailyBriefID = nil
        case .xFeed, .longForm, .chinaEconomy, .magazines, .highValue, .bookmarks:
            guard let selection else { return }
            store.deleteEvent(selection)
            self.selection = nil
        default:
            break
        }
    }

    private func badgeCount(for item: AppSection) -> Int? {
        switch item {
        case .xFeed:
            store.events.filter { xSourceIDs.contains($0.sourceID) && !$0.isRead }.count
        case .longForm:
            store.events.filter { longFormSourceIDs.contains($0.sourceID) && !$0.isRead }.count
        case .chinaEconomy:
            store.events.filter { chinaEconomySourceIDs.contains($0.sourceID) && !$0.isRead }.count
        case .magazines:
            store.events.filter { magazineSourceIDs.contains($0.sourceID) && !$0.isRead }.count
        case .stocks:
            store.stockUpdates.filter { !$0.isRead }.count
        case .qdiiQuotas:
            qdiiQuotaStore.changes.count
        case .highValue: store.highValueCount
        case .bookmarks: store.events.filter(\.isBookmarked).count
        case .dailyBrief: nil
        case .investors: InvestorPreset.featured.count
        case .sources: store.sources.count
        case .settings: nil
        }
    }

    private func topicRow(_ domain: SignalDomain) -> some View {
        Button {
            selectedTopic = selectedTopic == domain ? nil : domain
            section = .longForm
            selectedSourceGroupKey = nil
            selection = nil
        } label: {
            HStack {
                Circle().fill(topicColor(domain)).frame(width: 7, height: 7)
                Text(domain.title)
                Spacer()
                Text("\(store.events.filter { $0.domains?.contains(domain) == true }.count)")
                    .scaledFont(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if selectedTopic == domain {
                    Image(systemName: "checkmark")
                        .scaledFont(.caption.weight(.semibold))
                        .foregroundStyle(topicColor(domain))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selectedTopic == domain ? topicColor(domain).opacity(0.12) : Color.clear
        )
    }

    private func topicColor(_ domain: SignalDomain) -> Color {
        switch domain {
        case .modelsAgents: .purple
        case .robotics: .cyan
        case .compute: .blue
        case .investmentBusiness: .green
        }
    }
}

private struct SourceGroup: Identifiable {
    let key: String
    let title: String
    let sources: [TrackedSource]

    var id: String { key }
}

private struct EventRow: View {
    let event: SignalEvent

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Circle()
                .fill(event.isRead ? Color.clear : Color.blue)
                .frame(width: 7, height: 7)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(event.sourceName)
                        .scaledFont(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Label(event.category.title, systemImage: event.category.icon)
                        .scaledFont(.caption2.weight(.medium))
                        .foregroundStyle(categoryColor)
                    Spacer()
                    Text(event.publishedAt, format: .relative(presentation: .named))
                        .scaledFont(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(event.title)
                    .scaledFont(.headline)
                    .lineLimit(2)
                if !event.summary.isEmpty {
                    Text(event.summary)
                        .scaledFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    ScorePill(score: event.importance)
                    ForEach(event.matchedTopics.prefix(3), id: \.self) { topic in
                        Text(topic)
                            .scaledFont(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    if event.isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var categoryColor: Color {
        switch event.category {
        case .viewpoint: .purple
        case .activity: .blue
        case .holding: .green
        }
    }
}

private struct ScorePill: View {
    let score: Int

    var body: some View {
        Text("\(score) 分")
            .scaledFont(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        score >= 80 ? .orange : (score >= 60 ? .blue : .secondary)
    }
}

private struct EventDetail: View {
    @EnvironmentObject private var store: SignalStore
    @Environment(\.openURL) private var openURL
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var isTranslating = false
    @State private var translationError: String?
    let event: SignalEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label(event.category.title, systemImage: event.category.icon)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button {
                        store.toggleBookmark(event.id)
                    } label: {
                        Image(systemName: event.isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(event.title)
                        .scaledFont(.title.weight(.bold))
                        .textSelection(.enabled)
                    HStack(spacing: 0) {
                        if let profile = PersonProfileCatalog.profile(forSourceName: event.sourceName) {
                            PersonHoverName(
                                title: eventPersonName,
                                profile: profile
                            )
                        } else {
                            Text(event.sourceName)
                        }
                        Text(" · \(event.publishedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 14) {
                    metric(title: "价值评分", value: "\(event.importance)", color: .orange)
                    metric(title: "命中主题", value: "\(event.matchedTopics.count)", color: .purple)
                }

                if !event.matchedTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("命中主题").scaledFont(.headline)
                        HStack {
                            ForEach(event.matchedTopics, id: \.self) { topic in
                                Text(topic)
                                    .scaledFont(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.blue.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("来源摘要").scaledFont(.headline)
                    Text(event.summary.isEmpty ? "该来源未提供摘要，请打开原文查看。" : event.summary)
                        .scaledFont(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("AI 中文翻译", systemImage: "character.book.closed.fill")
                            .scaledFont(.headline)
                        Spacer()
                        if let translation = event.aiTranslation {
                            Text(translation.provider.title)
                                .scaledFont(.caption)
                                .foregroundStyle(.secondary)
                            Button("重新翻译") {
                                store.clearTranslation(for: event.id)
                                Task { await generateTranslation() }
                            }
                            .scaledFont(.caption)
                            .disabled(isTranslating)
                        }
                    }

                    if let translation = event.aiTranslation {
                        MarkdownText(translation.content)
                            .scaledFont(.body)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                        Text("翻译于 \(translation.generatedAt.formatted(date: .abbreviated, time: .shortened)) · AI 翻译可能有误，请结合原文核验")
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if isTranslating {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在抓取正文并翻译为中文…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let translationError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(translationError, systemImage: "exclamationmark.triangle.fill")
                                .scaledFont(.subheadline)
                                .foregroundStyle(.orange)
                            Button("重试") {
                                Task { await generateTranslation() }
                            }
                        }
                    } else {
                        Button {
                            Task { await generateTranslation() }
                        } label: {
                            Label("翻译为中文", systemImage: "character.book.closed.fill")
                        }
                    }
                }
                .padding(16)
                .background(.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            AISummaryService.canSummarize(event)
                                ? "AI 情报总结（详细版）"
                                : "AI 情报总结（暂不支持媒体内容）",
                            systemImage: "sparkles"
                        )
                            .scaledFont(.headline)
                        Spacer()
                        if AISummaryService.canSummarize(event), let summary = event.aiSummary {
                            Text(summary.provider.title)
                                .scaledFont(.caption)
                                .foregroundStyle(.secondary)
                            Button(summary.isDetailedFormat ? "重新生成详细版" : "生成详细版") {
                                store.clearSummary(for: event.id)
                                Task { await generateSummary() }
                            }
                            .scaledFont(.caption)
                            .disabled(isSummarizing)
                        }
                    }

                    if !AISummaryService.canSummarize(event) {
                        Label(
                            "当前只能总结抓取到正文的文章；播客和视频需要完整字幕或文字稿。",
                            systemImage: "info.circle"
                        )
                        .scaledFont(.subheadline)
                        .foregroundStyle(.secondary)
                        if let summary = event.aiSummary {
                            Text("已保存的历史总结")
                                .scaledFont(.caption)
                                .foregroundStyle(.secondary)
                            MarkdownText(summary.content)
                                .scaledFont(.body)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                        }
                    } else if let summary = event.aiSummary {
                        if !summary.isDetailedFormat {
                            Label("这是旧版简摘要，点击上方按钮可按完整材料重新生成。", systemImage: "info.circle")
                                .scaledFont(.caption)
                                .foregroundStyle(.orange)
                        }
                        MarkdownText(summary.content)
                            .scaledFont(.body)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                        Text("生成于 \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened)) · AI 内容可能有误，请结合原始来源核验")
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if isSummarizing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在抓取正文并生成中文总结…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let summaryError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(summaryError, systemImage: "exclamationmark.triangle.fill")
                                .scaledFont(.subheadline)
                                .foregroundStyle(.orange)
                            Button("重试") {
                                Task { await generateSummary() }
                            }
                        }
                    } else {
                        Button {
                            Task { await generateSummary() }
                        } label: {
                            Label("生成详细 AI 总结", systemImage: "sparkles")
                        }
                    }
                }
                .padding(16)
                .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                if let rawURL = event.url, let url = URL(string: rawURL) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("打开原始来源", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()
            }
            .padding(28)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task(id: event.id) {
            guard event.importance >= AISummaryService.automaticSummaryImportanceThreshold,
                  AISummaryService.canSummarize(event),
                  event.aiSummary == nil else {
                return
            }
            await generateSummary()
        }
    }

    @MainActor
    private func generateSummary() async {
        guard !isSummarizing else { return }
        guard AISummaryService.canSummarize(event) else {
            summaryError = AISummaryError.mediaNotSupported.localizedDescription
            return
        }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }

        do {
            let summary = try await AISummaryService().summarize(event)
            store.saveSummary(summary, for: event.id)
        } catch {
            summaryError = error.localizedDescription
        }
    }

    @MainActor
    private func generateTranslation() async {
        guard !isTranslating else { return }
        isTranslating = true
        translationError = nil
        defer { isTranslating = false }

        do {
            let translation = try await AISummaryService().translate(event)
            store.saveTranslation(translation, for: event.id)
        } catch {
            translationError = error.localizedDescription
        }
    }

    private var eventPersonName: String {
        event.sourceName.components(separatedBy: " · ").first ?? event.sourceName
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .scaledFont(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

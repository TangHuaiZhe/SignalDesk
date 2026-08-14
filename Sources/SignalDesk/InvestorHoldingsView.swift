import AppKit
import SwiftUI

enum InvestorPageTab: String, CaseIterable, Identifiable {
    case investors
    case consensus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .investors: "投资者"
        case .consensus: "持仓共识"
        }
    }
}

private enum InvestorDetailTab: String, CaseIterable, Identifiable {
    case holdings
    case writings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdings: "持仓"
        case .writings: "观点与信件"
        }
    }
}

struct InvestorListView: View {
    @EnvironmentObject private var store: InvestorHoldingsStore
    @Binding var selection: String?
    @Binding var selectedTab: InvestorPageTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("杰出投资者")
                        .scaledFont(.largeTitle.weight(.bold))
                    Text("季度持仓、共识信号、基金信与投资观点")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label(
                        store.isRefreshingAll ? "刷新全部中" : "刷新全部持仓",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.refreshingInvestorID != nil || store.isRefreshingAll)
            }

            Picker("查看内容", selection: $selectedTab) {
                ForEach(InvestorPageTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            List(InvestorPreset.featured, selection: $selection) { investor in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(investor.name)
                            .scaledFont(.headline)
                        Spacer()
                        if let portfolio = store.portfolio(for: investor.id) {
                            Text(portfolio.reportDate)
                                .scaledFont(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(investor.firm)
                        .scaledFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(investor.style)
                        .scaledFont(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    if investor.holdingsKind == .chineseFund {
                        Text("基金季报前十大持仓")
                            .scaledFont(.caption2)
                            .foregroundStyle(.blue)
                    } else if investor.holdingsKind == .unavailable {
                        Text("持仓暂无连续公开披露")
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 7)
                .tag(investor.id)
            }
            .listStyle(.inset)
        }
        .navigationSplitViewColumnWidth(min: 270, ideal: 320, max: 380)
    }
}

struct InvestorPortfolioView: View {
    @EnvironmentObject private var store: InvestorHoldingsStore
    @EnvironmentObject private var writingStore: InvestorWritingStore
    @State private var selectedTab = InvestorDetailTab.holdings
    @State private var selectedWritingID: String?
    let investorID: String?

    private var investor: InvestorPreset? {
        InvestorPreset.featured.first { $0.id == investorID }
    }

    var body: some View {
        if let investor {
            VStack(spacing: 0) {
                portfolioHeader(investor)
                Divider()
                if selectedTab == .holdings {
                    portfolioContent(investor)
                } else {
                    writingsContent(investor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: investorID) {
                selectedWritingID = writingStore.writings(for: investor.id).first?.id
            }
            .task(id: investorID) {
                await store.refreshIfStale(investor)
                await store.loadChineseNames(for: investor.id)
            }
        } else {
            ContentUnavailableView(
                "选择一位投资者",
                systemImage: "chart.pie",
                description: Text("查看最近一期 13F 持仓和长期收益指标。")
            )
        }
    }

    private func portfolioHeader(_ investor: InvestorPreset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    PersonHoverName(
                        title: investor.name,
                        profile: PersonProfileCatalog.profile(for: investor)
                    )
                    .scaledFont(.largeTitle.weight(.bold))
                    Text("\(investor.firm) · \(investor.style)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedTab == .holdings {
                    Button {
                        Task { await store.refresh(investor) }
                    } label: {
                        Label(
                            store.refreshingInvestorID == investor.id ? "刷新中" : "刷新持仓",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.refreshingInvestorID != nil || store.isRefreshingAll)
                } else if selectedTab == .writings {
                    Button {
                        Task { await writingStore.refresh(investor) }
                    } label: {
                        Label(
                            writingStore.refreshingInvestorID == investor.id ? "刷新中" : "刷新观点",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(writingStore.refreshingInvestorID != nil)
                }
            }

            Picker("查看内容", selection: $selectedTab) {
                ForEach(InvestorDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            if selectedTab == .holdings {
                HStack(spacing: 8) {
                    if investor.holdingsKind == .sec13F {
                        Label("SEC EDGAR", systemImage: "building.columns")
                        Text("季度末快照，最长可能滞后约 45 天")
                    } else if investor.holdingsKind == .chineseFund {
                        Label("基金季报", systemImage: "building.columns")
                        Text("公开前十大持仓，非完整组合")
                    } else {
                        Label("公开披露", systemImage: "questionmark.folder")
                        Text("当前没有可核验的公开持仓")
                    }
                    if let portfolio = store.portfolio(for: investor.id) {
                        Text("·")
                        Text("报告期 \(portfolio.reportDate)")
                        Text("·")
                        Text("申报 \(portfolio.filingDate)")
                    }
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)

                if store.refreshingInvestorID == investor.id {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(
                            value: store.totalMarketSymbols > 0
                                ? Double(store.completedMarketSymbols)
                                : nil,
                            total: store.totalMarketSymbols > 0
                                ? Double(store.totalMarketSymbols)
                                : 1
                        )
                        Text(store.statusMessage ?? "正在更新…")
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if store.statusInvestorID == investor.id,
                          let message = store.statusMessage {
                    Text(message)
                        .scaledFont(.caption)
                        .foregroundStyle(message.hasPrefix("刷新失败") ? .red : .secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Label("官方原文优先", systemImage: "checkmark.seal")
                    Text("区分本人署名与基金团队材料；AI 仅在点击后解析")
                    if let archive = InvestorWritingCatalog.archiveURL(for: investor.id) {
                        Link("官方档案", destination: archive)
                    }
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)

                if writingStore.statusInvestorID == investor.id,
                   let message = writingStore.statusMessage {
                    Text(message)
                    .scaledFont(.caption)
                    .foregroundStyle(message.hasPrefix("观点刷新失败") ? .red : .secondary)
                }
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private func portfolioContent(_ investor: InvestorPreset) -> some View {
        if let portfolio = store.portfolio(for: investor.id) {
            VStack(spacing: 0) {
                portfolioSummary(portfolio)
                Divider()
                holdingsTable(portfolio)
                metricFootnote
            }
        } else {
            ContentUnavailableView {
                Label("尚未读取持仓", systemImage: "tray")
            } description: {
                if investor.holdingsKind == .sec13F {
                    Text("SEC 13F 无需 API Key；先读取申报即可查看持仓和占比。")
                } else if investor.holdingsKind == .chineseFund {
                    Text("将读取基金季报公开的前十大股票持仓；数据不是完整组合。")
                } else {
                    Text("目前没有连续、可核验的公开持仓披露，因此不填充猜测数据。")
                }
            } actions: {
                if investor.holdingsKind != .unavailable {
                    Button(investor.holdingsKind == .chineseFund ? "读取最新基金季报" : "读取最新 13F") {
                        Task { await store.refresh(investor) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.refreshingInvestorID != nil || store.isRefreshingAll)
                }
            }
        }
    }

    private func portfolioSummary(_ portfolio: InvestorPortfolio) -> some View {
        HStack(spacing: 26) {
            summaryMetric("申报总值", money(portfolio.totalValueUSD, currencyCode: portfolio.currencyCode))
            summaryMetric("持仓数量", "\(portfolio.positions.count)")
            summaryMetric(
                "已补全行情",
                "\(portfolio.positions.filter { $0.latestPrice != nil }.count)"
            )
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("更新于 \(portfolio.refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                Text("缓存有效期 30 天")
            }
                .scaledFont(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func writingsContent(_ investor: InvestorPreset) -> some View {
        let writings = writingStore.writings(for: investor.id)
        if writings.isEmpty {
            ContentUnavailableView {
                Label("暂无稳定公开基金信", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("这不代表投资者没有观点；只是目前没有可稳定核验、可公开访问的本人或基金官方信件来源。")
            } actions: {
                Button("检查官方来源") {
                    Task { await writingStore.refresh(investor) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(writingStore.refreshingInvestorID != nil)
            }
        } else {
            HSplitView {
                List(selection: $selectedWritingID) {
                    ForEach(writings) { writing in
                        WritingRow(writing: writing)
                            .tag(writing.id)
                            .contextMenu {
                                Button("删除材料", role: .destructive) {
                                    writingStore.deleteWriting(id: writing.id, investorID: investor.id)
                                    if selectedWritingID == writing.id { selectedWritingID = nil }
                                }
                            }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { writings[$0].id }
                        ids.forEach {
                            writingStore.deleteWriting(id: $0, investorID: investor.id)
                        }
                        selectedWritingID = nil
                    }
                }
                .listStyle(.inset)
                .frame(minWidth: 270, idealWidth: 330, maxWidth: 390)

                if let writing = selectedWriting(in: writings) {
                    InvestorWritingDetail(writing: writing)
                        .id(writing.id)
                } else {
                    ContentUnavailableView(
                        "选择一份材料",
                        systemImage: "doc.text",
                        description: Text("查看署名、原始来源，并按需生成 AI 总结。")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDeleteCommand {
                guard let selectedWritingID else { return }
                writingStore.deleteWriting(id: selectedWritingID, investorID: investor.id)
                self.selectedWritingID = nil
            }
            .onAppear {
                if selectedWriting(in: writings) == nil {
                    selectedWritingID = writings.first?.id
                }
            }
        }
    }

    private func selectedWriting(in writings: [InvestorWriting]) -> InvestorWriting? {
        guard let selectedWritingID else { return nil }
        return writings.first { $0.id == selectedWritingID }
    }

    private func holdingsTable(_ portfolio: InvestorPortfolio) -> some View {
        Table(portfolio.positions) {
            TableColumn("持仓") { position in
                Group {
                    if let url = position.xueqiuURL {
                        Link(destination: url) {
                            holdingIdentity(position, showsExternalLink: true)
                        }
                        .buttonStyle(.plain)
                        .help("在雪球打开 \(position.ticker ?? position.issuer)")
                    } else {
                        holdingIdentity(position, showsExternalLink: false)
                    }
                }
                .contextMenu {
                    if let localizedName = position.chineseName {
                        Button("复制中文名") {
                            copyToPasteboard(localizedName)
                        }
                    }
                    Button("复制英文公司名") {
                        copyToPasteboard(position.issuer)
                    }
                }
            }
            .width(min: 190, ideal: 270)

            TableColumn("占比") { position in
                numericText(percent(position.portfolioWeight))
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("股数") { position in
                numericText(shares(position.shares))
            }
            .width(min: 70, ideal: 85, max: 100)

            TableColumn("申报价值") { position in
                numericText(money(position.valueUSD, currencyCode: portfolio.currencyCode))
            }
            .width(min: 78, ideal: 92, max: 110)

            TableColumn("估算成本") { position in
                VStack(alignment: .trailing, spacing: 2) {
                    Text(position.estimatedCost.map(currency) ?? "—")
                        .monospacedDigit()
                    if let confidence = position.costConfidence {
                        Text(confidence.title)
                            .scaledFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 82, ideal: 96, max: 110)

            TableColumn("估算盈亏") { position in
                returnText(position.estimatedProfitLoss)
            }
            .width(min: 70, ideal: 80, max: 90)

            TableColumn("1 年") { position in
                returnText(position.returns.oneYear)
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("3 年") { position in
                returnText(position.returns.threeYears)
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("5 年") { position in
                returnText(position.returns.fiveYears)
            }
            .width(min: 55, ideal: 65, max: 75)

            TableColumn("10 年") { position in
                returnText(position.returns.tenYears)
            }
            .width(min: 55, ideal: 65, max: 75)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func holdingIdentity(
        _ position: InvestorPosition,
        showsExternalLink: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(position.ticker ?? position.cusip)
                    .scaledFont(.headline.monospaced())
                if let localizedName = position.chineseName {
                    Text(localizedName)
                        .scaledFont(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                if let putCall = position.putCall {
                    Text(putCall.uppercased())
                        .scaledFont(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                }
                if showsExternalLink {
                    Image(systemName: "arrow.up.right.square")
                        .scaledFont(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Text(position.issuer)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var metricFootnote: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("估算成本：历史股数先按拆股追溯调整，再按过去约 5 年季度增仓量和当期价格加权；减仓不重置成本。")
            Text("估算盈亏及 1/3/5/10 年 CAGR 使用拆股复权价格，不含股息；期权、无法映射或历史不足时显示“—”。")
        }
        .scaledFont(.caption2)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35))
    }

    private func summaryMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .scaledFont(.headline.monospacedDigit())
            Text(label)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func numericText(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func returnText(_ value: Double?) -> some View {
        Text(value.map(percent) ?? "—")
            .fontWeight(value.map { abs($0) >= 0.2 } == true ? .semibold : .regular)
            .foregroundStyle(returnColor(value))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func returnColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .primary
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    private func money(_ value: Int64, currencyCode: String = "USD") -> String {
        let symbol = currencyCode == "CNY" ? "¥" : "$"
        if value >= 1_000_000_000 {
            return symbol + (Double(value) / 1_000_000_000).formatted(
                .number.precision(.fractionLength(1))
            ) + "B"
        }
        if value >= 1_000_000 {
            return symbol + (Double(value) / 1_000_000).formatted(
                .number.precision(.fractionLength(1))
            ) + "M"
        }
        return symbol + value.formatted(.number)
    }

    private func shares(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
}

struct InvestorConsensusView: View {
    @EnvironmentObject private var store: InvestorHoldingsStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("持仓共识")
                        .scaledFont(.largeTitle.weight(.bold))
                    Text("聚合杰出投资者最近两期 SEC 13F 的买入与卖出变化")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Label(
                        store.isRefreshingAll ? "刷新全部中" : "刷新全部持仓",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.refreshingInvestorID != nil || store.isRefreshingAll)
            }
            .padding(22)

            HStack(spacing: 8) {
                Label("SEC 13F 变化", systemImage: "arrow.triangle.2.circlepath")
                Text("基于最近两期申报；不是实时持仓")
                Text("·")
                Text("已加载 \(store.portfolios.count)/\(InvestorPreset.featured.count) 位投资者")
                if let message = store.statusMessage {
                    Text("·")
                    Text(message)
                }
            }
            .scaledFont(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            Divider()
            consensusContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await store.refreshAllIfStale()
        }
    }

    @ViewBuilder
    private var consensusContent: some View {
        let consensus = InvestorConsensusBuilder.build(
            investors: InvestorPreset.featured,
            portfolios: store.portfolios
        )

        if consensus.isEmpty {
            ContentUnavailableView {
                Label("暂无持仓变化共识", systemImage: "chart.bar.xaxis")
            } description: {
                Text("请先刷新全部持仓；系统需要至少两期 SEC 13F 才能识别增持、减持、新增或清仓。")
            } actions: {
                Button("刷新全部持仓") {
                    Task { await store.refreshAll() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.refreshingInvestorID != nil || store.isRefreshingAll)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(consensus) { item in
                        consensusRow(item)
                        Divider()
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private func consensusRow(_ item: InvestorConsensus) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.ticker ?? item.cusip)
                    .scaledFont(.headline.monospaced())
                if let localizedName = item.localizedName,
                   localizedName.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
                    Text(localizedName)
                        .scaledFont(.headline.weight(.medium))
                }
                Text(item.issuer)
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(item.signalTitle)
                    .scaledFont(.caption.weight(.bold))
                    .foregroundStyle(consensusColor(item))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(consensusColor(item).opacity(0.12), in: Capsule())
            }

            HStack(spacing: 14) {
                Text("当前持有 \(item.holderCount) 位")
                Text("合计占比 \(percent(item.aggregateWeight))")
                if item.latestValueUSD > 0,
                   let currencyCode = item.currencyCode {
                    Text("申报值 \(money(item.latestValueUSD, currencyCode: currencyCode))")
                }
            }
            .scaledFont(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                if !item.buyers.isEmpty {
                    Label("买入：\(item.buyers.joined(separator: "、"))", systemImage: "arrow.up.right")
                        .foregroundStyle(.red)
                }
                if !item.sellers.isEmpty {
                    Label("卖出：\(item.sellers.joined(separator: "、"))", systemImage: "arrow.down.right")
                        .foregroundStyle(.green)
                }
            }
            .scaledFont(.caption)
        }
        .padding(.vertical, 14)
        .textSelection(.enabled)
        .contextMenu {
            if let ticker = item.ticker {
                Button("复制代码") { copyToPasteboard(ticker) }
            }
            Button("复制英文公司名") { copyToPasteboard(item.issuer) }
        }
    }

    private func consensusColor(_ item: InvestorConsensus) -> Color {
        if item.buyers.count >= item.sellers.count, !item.buyers.isEmpty { return .red }
        if !item.sellers.isEmpty { return .green }
        return .secondary
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func money(_ value: Int64, currencyCode: String) -> String {
        let symbol = currencyCode == "CNY" ? "¥" : "$"
        if value >= 1_000_000_000 {
            return symbol + (Double(value) / 1_000_000_000).formatted(
                .number.precision(.fractionLength(1))
            ) + "B"
        }
        if value >= 1_000_000 {
            return symbol + (Double(value) / 1_000_000).formatted(
                .number.precision(.fractionLength(1))
            ) + "M"
        }
        return symbol + value.formatted(.number)
    }
}

private struct WritingRow: View {
    let writing: InvestorWriting

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(writing.kind.title, systemImage: writing.kind.icon)
                    .scaledFont(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Text(writing.displaysYearOnly == true
                    ? writing.period ?? writing.publishedAt.formatted(.dateTime.year())
                    : writing.publishedAt.formatted(.dateTime.year().month().day()))
                    .scaledFont(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(writing.title)
                .scaledFont(.headline)
                .lineLimit(3)
            HStack(spacing: 6) {
                Text(writing.author)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(writing.attribution.title)
                    .scaledFont(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        writing.attribution == .namedAuthor
                            ? Color.green.opacity(0.12)
                            : Color.orange.opacity(0.12),
                        in: Capsule()
                    )
                Spacer()
                if writing.aiSummary != nil {
                    Image(systemName: "sparkles")
                        .scaledFont(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(.vertical, 7)
    }
}

private struct InvestorWritingDetail: View {
    @EnvironmentObject private var store: InvestorWritingStore
    @Environment(\.openURL) private var openURL
    @State private var isSummarizing = false
    @State private var summaryError: String?
    @State private var isTranslating = false
    @State private var translationError: String?
    let writing: InvestorWriting

    private var currentWriting: InvestorWriting {
        store.writing(id: writing.id, investorID: writing.investorID) ?? writing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(currentWriting.kind.title, systemImage: currentWriting.kind.icon)
                        .foregroundStyle(.blue)
                    Text(currentWriting.attribution.title)
                        .scaledFont(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(attributionColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(attributionColor)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(currentWriting.title)
                        .scaledFont(.title2.weight(.bold))
                        .textSelection(.enabled)
                    HStack(spacing: 0) {
                        if let profile = PersonProfileCatalog.profile(forSourceName: currentWriting.author) {
                            PersonHoverName(
                                title: currentWriting.author,
                                profile: profile
                            )
                        } else {
                            Text(currentWriting.author)
                        }
                        Text(" · \(currentWriting.publisher)")
                    }
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
                    if let period = currentWriting.period {
                        Text(
                            currentWriting.displaysYearOnly == true
                                ? "报告年份 \(period)"
                                : "报告期 \(period) · "
                                    + currentWriting.publishedAt.formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    )
                        )
                            .scaledFont(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(
                            currentWriting.publishedAt.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                        .scaledFont(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("来源归属")
                        .scaledFont(.headline)
                    Text(currentWriting.sourceNote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("AI 中文翻译", systemImage: "character.book.closed.fill")
                            .scaledFont(.headline)
                        Spacer()
                        if let translation = currentWriting.aiTranslation {
                            Text(translation.provider.title)
                                .scaledFont(.caption)
                                .foregroundStyle(.secondary)
                            Button("重新翻译") {
                                store.clearTranslation(
                                    writingID: currentWriting.id,
                                    investorID: currentWriting.investorID
                                )
                                Task { await generateTranslation() }
                            }
                            .scaledFont(.caption)
                            .disabled(isTranslating)
                        }
                    }

                    if let translation = currentWriting.aiTranslation {
                        MarkdownText(translation.content)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                        Text(
                            "翻译于 \(translation.generatedAt.formatted(date: .abbreviated, time: .shortened))"
                                + " · AI 翻译可能有误，请结合原文核验"
                        )
                        .scaledFont(.caption2)
                        .foregroundStyle(.tertiary)
                    } else if isTranslating {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在读取原文并翻译为中文…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let translationError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(translationError, systemImage: "exclamationmark.triangle.fill")
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
                        Label("AI 投资分析（详细版）", systemImage: "sparkles")
                            .scaledFont(.headline)
                        Spacer()
                        if let summary = currentWriting.aiSummary {
                            Text(summary.provider.title)
                                .scaledFont(.caption)
                                .foregroundStyle(.secondary)
                            Button(summary.isDetailedFormat ? "重新生成详细版" : "生成详细版") {
                                store.clearSummary(
                                    writingID: currentWriting.id,
                                    investorID: currentWriting.investorID
                                )
                                Task { await generateSummary() }
                            }
                            .scaledFont(.caption)
                            .disabled(isSummarizing)
                        }
                    }

                    if let summary = currentWriting.aiSummary {
                        if !summary.isDetailedFormat {
                            Label("这是旧版简摘要，点击上方按钮可按完整材料重新生成。", systemImage: "info.circle")
                                .scaledFont(.caption)
                                .foregroundStyle(.orange)
                        }
                        MarkdownText(summary.content)
                            .lineSpacing(6)
                            .textSelection(.enabled)
                        Text(
                            "生成于 \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))"
                                + " · AI 内容可能有误，请结合原文和 13F 核验"
                        )
                        .scaledFont(.caption2)
                        .foregroundStyle(.tertiary)
                    } else if isSummarizing {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在读取原文并分析投资观点…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let summaryError {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(summaryError, systemImage: "exclamationmark.triangle.fill")
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

                Button {
                    if let url = URL(string: currentWriting.sourceURL) {
                        openURL(url)
                    }
                } label: {
                    Label("打开官方原文", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var attributionColor: Color {
        currentWriting.attribution == .namedAuthor ? .green : .orange
    }

    @MainActor
    private func generateSummary() async {
        guard !isSummarizing else { return }
        isSummarizing = true
        summaryError = nil
        defer { isSummarizing = false }

        do {
            let summary = try await AISummaryService().summarize(currentWriting)
            store.saveSummary(
                summary,
                writingID: currentWriting.id,
                investorID: currentWriting.investorID
            )
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
            let translation = try await AISummaryService().translate(currentWriting)
            store.saveTranslation(
                translation,
                writingID: currentWriting.id,
                investorID: currentWriting.investorID
            )
        } catch {
            translationError = error.localizedDescription
        }
    }
}

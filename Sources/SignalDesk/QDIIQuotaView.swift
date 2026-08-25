import SwiftUI

struct QDIIQuotaView: View {
    @EnvironmentObject private var store: QDIIQuotaStore
    @Environment(\.openURL) private var openURL
    @Binding var selection: String?
    @Binding var showingAddFund: Bool
    @State private var selectedMarket: QDIIFundMarket = .overTheCounter

    private var sortedItems: [QDIIQuotaWatchItem] {
        let items = store.watchlist.filter { $0.market == selectedMarket }
        return items.sorted { lhs, rhs in
            if selectedMarket == .exchangeTraded {
                let left = store.exchangeObservation(for: lhs.fundCode)
                let right = store.exchangeObservation(for: rhs.fundCode)
                if QDIIExchangeObservation.comesBeforeByPremium(left, right) { return true }
                if QDIIExchangeObservation.comesBeforeByPremium(right, left) { return false }
                return lhs.fundCode < rhs.fundCode
            }
            let left = store.observation(for: lhs.fundCode)
            let right = store.observation(for: rhs.fundCode)
            if QDIIQuotaObservation.comesBeforeByPurchaseQuota(left, right) { return true }
            if QDIIQuotaObservation.comesBeforeByPurchaseQuota(right, left) { return false }
            return lhs.fundCode < rhs.fundCode
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if sortedItems.isEmpty {
                ContentUnavailableView(
                    "还没有\(selectedMarket.title)",
                    systemImage: selectedMarket == .exchangeTraded ? "chart.line.uptrend.xyaxis" : "chart.bar.doc.horizontal",
                    description: Text(selectedMarket == .exchangeTraded ? "添加场内 ETF / LOF 代码后刷新行情。" : "添加场外基金代码后刷新额度。")
                )
            } else {
                List(selection: $selection) {
                    ForEach(sortedItems) { item in
                        Group {
                            if item.market == .exchangeTraded {
                                QDIIExchangeRow(item: item, observation: store.exchangeObservation(for: item.fundCode))
                            } else {
                                QDIIQuotaRow(
                                    item: item,
                                    tiantianObservation: store.observation(for: item.fundCode, channel: .tiantian),
                                    directObservation: store.observation(for: item.fundCode, channel: .direct),
                                    xueqiuObservation: store.observation(for: item.fundCode, channel: .xueqiu)
                                )
                            }
                        }
                            .tag(item.fundCode)
                            .contextMenu {
                                Button(item.isEnabled ? "暂停监控" : "恢复监控") { store.toggle(item) }
                                Button("删除基金", role: .destructive) {
                                    store.removeFund(item.fundCode)
                                    if selection == item.fundCode { selection = nil }
                                }
                                let sourceURL = item.market == .exchangeTraded
                                    ? store.exchangeObservation(for: item.fundCode)?.sourceURL
                                    : store.observation(for: item.fundCode)?.sourceURL
                                if let urlString = sourceURL,
                                   let url = URL(string: urlString) {
                                    Button("打开数据来源") { openURL(url) }
                                }
                            }
                    }
                    .onDelete { offsets in
                        let items = offsets.map { sortedItems[$0] }
                        items.forEach { store.removeFund($0.fundCode) }
                        selection = nil
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 450, ideal: 570)
        .onChange(of: selectedMarket) { _, market in
            if let selection, !store.watchlist.contains(where: { $0.fundCode == selection && $0.market == market }) {
                self.selection = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("QDII 基金额度")
                        .scaledFont(.largeTitle.weight(.bold))
                    Text(selectedMarket == .exchangeTraded ? "场内 ETF / LOF 行情 · 按溢价率排序" : "对比基金公司直销、天天基金和雪球的单日累计购买上限 · 辅助源，仅供核验")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingAddFund = true } label: {
                    Label("添加基金", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(store.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
            Picker("基金市场", selection: $selectedMarket) {
                ForEach(QDIIFundMarket.allCases) { market in
                    Text("\(market.title) · \(market.subtitle)").tag(market)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Text(store.statusMessage ?? (selectedMarket == .exchangeTraded ? "关注价格、涨跌幅和成交额变化" : "关注额度上调、恢复申购或解除限购"))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastRefreshAt = store.lastRefreshAt {
                    Text("更新于 \(lastRefreshAt.formatted(date: .omitted, time: .shortened))")
                        .scaledFont(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
    }
}

private struct QDIIExchangeRow: View {
    let item: QDIIQuotaWatchItem
    let observation: QDIIExchangeObservation?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.blue.opacity(0.13))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.blue)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(observation?.fundName ?? (item.fundName.isEmpty ? "基金 \(item.fundCode)" : item.fundName))
                        .scaledFont(.body.weight(.semibold))
                        .lineLimit(2)
                    if observation?.isLowFeeRate == true {
                        Text("低费率")
                            .scaledFont(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(observation?.premiumRateTitle ?? "溢价率待刷新")
                            .scaledFont(.headline.monospacedDigit())
                            .foregroundStyle(premiumColor)
                        Text(observation?.premiumRateIsEstimated == true ? "参考溢价率" : "溢价率")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("最新价 \(observation?.priceTitle ?? "待刷新")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("净值/IOPV \(observation?.netAssetValueTitle ?? "待刷新")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("成交额 \(observation?.turnoverTitle ?? "待刷新")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("综合费率 \(observation?.comprehensiveFeeTitle ?? "待刷新")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.fundCode).scaledFont(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(observation?.premiumRateSourceTitle ?? "溢价率待刷新")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    Text("涨跌幅 \(observation?.changePercentTitle ?? "待刷新")")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    Text("换手率 \(observation?.turnoverRateTitle ?? "待刷新")")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                    if let date = observation?.observedAt {
                        Text("观测 \(date.formatted(date: .omitted, time: .shortened))")
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .opacity(item.isEnabled ? 1 : 0.5)
    }

    private var premiumColor: Color {
        guard let observation else { return .secondary }
        return observation.premiumColorIsPositive ? .orange : .green
    }
}

private struct QDIIQuotaRow: View {
    let item: QDIIQuotaWatchItem
    let tiantianObservation: QDIIQuotaObservation?
    let directObservation: QDIIQuotaObservation?
    let xueqiuObservation: QDIIQuotaObservation?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.13))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: tiantianObservation?.status.icon ?? "questionmark.circle.fill")
                        .foregroundStyle(color)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(tiantianObservation?.fundName ?? directObservation?.fundName ?? (item.fundName.isEmpty ? "基金 \(item.fundCode)" : item.fundName))
                        .scaledFont(.body.weight(.semibold))
                        .lineLimit(2)
                    if tiantianObservation?.isLowFeeRate == true {
                        Text("低费率")
                            .scaledFont(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("天天基金 \(tiantianObservation?.limitTitle ?? "待刷新")")
                            .scaledFont(.headline.monospacedDigit())
                            .foregroundStyle(color)
                        Text("直销 \(directObservation?.limitTitle ?? "待核验")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("雪球 \(xueqiuObservation?.limitTitle ?? "待核验")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("综合费率 \(tiantianObservation?.comprehensiveFeeTitle ?? "待刷新")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.fundCode).scaledFont(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text("天天基金：\(tiantianObservation?.status.title ?? "尚未读取")")
                        .scaledFont(.caption)
                        .foregroundStyle(color)
                    if let directObservation {
                        Text("直销：\(directObservation.status.title)")
                            .scaledFont(.caption)
                            .foregroundStyle(directObservation.status == .open ? .green : .orange)
                    }
                    if let xueqiuObservation {
                        Text("雪球：\(xueqiuObservation.status.title)")
                            .scaledFont(.caption)
                            .foregroundStyle(xueqiuObservation.status == .open ? .green : .orange)
                    }
                    if let date = tiantianObservation?.observedAt {
                        Text("天天基金观测 \(date.formatted(date: .omitted, time: .shortened))")
                            .scaledFont(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .opacity(item.isEnabled ? 1 : 0.5)
    }

    private var color: Color {
        switch tiantianObservation?.status {
        case .open: .green
        case .limited: .orange
        case .suspended: .red
        default: .secondary
        }
    }
}

struct QDIIQuotaDetail: View {
    @Environment(\.openURL) private var openURL
    let tiantianObservation: QDIIQuotaObservation?
    let directObservation: QDIIQuotaObservation?
    let xueqiuObservation: QDIIQuotaObservation?
    let changes: [QDIIQuotaChange]

    var body: some View {
        Group {
            if let observation = tiantianObservation ?? xueqiuObservation ?? directObservation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        channelMetric(
                            title: "天天基金",
                            observation: tiantianObservation,
                            fallback: "待刷新"
                        )
                        channelMetric(
                            title: "基金公司直销",
                            observation: directObservation,
                            fallback: "待核验"
                        )
                        channelMetric(
                            title: "雪球",
                            observation: xueqiuObservation,
                            fallback: "待核验"
                        )
                        Text(observation.fundName)
                            .scaledFont(.title.weight(.bold))
                            .textSelection(.enabled)
                        if observation.isLowFeeRate {
                            Label("低费率", systemImage: "checkmark.seal.fill")
                                .scaledFont(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Text(observation.fundCode).scaledFont(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            metric(title: "天天基金上限", value: tiantianObservation?.limitTitle ?? "待刷新")
                            metric(title: "直销上限", value: directObservation?.limitTitle ?? "待核验")
                            metric(title: "雪球上限", value: xueqiuObservation?.limitTitle ?? "待核验")
                            metric(title: "综合运营费率", value: observation.comprehensiveFeeTitle)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("费率明细").scaledFont(.headline)
                            Text(observation.feeBreakdownTitle)
                                .scaledFont(.body)
                                .foregroundStyle(.secondary)
                            Text("综合运营费率 = 管理费率 + 托管费率 + 销售服务费率；均为年化费率，从基金资产中计提。")
                                .scaledFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("核验说明").scaledFont(.headline)
                            Text("天天基金额度来自东方财富基金详情页；直销额度来自基金公告中明确标注的直销渠道；雪球额度来自雪球基金公开榜单。没有可靠渠道数据的基金显示为待核验，实际申购前仍请以基金管理人和销售平台页面为准。")
                                .scaledFont(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                        if !changes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("额度变化记录").scaledFont(.headline)
                                ForEach(changes.prefix(5)) { change in
                                    HStack {
                                        Text(change.changedAt, format: .dateTime.year().month().day())
                                            .scaledFont(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(change.oldLimitTitle) → \(change.newLimitTitle)")
                                            .scaledFont(.caption.weight(.medium))
                                        Spacer()
                                        Text("\(change.channel.title)：\(change.newStatus.title)")
                                            .scaledFont(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        HStack {
                            if let url = tiantianObservation.flatMap({ URL(string: $0.sourceURL) }) {
                                Button("打开天天基金来源") { openURL(url) }
                            }
                            if let url = directObservation.flatMap({ URL(string: $0.sourceURL) }) {
                                Button("打开直销公告") { openURL(url) }
                            }
                            if let url = xueqiuObservation.flatMap({ URL(string: $0.sourceURL) }) {
                                Button("打开雪球来源") { openURL(url) }
                            }
                        }
                        Text("观测于 \(observation.observedAt.formatted(date: .abbreviated, time: .shortened))")
                            .scaledFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(24)
                }
            } else {
                ContentUnavailableView("选择一只基金", systemImage: "chart.bar.doc.horizontal", description: Text("查看当前额度和数据来源。"))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).scaledFont(.caption).foregroundStyle(.secondary)
            Text(value).scaledFont(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func channelMetric(title: String, observation: QDIIQuotaObservation?, fallback: String) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: observation?.status.icon ?? "questionmark.circle")
                .scaledFont(.headline)
            Spacer()
            Text(observation?.status.title ?? fallback)
                .scaledFont(.subheadline.weight(.semibold))
                .foregroundStyle(observation?.status == .open ? .green : .orange)
        }
    }
}

struct QDIIExchangeDetail: View {
    @Environment(\.openURL) private var openURL
    let observation: QDIIExchangeObservation?

    var body: some View {
        Group {
            if let observation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(observation.fundName)
                            .scaledFont(.title.weight(.bold))
                            .textSelection(.enabled)
                        if observation.isLowFeeRate {
                            Label("低费率", systemImage: "checkmark.seal.fill")
                                .scaledFont(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Text(observation.fundCode)
                            .scaledFont(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            metric(title: observation.premiumRateIsEstimated ? "参考溢价率" : "溢价率", value: observation.premiumRateTitle)
                            metric(title: "最新价", value: observation.priceTitle)
                            metric(title: "净值 / IOPV", value: observation.netAssetValueTitle)
                            metric(title: "综合运营费率", value: observation.comprehensiveFeeTitle)
                        }
                        HStack(spacing: 12) {
                            metric(title: "涨跌幅", value: observation.changePercentTitle)
                            metric(title: "成交额", value: observation.turnoverTitle)
                            metric(title: "成交量", value: observation.volumeTitle)
                            metric(title: "换手率", value: observation.turnoverRateTitle)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("费率明细").scaledFont(.headline)
                            Text(observation.feeBreakdownTitle)
                                .scaledFont(.body)
                                .foregroundStyle(.secondary)
                            Text("综合运营费率 = 管理费率 + 托管费率 + 销售服务费率；均为年化费率，从基金资产中计提。")
                                .scaledFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("场内数据说明").scaledFont(.headline)
                            Text("溢价率 =（场内价格 ÷ 基金净值或 IOPV - 1）× 100%。实时 IOPV 不可用时，使用最新公布单位净值估算并明确标注为参考溢价率。场内成交价可能快速变化，实际交易前请以券商交易页面为准。")
                                .scaledFont(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                        if let url = URL(string: observation.sourceURL) {
                            Button("打开东方财富行情") { openURL(url) }
                        }
                        Text("观测于 \(observation.observedAt.formatted(date: .abbreviated, time: .shortened))")
                            .scaledFont(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(24)
                }
            } else {
                ContentUnavailableView("选择一只基金", systemImage: "chart.line.uptrend.xyaxis", description: Text("查看场内行情和数据来源。"))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).scaledFont(.caption).foregroundStyle(.secondary)
            Text(value).scaledFont(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AddQDIIQuotaView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: QDIIQuotaStore
    @State private var fundCode = ""
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加 QDII 基金").scaledFont(.title2.weight(.bold))
            Text("输入 6 位基金代码。基金名称可以留空，刷新后自动读取。")
                .scaledFont(.subheadline)
                .foregroundStyle(.secondary)
            TextField("基金代码，例如 018064", text: $fundCode)
                .textFieldStyle(.roundedBorder)
            TextField("基金名称（可选）", text: $name)
                .textFieldStyle(.roundedBorder)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).scaledFont(.caption) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    if store.addFund(code: fundCode, name: name) {
                        dismiss()
                    } else {
                        errorMessage = "请输入未监控的 6 位数字基金代码"
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 390)
    }
}

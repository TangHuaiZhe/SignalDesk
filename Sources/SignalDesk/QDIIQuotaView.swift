import SwiftUI

struct QDIIQuotaView: View {
    @EnvironmentObject private var store: QDIIQuotaStore
    @Environment(\.openURL) private var openURL
    @Binding var selection: String?
    @Binding var showingAddFund: Bool

    private var sortedItems: [QDIIQuotaWatchItem] {
        store.watchlist.sorted { lhs, rhs in
            let left = store.observation(for: lhs.fundCode)
            let right = store.observation(for: rhs.fundCode)
            if left?.canBuyMore != right?.canBuyMore { return left?.canBuyMore == true }
            return lhs.fundCode < rhs.fundCode
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if sortedItems.isEmpty {
                ContentUnavailableView("还没有监控基金", systemImage: "chart.bar.doc.horizontal", description: Text("添加基金代码后刷新额度。"))
            } else {
                List(selection: $selection) {
                    ForEach(sortedItems) { item in
                        QDIIQuotaRow(item: item, observation: store.observation(for: item.fundCode))
                            .tag(item.fundCode)
                            .contextMenu {
                                Button(item.isEnabled ? "暂停监控" : "恢复监控") { store.toggle(item) }
                                Button("删除基金", role: .destructive) {
                                    store.removeFund(item.fundCode)
                                    if selection == item.fundCode { selection = nil }
                                }
                                if let urlString = store.observation(for: item.fundCode)?.sourceURL,
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("QDII 基金额度")
                        .scaledFont(.largeTitle.weight(.bold))
                    Text("监控场外基金申购状态与单日累计购买上限 · 辅助源，仅供核验")
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
            HStack {
                Text(store.statusMessage ?? "关注额度上调、恢复申购或解除限购")
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

private struct QDIIQuotaRow: View {
    let item: QDIIQuotaWatchItem
    let observation: QDIIQuotaObservation?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.13))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: observation?.status.icon ?? "questionmark.circle.fill")
                        .foregroundStyle(color)
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
                        Text("综合费率 \(observation?.comprehensiveFeeTitle ?? "待刷新")")
                            .scaledFont(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(observation?.limitTitle ?? "待刷新")
                            .scaledFont(.headline.monospacedDigit())
                            .foregroundStyle(color)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.fundCode).scaledFont(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(observation?.status.title ?? "尚未读取").scaledFont(.caption).foregroundStyle(color)
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

    private var color: Color {
        switch observation?.status {
        case .open: .green
        case .limited: .orange
        case .suspended: .red
        default: .secondary
        }
    }
}

struct QDIIQuotaDetail: View {
    @Environment(\.openURL) private var openURL
    let observation: QDIIQuotaObservation?
    let changes: [QDIIQuotaChange]

    var body: some View {
        Group {
            if let observation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(observation.status.title, systemImage: observation.status.icon)
                            .foregroundStyle(observation.status == .open ? .green : .orange)
                            .scaledFont(.headline)
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
                            metric(title: "单日累计上限", value: observation.limitTitle)
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
                            Text("该数据来自天天基金/东方财富基金详情页，反映销售端公开展示值；不同销售渠道可能存在差异，实际申购前请以基金管理人和你的销售平台页面为准。")
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
                                        Text(change.newStatus.title)
                                            .scaledFont(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        Button("打开原始页面") { if let url = URL(string: observation.sourceURL) { openURL(url) } }
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

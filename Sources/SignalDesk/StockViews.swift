import SwiftUI

struct StockTimelineView: View {
    @EnvironmentObject private var store: SignalStore
    @Environment(\.openURL) private var openURL
    @Binding var selectedStockID: UUID?
    @Binding var selection: String?
    @Binding var showingAddStock: Bool
    @State private var selectedKind: StockInfoKind = .fundamentals

    private var activeStockID: UUID? {
        if let selectedStockID,
           store.stockWatchlist.contains(where: { $0.id == selectedStockID }) {
            return selectedStockID
        }
        return store.stockWatchlist.first?.id
    }

    private var updates: [StockUpdate] {
        store.stockUpdates
            .filter { $0.kind == selectedKind }
            .filter { $0.stockID == activeStockID }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.stockWatchlist.isEmpty {
                ContentUnavailableView(
                    "还没有自选股",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("点击右上角添加股票，随后在基本面、新闻、重要公告和深度研报子 Tab 中追踪公开信息。")
                )
            } else if updates.isEmpty {
                ContentUnavailableView(
                    "暂无\(activeStockName)的\(selectedKind.title)信息",
                    systemImage: selectedKind.icon,
                    description: Text("点击刷新获取公开来源；深度研报只保留最近 6 个月且不少于 10 页的公开 PDF。")
                )
            } else {
                List(selection: $selection) {
                    ForEach(updates) { update in
                        StockUpdateRow(update: update)
                            .tag(update.id)
                            .contextMenu {
                                Button(update.isBookmarked ? "取消收藏" : "收藏") {
                                    store.toggleStockUpdateBookmark(update.id)
                                }
                                Button("删除信息", role: .destructive) {
                                    store.deleteStockUpdate(update.id)
                                    if selection == update.id { selection = nil }
                                }
                                if let rawURL = update.url, let url = URL(string: rawURL) {
                                    Button("打开原文") { openURL(url) }
                                }
                            }
                    }
                    .onDelete { offsets in
                        store.deleteStockUpdates(offsets.map { updates[$0].id })
                        selection = nil
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 450, ideal: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("自选股信息")
                        .scaledFont(.largeTitle.weight(.bold))
                    Text("公开信息追踪 · 不等同于实时行情或投资建议")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showingAddStock = true
                } label: {
                    Label("添加股票", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(store.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
                Button("全部已读") { store.markAllStockUpdatesRead() }
            }

            Picker("股票信息类型", selection: $selectedKind) {
                ForEach(StockInfoKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.icon).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text(activeStockName)
                    .scaledFont(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let message = store.statusMessage {
                    Text(message)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var activeStockName: String {
        store.stockWatchlist.first { $0.id == activeStockID }?.displayName ?? "自选股"
    }

}

struct StockUpdateRow: View {
    let update: StockUpdate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(update.isRead ? Color.secondary.opacity(0.12) : Color.blue.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: update.kind.icon)
                        .foregroundStyle(update.isRead ? Color.secondary : Color.blue)
                }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(update.stockName.isEmpty ? update.symbol : update.stockName)
                        .scaledFont(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(update.publishedAt, format: .dateTime.year().month().day())
                        .scaledFont(.caption2)
                        .foregroundStyle(.tertiary)
                    if update.isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .scaledFont(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                    Text(update.title)
                        .scaledFont(.body.weight(update.isRead ? .regular : .semibold))
                        .lineLimit(2)
                    if update.kind == .deepReports, let pageCount = update.pageCount {
                        Label("\(pageCount) 页 PDF", systemImage: "doc.text")
                            .scaledFont(.caption2)
                            .foregroundStyle(.blue)
                    }
                if !update.summary.isEmpty {
                    Text(update.summary)
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct StockUpdateDetail: View {
    @Environment(\.openURL) private var openURL
    let update: StockUpdate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(update.kind.title, systemImage: update.kind.icon)
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(update.publishedAt, format: .dateTime.year().month().day().hour().minute())
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(update.title)
                    .scaledFont(.title2.weight(.bold))
                Text("\(update.stockName.isEmpty ? update.symbol : update.stockName) · \(update.symbol)")
                    .scaledFont(.subheadline)
                    .foregroundStyle(.secondary)
                if update.kind == .deepReports, let pageCount = update.pageCount {
                    Label("深度研报 · \(pageCount) 页 · 最近 6 个月", systemImage: "doc.text.magnifyingglass")
                        .scaledFont(.caption)
                        .foregroundStyle(.blue)
                }
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Text("公开来源摘要")
                        .scaledFont(.headline)
                    Text(update.summary.isEmpty ? "该来源未提供摘要，请打开原文查看。" : update.summary)
                        .scaledFont(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
                Label("这条信息来自公开检索结果，重要事项请以公司公告、交易所或监管机构原文为准。", systemImage: "info.circle")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                if let rawURL = update.url, let url = URL(string: rawURL) {
                    Button { openURL(url) } label: {
                        Label("打开原始来源", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding(28)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct AddStockView: View {
    @EnvironmentObject private var store: SignalStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var candidates: [StockCandidate] = []
    @State private var addError: String?
    @State private var isResolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("添加自选股")
                    .scaledFont(.title2.weight(.bold))
                Text("输入股票代码或公司名称，系统会自动识别上市市场。")
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("股票代码或公司名称（如 00700、腾讯控股、AAPL）", text: $query)
                    .onSubmit { resolveAndAdd() }
            }
            .formStyle(.grouped)

            if isResolving {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在识别股票…")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let addError {
                Label(addError, systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(.caption)
                    .foregroundStyle(.orange)
            }

            if candidates.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("找到多个上市标的，请选择")
                        .scaledFont(.headline)
                    ForEach(candidates) { candidate in
                        Button {
                            add(candidate)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.displayName)
                                    Text("\(candidate.marketTitle) · \(candidate.exchange)")
                                        .scaledFont(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !store.stockWatchlist.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已添加的自选股")
                        .scaledFont(.headline)
                    List {
                        ForEach(store.stockWatchlist) { stock in
                            HStack {
                                Text(stock.displayName)
                                Text(stock.market)
                                    .scaledFont(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { stock.isEnabled },
                                    set: { _ in store.toggleStock(stock) }
                                ))
                                .labelsHidden()
                            }
                        }
                        .onDelete(perform: store.removeStocks)
                    }
                    .frame(height: min(CGFloat(store.stockWatchlist.count * 42 + 18), 170))
                }
            }

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                Button {
                    resolveAndAdd()
                } label: {
                    Label(isResolving ? "识别中" : "识别并添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
            }
        }
        .padding(24)
        .frame(width: 560, height: store.stockWatchlist.isEmpty ? 360 : 560)
    }

    private func resolveAndAdd() {
        guard !isResolving else { return }
        isResolving = true
        addError = nil
        candidates = []
        Task {
            let matches = await StockLookupClient().search(query)
            await MainActor.run {
                isResolving = false
                if matches.isEmpty {
                    addError = "没有识别到可用股票，请检查代码或公司名称"
                } else if matches.count == 1, let candidate = matches.first {
                    add(candidate)
                } else {
                    candidates = matches
                }
            }
        }
    }

    private func add(_ candidate: StockCandidate) {
        guard store.addStock(candidate) else {
            addError = "该股票已经在自选股中"
            return
        }
        dismiss()
        Task { await store.refresh() }
    }
}

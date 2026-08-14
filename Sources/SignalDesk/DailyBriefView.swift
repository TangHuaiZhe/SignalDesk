import SwiftUI

struct DailyBriefIndexView: View {
    @EnvironmentObject private var store: SignalStore
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("每日快报")
                    .scaledFont(.largeTitle.weight(.bold))
                Text("每天 08:00 汇总最近 24 小时情报，并搜索 AI、机器人、新能源汽车和芯片新闻。")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if store.dailyBriefs.isEmpty {
                ContentUnavailableView(
                    "尚未生成每日快报",
                    systemImage: "newspaper",
                    description: Text("打开应用后会在 08:00 之后自动生成，也可以立即刷新。")
                )
            } else {
                Text("历史记录（\(store.dailyBriefs.count) 份）")
                    .scaledFont(.headline)
                List(selection: $selection) {
                    ForEach(store.dailyBriefs) { brief in
                        DailyBriefRow(brief: brief)
                            .tag(brief.id)
                            .contextMenu {
                                Button("删除快报", role: .destructive) {
                                    store.deleteDailyBrief(brief.id)
                                    if selection == brief.id { selection = nil }
                                }
                            }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.dailyBriefs[$0].id }
                        ids.forEach(store.deleteDailyBrief)
                        selection = nil
                    }
                }
                .listStyle(.inset)
                .frame(maxHeight: .infinity)
                .onAppear {
                    if selection == nil {
                        selection = store.dailyBrief?.id
                    }
                }
            }

            Button {
                Task {
                    await store.refreshDailyBrief()
                    selection = store.dailyBrief?.id
                }
            } label: {
                Label(
                    store.isGeneratingDailyBrief ? "生成中…" : "刷新并重新生成",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isGeneratingDailyBrief)

            Spacer()
        }
        .padding(24)
    }

}

struct DailyBriefView: View {
    @EnvironmentObject private var store: SignalStore
    @Binding var selection: String?

    private var selectedBrief: DailyBrief? {
        if let selection {
            return store.dailyBriefs.first { $0.id == selection }
        }
        return store.dailyBrief
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("每日快报")
                            .scaledFont(.largeTitle.weight(.bold))
                        if let brief = selectedBrief {
                            Text(
                                "\(brief.windowStart.formatted(date: .abbreviated, time: .shortened)) – "
                                    + brief.windowEnd.formatted(date: .abbreviated, time: .shortened)
                            )
                            .scaledFont(.subheadline)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("AI、具身智能、新能源汽车、芯片")
                                .scaledFont(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task {
                            await store.refreshDailyBrief()
                            selection = store.dailyBrief?.id
                        }
                    } label: {
                        Label(
                            store.isGeneratingDailyBrief ? "生成中…" : "刷新快报",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isGeneratingDailyBrief)
                }

                if let message = store.statusMessage,
                   (store.isGeneratingDailyBrief || message.contains("每日快报")) {
                    Label(message, systemImage: store.isGeneratingDailyBrief ? "hourglass" : "info.circle")
                        .scaledFont(.caption)
                        .foregroundStyle(.secondary)
                }

                if let brief = selectedBrief {
                    HStack(spacing: 20) {
                        metric(title: "已抓取情报", value: "\(brief.trackedEventCount)")
                        metric(title: "全网新闻", value: "\(brief.newsItemCount)")
                        metric(title: "生成模型", value: brief.provider.title)
                    }
                    .padding(16)
                    .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                    MarkdownText(brief.content)
                        .scaledFont(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)

                    Text("生成于 \(brief.generatedAt.formatted(date: .abbreviated, time: .shortened)) · 新闻来自 Google News RSS 聚合；公司影响与估值判断请结合财报和行情核验")
                        .scaledFont(.caption2)
                        .foregroundStyle(.tertiary)
                } else if store.isGeneratingDailyBrief {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在搜索新闻、整理过去 24 小时情报并生成详细快报…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "尚未生成快报",
                        systemImage: "newspaper",
                        description: Text("点击“刷新快报”立即搜索并生成。")
                    )
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .scaledFont(.title2.weight(.bold).monospacedDigit())
            Text(title)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyBriefRow: View {
    let brief: DailyBrief

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(brief.windowEnd.formatted(date: .complete, time: .omitted))
                    .scaledFont(.headline)
                Spacer()
                Text(brief.generatedAt.formatted(date: .omitted, time: .shortened))
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(brief.trackedEventCount) 条情报 · \(brief.newsItemCount) 条新闻 · \(brief.provider.title)")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

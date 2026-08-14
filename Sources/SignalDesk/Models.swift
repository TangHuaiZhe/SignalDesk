import Foundation

enum SourceKind: String, Codable, CaseIterable, Identifiable {
    case rss
    case sec13F
    case x
    case mediaSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rss: "RSS / Atom"
        case .sec13F: "SEC 13F"
        case .x: "X 第三方 API"
        case .mediaSearch: "采访 / 播客 / 视频"
        }
    }

    var icon: String {
        switch self {
        case .rss: "dot.radiowaves.left.and.right"
        case .sec13F: "building.columns"
        case .x: "at"
        case .mediaSearch: "mic.and.signal.meter.fill"
        }
    }

    static let userAddableCases: [SourceKind] = [.rss, .sec13F, .x]
}

enum SignalCategory: String, Codable, CaseIterable, Identifiable {
    case viewpoint
    case activity
    case holding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .viewpoint: "观点"
        case .activity: "动向"
        case .holding: "持仓"
        }
    }

    var icon: String {
        switch self {
        case .viewpoint: "quote.bubble.fill"
        case .activity: "bolt.fill"
        case .holding: "chart.pie.fill"
        }
    }
}

enum SignalDomain: String, Codable, CaseIterable, Identifiable {
    case modelsAgents
    case robotics
    case compute
    case investmentBusiness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modelsAgents: "模型与 Agent"
        case .robotics: "机器人与具身智能"
        case .compute: "算力与芯片"
        case .investmentBusiness: "投资与商业"
        }
    }
}

enum SourceChannel: String, Codable, CaseIterable, Identifiable {
    case chinaEconomy

    var id: String { rawValue }
}

struct TrackedSource: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var role: String
    var topics: [String]
    var sourceKind: SourceKind
    var feedURL: String
    var requiredTitleTerms: [String]? = nil
    var isEnabled = true
    var lastCheckedAt: Date?
    var groupID: String? = nil
    var groupName: String? = nil
    var channel: SourceChannel? = nil

    var groupKey: String {
        groupID ?? groupName ?? name.components(separatedBy: " · ").first ?? name
    }

    var groupTitle: String {
        groupName ?? name.components(separatedBy: " · ").first ?? name
    }

    var initials: String {
        let words = name.split(separator: " ")
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined()
        }
        return String(name.prefix(2))
    }
}

struct SignalEvent: Identifiable, Codable, Hashable {
    var id: String
    var sourceID: UUID
    var sourceKind: SourceKind? = nil
    var sourceName: String
    var title: String
    var summary: String
    var url: String?
    var transcriptURL: String? = nil
    var publishedAt: Date
    var category: SignalCategory
    var importance: Int
    var matchedTopics: [String]
    var domains: [SignalDomain]? = nil
    var isRead = false
    var isBookmarked = false
    var aiSummary: AISummary?
    var aiTranslation: AITranslation? = nil
}

enum StockInfoKind: String, Codable, CaseIterable, Identifiable {
    case fundamentals
    case news
    case announcements
    case deepReports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fundamentals: "基本面"
        case .news: "新闻"
        case .announcements: "重要公告"
        case .deepReports: "深度研报"
        }
    }

    var icon: String {
        switch self {
        case .fundamentals: "chart.bar.xaxis"
        case .news: "newspaper.fill"
        case .announcements: "megaphone.fill"
        case .deepReports: "doc.text.magnifyingglass"
        }
    }
}

enum StockMarket: String, CaseIterable, Identifiable {
    case cn
    case hk
    case us
    case other

    var id: String { rawValue }

    var code: String { rawValue.uppercased() }

    var title: String {
        switch self {
        case .cn: "中国 A 股"
        case .hk: "香港市场"
        case .us: "美国市场"
        case .other: "其他"
        }
    }
}

struct StockCandidate: Identifiable, Hashable {
    var symbol: String
    var name: String
    var market: String
    var exchange: String

    var id: String { "\(market)|\(symbol)" }

    var displayName: String {
        name.isEmpty ? symbol : "\(name)（\(symbol)）"
    }

    var marketTitle: String {
        StockMarket(rawValue: market.lowercased())?.title ?? market
    }
}

struct StockWatchlistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var symbol: String
    var name: String
    var market: String
    var isEnabled = true
    var lastCheckedAt: Date?

    var displayName: String {
        name.isEmpty ? symbol : "\(name)（\(symbol)）"
    }
}

struct StockUpdate: Identifiable, Codable, Hashable {
    var id: String
    var stockID: UUID
    var symbol: String
    var stockName: String
    var kind: StockInfoKind
    var title: String
    var summary: String
    var url: String?
    var publishedAt: Date
    var importance: Int
    var pageCount: Int? = nil
    var isRead = false
    var isBookmarked = false
}

struct AISummary: Codable, Hashable {
    var content: String
    var provider: AISummaryProvider
    var generatedAt: Date

    var isDetailedFormat: Bool {
        [
            "# 关键事实与数据",
            "# 主要观点与论证链",
            "# 原文覆盖说明"
        ].allSatisfy(content.contains)
    }
}

struct AITranslation: Codable, Hashable {
    var content: String
    var provider: AISummaryProvider
    var generatedAt: Date
}

enum AISummaryProvider: String, Codable, CaseIterable, Identifiable {
    case appleOnDevice
    case ollama
    case deepSeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice: "Apple 本机模型"
        case .ollama: "Ollama 本地模型"
        case .deepSeek: "DeepSeek API"
        }
    }
}

enum AISummaryMode: String, CaseIterable, Identifiable {
    case localFirst
    case ollama
    case deepSeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localFirst: "本机优先（免费）"
        case .ollama: "Ollama（免费）"
        case .deepSeek: "DeepSeek"
        }
    }
}

struct AppSnapshot: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var sources: [TrackedSource]
    var events: [SignalEvent]
    var lastRefreshAt: Date?
    var installedCatalogIDs: [String]? = nil
    var dailyBrief: DailyBrief? = nil
    var dailyBriefs: [DailyBrief]? = nil
    var stockWatchlist: [StockWatchlistItem]? = nil
    var stockUpdates: [StockUpdate]? = nil

    init(
        schemaVersion: Int = AppSnapshot.currentSchemaVersion,
        sources: [TrackedSource],
        events: [SignalEvent],
        lastRefreshAt: Date?,
        installedCatalogIDs: [String]? = nil,
        dailyBrief: DailyBrief? = nil,
        dailyBriefs: [DailyBrief]? = nil,
        stockWatchlist: [StockWatchlistItem]? = nil,
        stockUpdates: [StockUpdate]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.sources = sources
        self.events = events
        self.lastRefreshAt = lastRefreshAt
        self.installedCatalogIDs = installedCatalogIDs
        self.dailyBrief = dailyBrief
        self.dailyBriefs = dailyBriefs
        self.stockWatchlist = stockWatchlist
        self.stockUpdates = stockUpdates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? AppSnapshot.currentSchemaVersion
        sources = try container.decode([TrackedSource].self, forKey: .sources)
        events = try container.decode([SignalEvent].self, forKey: .events)
        lastRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshAt)
        installedCatalogIDs = try container.decodeIfPresent([String].self, forKey: .installedCatalogIDs)
        dailyBrief = try container.decodeIfPresent(DailyBrief.self, forKey: .dailyBrief)
        dailyBriefs = try container.decodeIfPresent([DailyBrief].self, forKey: .dailyBriefs)
        stockWatchlist = try container.decodeIfPresent([StockWatchlistItem].self, forKey: .stockWatchlist)
        stockUpdates = try container.decodeIfPresent([StockUpdate].self, forKey: .stockUpdates)
    }
}

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case inbox
    case xFeed
    case rssFeed
    case chinaEconomy
    case stocks
    case qdiiQuotas
    case highValue
    case bookmarks
    case dailyBrief
    case investors
    case sources
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "情报流"
        case .xFeed: "X 情报"
        case .rssFeed: "RSS"
        case .chinaEconomy: "海外看中国"
        case .stocks: "自选股信息"
        case .qdiiQuotas: "QDII 基金额度"
        case .highValue: "高价值"
        case .bookmarks: "已收藏"
        case .dailyBrief: "每日快报"
        case .investors: "杰出投资者"
        case .sources: "监控对象"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "rectangle.stack.fill"
        case .xFeed: "at.circle.fill"
        case .rssFeed: "dot.radiowaves.left.and.right"
        case .chinaEconomy: "globe.asia.australia.fill"
        case .stocks: "chart.line.uptrend.xyaxis"
        case .qdiiQuotas: "chart.bar.doc.horizontal"
        case .highValue: "sparkles"
        case .bookmarks: "bookmark.fill"
        case .dailyBrief: "newspaper.fill"
        case .investors: "chart.pie.fill"
        case .sources: "person.2.fill"
        case .settings: "gearshape.fill"
        }
    }
}

extension TrackedSource {
    static let starterSources = [
        TrackedSource(
            name: "Sam Altman / OpenAI",
            role: "AI · 官方动态",
            topics: ["AI", "模型", "Agent", "算力"],
            sourceKind: .rss,
            feedURL: "https://openai.com/news/rss.xml"
        ),
        TrackedSource(
            name: "Jensen Huang / NVIDIA",
            role: "AI 芯片 · 机器人",
            topics: ["GPU", "机器人", "AI", "数据中心"],
            sourceKind: .rss,
            feedURL: "https://nvidianews.nvidia.com/cats/robotics.xml"
        )
    ]

    static func sec13F(name: String, role: String, cik: String) -> TrackedSource {
        let digits = cik.filter(\.isNumber)
        let url = "https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=\(digits)&type=13F-HR&owner=exclude&count=40&output=atom"
        var source = TrackedSource(
            name: name,
            role: role,
            topics: ["13F", "持仓", "投资"],
            sourceKind: .sec13F,
            feedURL: url
        )
        source.groupID = "sec13f-\(digits)"
        source.groupName = name
        return source
    }

    static func x(
        name: String,
        role: String,
        username: String,
        topics: [String],
        isEnabled: Bool = true
    ) -> TrackedSource {
        var source = TrackedSource(
            name: name,
            role: role,
            topics: topics,
            sourceKind: .x,
            feedURL: username.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        )
        source.groupName = name
        source.isEnabled = isEnabled
        return source
    }
}

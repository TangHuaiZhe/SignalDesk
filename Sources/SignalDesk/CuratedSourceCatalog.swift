import Foundation

struct CuratedSourcePreset: Identifiable, Hashable {
    var id: String
    var name: String
    var role: String
    var topics: [String]
    var feedURL: String
    var channel: SourceChannel? = nil

    func trackedSource() -> TrackedSource {
        var source = TrackedSource(
            name: name,
            role: role,
            topics: topics,
            sourceKind: .rss,
            feedURL: feedURL
        )
        source.groupID = id
        source.groupName = name
        source.channel = channel
        return source
    }
}

extension CuratedSourcePreset {
    static let researchSources: [CuratedSourcePreset] = [
        CuratedSourcePreset(
            id: "howard-marks-oaktree-memos",
            name: "Howard Marks / Oaktree Memos",
            role: "周期、风险、市场情绪与估值纪律；新 memo 必读；不是具体股票推荐",
            topics: ["market cycle", "risk", "market sentiment", "valuation", "credit", "周期", "风险", "估值", "信用"],
            feedURL: googleNewsFeed(query: "site:oaktreecapital.com/insights \"Howard Marks\"")
        ),
        CuratedSourcePreset(
            id: "aswath-damodaran-musings-on-markets",
            name: "Aswath Damodaran / Musings on Markets",
            role: "估值、反向 DCF 与把商业叙事转成可检验假设；估值依赖假设，不是目标价机器",
            topics: ["valuation", "DCF", "cost of capital", "narrative", "估值", "反向 DCF", "资本成本"],
            feedURL: "https://aswathdamodaran.blogspot.com/feeds/posts/default?alt=rss"
        ),
        CuratedSourcePreset(
            id: "stratechery",
            name: "Stratechery / Ben Thompson",
            role: "科技战略、平台、分发、价值捕获与利润池；战略洞察强于财务模型和估值",
            topics: ["technology strategy", "platform", "distribution", "value capture", "profit pool", "科技战略", "平台", "分发"],
            feedURL: "https://stratechery.com/feed/"
        ),
        CuratedSourcePreset(
            id: "money-stuff-matt-levine",
            name: "Money Stuff / Matt Levine",
            role: "并购、证券设计、监管、激励与市场机制；理解市场如何运作，不是选股服务",
            topics: ["merger", "acquisition", "securities", "regulation", "incentives", "market structure", "并购", "监管", "市场机制"],
            feedURL: "https://www.bloomberg.com/opinion/authors/ARbTQlRLRjE/matthew-s-levine.rss"
        ),
        CuratedSourcePreset(
            id: "the-diff-byrne-hobart",
            name: "The Diff / Byrne Hobart",
            role: "科技、金融与商业模式的非共识连接；用于寻找第二层问题，需回到一手资料核验",
            topics: ["technology", "finance", "business model", "strategy", "macroeconomics", "科技", "金融", "商业模式"],
            feedURL: "https://www.thediff.co/feed"
        ),
        CuratedSourcePreset(
            id: "semianalysis",
            name: "SemiAnalysis",
            role: "AI 加速器、数据中心、电力、网络、晶圆厂与成本结构；关注供应链瓶颈",
            topics: ["GPU", "ASIC", "HBM", "datacenter", "power", "networking", "foundry", "inference", "accelerator", "AI 加速器", "数据中心", "电力"],
            feedURL: "https://newsletter.semianalysis.com/feed"
        ),
        CuratedSourcePreset(
            id: "fabricated-knowledge",
            name: "Fabricated Knowledge",
            role: "用投资视角解释半导体公司与细分环节；优先阅读封装、量测、光刻、时钟与 CXL Primer",
            topics: ["semiconductor", "packaging", "metrology", "lithography", "timing", "CXL", "半导体", "封装", "量测", "光刻"],
            feedURL: "https://www.fabricatedknowledge.com/feed"
        ),
        CuratedSourcePreset(
            id: "a16z-show",
            name: "The a16z Show",
            role: "AI 创业、产品、基础设施与科技产业前沿访谈；关注芯片、数据中心与 AI 商业化",
            topics: ["AI", "startup", "product", "infrastructure", "chip", "datacenter", "AI commercialization", "创业", "基础设施", "商业化"],
            feedURL: "https://feeds.simplecast.com/JGE3yC0V"
        ),
        CuratedSourcePreset(
            id: "ai-a16z",
            name: "AI + a16z",
            role: "AI 技术与商业模式专题；关注 Agent、评测、数据、AI 定价与企业部署",
            topics: ["AI", "agent", "evaluation", "data", "pricing", "enterprise deployment", "AI infrastructure", "Agent", "评测", "企业部署"],
            feedURL: "https://feeds.simplecast.com/Hb_IuXOo"
        )
    ]

    static let chinaEconomySources: [CuratedSourcePreset] = [
        CuratedSourcePreset(
            id: "china-economy-goldman-sachs",
            name: "Goldman Sachs Research · China",
            role: "高盛研究部对中国宏观、消费、地产、出口与产业转型的研究；聚合入口，原文回到高盛",
            topics: ["China", "Chinese economy", "GDP", "growth", "consumption", "property", "exports", "manufacturing", "中国经济", "增长", "消费", "房地产", "出口", "制造业"],
            feedURL: googleNewsFeed(query: "site:goldmansachs.com/insights China economy"),
            channel: .chinaEconomy
        ),
        CuratedSourcePreset(
            id: "china-economy-bbc",
            name: "BBC News · China Economy",
            role: "BBC 对中国经济、贸易、产业与企业变化的报道；聚合入口，原文回到 BBC",
            topics: ["China", "economy", "economic", "GDP", "trade", "business", "property", "exports", "中国经济", "经济", "贸易", "企业"],
            feedURL: googleNewsFeed(query: "site:bbc.com/news China economy OR economic OR business OR trade"),
            channel: .chinaEconomy
        ),
        CuratedSourcePreset(
            id: "china-economy-financial-times",
            name: "Financial Times · China",
            role: "金融时报对中国宏观、市场、产业链和企业的深度报道；聚合入口，原文回到 FT",
            topics: ["China", "economy", "markets", "business", "property", "trade", "manufacturing", "中国经济", "市场", "商业", "房地产", "贸易", "制造业"],
            feedURL: googleNewsFeed(query: "site:ft.com China economy OR markets OR business"),
            channel: .chinaEconomy
        ),
        CuratedSourcePreset(
            id: "china-economy-economist",
            name: "The Economist · China",
            role: "《经济学人》对中国宏观、产业、消费与企业的分析；聚合入口，原文回到 Economist",
            topics: ["China", "economy", "industry", "consumption", "property", "technology", "中国经济", "产业", "消费", "房地产", "科技"],
            feedURL: googleNewsFeed(query: "site:economist.com China economy OR business OR industry"),
            channel: .chinaEconomy
        ),
        CuratedSourcePreset(
            id: "china-economy-imf",
            name: "IMF · China / Asia",
            role: "国际货币基金组织对中国与亚洲增长、政策、贸易和金融稳定的研究；聚合入口，原文回到 IMF",
            topics: ["China", "economy", "GDP", "growth", "policy", "trade", "financial stability", "中国经济", "增长", "政策", "贸易", "金融稳定"],
            feedURL: googleNewsFeed(query: "site:imf.org China economy"),
            channel: .chinaEconomy
        ),
        CuratedSourcePreset(
            id: "china-economy-world-bank",
            name: "World Bank · China",
            role: "世界银行对中国增长、就业、消费、生产率和结构改革的研究；聚合入口，原文回到 World Bank",
            topics: ["China", "economy", "growth", "employment", "consumption", "productivity", "reform", "中国经济", "增长", "就业", "消费", "生产率", "改革"],
            feedURL: googleNewsFeed(query: "site:worldbank.org China economy"),
            channel: .chinaEconomy
        )
    ]

    static let magazineSources: [CuratedSourcePreset] = [
        CuratedSourcePreset(
            id: "english-magazine-economist",
            name: "The Economist",
            role: "追踪 awesome-english-ebooks 的《经济学人》最新期号更新",
            topics: ["The Economist", "economist", "magazine", "杂志", "经济学人"],
            feedURL: githubCommitFeed(path: "01_economist"),
            channel: .magazines
        ),
        CuratedSourcePreset(
            id: "english-magazine-new-yorker",
            name: "The New Yorker",
            role: "追踪 awesome-english-ebooks 的《纽约客》最新期号更新",
            topics: ["The New Yorker", "new yorker", "magazine", "杂志", "纽约客"],
            feedURL: githubCommitFeed(path: "02_new_yorker"),
            channel: .magazines
        ),
        CuratedSourcePreset(
            id: "english-magazine-atlantic",
            name: "The Atlantic",
            role: "追踪 awesome-english-ebooks 的 The Atlantic 最新期号更新",
            topics: ["The Atlantic", "atlantic", "magazine", "杂志"],
            feedURL: githubCommitFeed(path: "04_atlantic"),
            channel: .magazines
        ),
        CuratedSourcePreset(
            id: "english-magazine-wired",
            name: "Wired",
            role: "追踪 awesome-english-ebooks 的 Wired 最新期号更新",
            topics: ["Wired", "magazine", "杂志", "科技杂志"],
            feedURL: githubCommitFeed(path: "05_wired"),
            channel: .magazines
        )
    ]

    private static func googleNewsFeed(query: String) -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "news.google.com"
        components.path = "/rss/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        return components.url!.absoluteString
    }

    private static func githubCommitFeed(path: String) -> String {
        "https://github.com/hehonghui/awesome-english-ebooks/commits/master/\(path).atom"
    }
}

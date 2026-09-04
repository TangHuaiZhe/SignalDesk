import Foundation

struct ParsedFeedItem: Equatable {
    var title: String
    var summary: String
    var link: String?
    var transcriptURL: String?
    var publishedAt: Date
}

enum FeedError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int)
    case invalidFeed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "来源地址无效"
        case .invalidResponse: "服务器响应无效"
        case .http(let code): "服务器返回 HTTP \(code)"
        case .invalidFeed: "无法解析 RSS / Atom 内容"
        }
    }
}

struct FeedClient {
    func fetchX(_ sources: [TrackedSource]) async throws -> [UUID: [SignalEvent]] {
        try await XClient().fetch(sources)
    }

    func fetch(_ source: TrackedSource) async throws -> [SignalEvent] {
        switch source.sourceKind {
        case .rss, .mediaSearch:
            return try await fetchFeed(source)
        case .sec13F:
            return try await SEC13FClient().fetch(source)
        case .x:
            return try await XClient().fetch(source)
        }
    }

    private func fetchFeed(_ source: TrackedSource) async throws -> [SignalEvent] {
        guard let url = URL(string: source.feedURL) else {
            throw FeedError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "SignalDesk/0.1 contact=local-user@signalsdesk.app",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/atom+xml, application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeedError.http(http.statusCode)
        }

        let itemLimit = source.sourceKind == .mediaSearch ? 25 : 150
        var parsedItems = try FeedParser.parse(
            data: data,
            allowEmpty: source.sourceKind == .mediaSearch
        )
        if source.sourceKind == .mediaSearch {
            parsedItems = parsedItems.filter {
                MediaClassifier.isLongForm(title: $0.title) &&
                MediaClassifier.matchesPerson(
                    title: $0.title,
                    aliases: source.requiredTitleTerms ?? []
                )
            }
        }
        if let requiredTitleTerms = source.requiredTitleTerms, !requiredTitleTerms.isEmpty {
            parsedItems = parsedItems.filter {
                MediaClassifier.matchesPerson(title: $0.title, aliases: requiredTitleTerms)
            }
        }
        if source.channel == .chinaEconomy {
            parsedItems = parsedItems.filter {
                ChinaEconomyRelevance.matches(title: $0.title, summary: $0.summary)
            }
        }
        let items = parsedItems
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(itemLimit)
        return items.map { item in
            let text = "\(item.title) \(item.summary)"
            let score = ImportanceScorer.score(text: text, topics: source.topics, kind: source.sourceKind)
            let category = ImportanceScorer.category(text: text, kind: source.sourceKind)
            let matched = ImportanceScorer.matchedTopics(in: text, topics: source.topics)
            let identity = item.link ?? "\(item.title)|\(item.publishedAt.timeIntervalSince1970)"

            return SignalEvent(
                id: "\(source.id.uuidString)|\(identity)",
                sourceID: source.id,
                sourceKind: source.sourceKind,
                sourceName: source.name,
                title: item.title,
                summary: item.summary,
                url: item.link,
                transcriptURL: item.transcriptURL,
                publishedAt: item.publishedAt,
                category: category,
                importance: score,
                matchedTopics: matched,
                domains: SignalDomainClassifier.classify(
                    text: text,
                    fallbackDomains: PersonPreset.defaultDomains(for: source),
                    kind: source.sourceKind
                )
            )
        }
    }
}

enum ChinaEconomyRelevance {
    private static let terms = [
        "china", "chinese", "hong kong", "beijing", "shanghai", "shenzhen", "guangzhou",
        "中国", "香港", "北京", "上海", "深圳", "广州"
    ]

    static func matches(title: String, summary: String) -> Bool {
        let text = "\(title) \(summary)".lowercased()
        return terms.contains { term in
            if term.unicodeScalars.allSatisfy({ !$0.isASCII }) || term.contains(" ") {
                return text.contains(term)
            }
            let escaped = NSRegularExpression.escapedPattern(for: term)
            return text.range(
                of: "(?<![a-z0-9])\(escaped)(?![a-z0-9])",
                options: .regularExpression
            ) != nil
        }
    }
}

enum MediaClassifier {
    private static let markers = [
        "interview", "podcast", "keynote", "conversation", "fireside",
        "q&a", "qa with", "talks with", "in conversation", "video", "webinar",
        "访谈", "专访", "采访", "对话", "播客", "演讲", "圆桌", "问答", "视频", "直播", "网络研讨会"
    ]
    private static let explicitMediaMarkers = [
        "podcast", "webinar", "livestream", "lecture",
        "播客", "视频", "直播", "网络研讨会", "讲座"
    ]

    static func isLongForm(title: String) -> Bool {
        let lowered = title.lowercased()
        return markers.contains { lowered.contains($0) }
    }

    static func isMedia(title: String, url: String?) -> Bool {
        let loweredTitle = title.lowercased()
        if explicitMediaMarkers.contains(where: loweredTitle.contains) { return true }
        guard let url, let parsedURL = URL(string: url) else { return false }

        let host = parsedURL.host?.lowercased() ?? ""
        if [
            "youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com",
            "vimeo.com", "www.vimeo.com", "open.spotify.com", "spotify.com",
            "podcasts.apple.com", "soundcloud.com", "www.soundcloud.com"
        ].contains(host) {
            return true
        }

        return ["mp3", "m4a", "mp4", "webm", "m3u8"].contains(parsedURL.pathExtension.lowercased())
    }

    static func matchesPerson(title: String, aliases: [String]) -> Bool {
        guard !aliases.isEmpty else { return true }
        return aliases.contains { title.localizedCaseInsensitiveContains($0) }
    }
}

enum ImportanceScorer {
    private static let highImpact = [
        "launch", "release", "acquire", "investment", "funding", "partnership",
        "breakthrough", "robot", "agent", "model", "chip", "gpu", "13f",
        "发布", "推出", "收购", "投资", "融资", "合作", "突破", "机器人",
        "智能体", "模型", "芯片", "算力", "持仓"
    ]
    private static let conviction = [
        "believe", "predict", "expect", "future", "strategy", "thesis",
        "认为", "预测", "预计", "未来", "战略", "判断"
    ]

    static func score(text: String, topics: [String], kind: SourceKind) -> Int {
        let lowered = text.lowercased()
        var value: Int
        switch kind {
        case .sec13F: value = 70
        case .mediaSearch: value = 52
        default: value = 38
        }
        value += min(matchedTopics(in: text, topics: topics).count * 9, 27)
        value += min(highImpact.filter { lowered.contains($0) }.count * 5, 25)
        value += min(conviction.filter { lowered.contains($0) }.count * 4, 12)
        return min(value, 100)
    }

    static func matchedTopics(in text: String, topics: [String]) -> [String] {
        let lowered = text.lowercased()
        return topics.filter { topic in
            let term = topic.lowercased()
            guard term.count <= 3, term.unicodeScalars.allSatisfy(\.isASCII) else {
                return lowered.contains(term)
            }
            let escaped = NSRegularExpression.escapedPattern(for: term)
            return lowered.range(of: "(?<![a-z0-9])\(escaped)(?![a-z0-9])", options: .regularExpression) != nil
        }
    }

    static func category(text: String, kind: SourceKind) -> SignalCategory {
        if kind == .sec13F { return .holding }
        if kind == .mediaSearch { return .viewpoint }
        let lowered = text.lowercased()
        if conviction.contains(where: lowered.contains) { return .viewpoint }
        return .activity
    }
}

enum SignalDomainClassifier {
    private static let terms: [SignalDomain: [String]] = [
        .modelsAgents: [
            "agi", "llm", "language model", "foundation model", "world model",
            "agent", "agents", "agentic", "copilot", "reasoning", "alignment",
            "ai safety", "artificial intelligence", "machine intelligence",
            "powerful ai", "model training", "模型", "大模型", "智能体",
            "世界模型", "推理模型", "对齐", "ai 安全"
        ],
        .robotics: [
            "robot", "robots", "robotics", "humanoid", "embodied ai",
            "physical ai", "optimus", "unitree", "vla", "gr00t",
            "autonomous driving", "self-driving", "fsd", "spatial intelligence",
            "机器人", "人形机器人", "具身智能", "物理智能", "自动驾驶", "空间智能"
        ],
        .compute: [
            "gpu", "gpus", "chip", "chips", "semiconductor", "accelerator",
            "inference", "compute", "computing", "data center", "datacenter",
            "ai factory", "mi300", "mi400", "yottaflops", "infrastructure",
            "算力", "芯片", "半导体", "推理成本", "数据中心", "ai 工厂", "基础设施"
        ],
        .investmentBusiness: [
            "13f", "holding", "holdings", "portfolio", "stake", "shares",
            "investment", "investing", "funding", "fundraise", "acquisition",
            "acquire", "valuation", "revenue", "monetization", "business model",
            "enterprise", "productivity", "workflow", "capex", "capital expenditure",
            "持仓", "增持", "减持", "清仓", "投资", "融资", "收购", "估值",
            "营收", "商业模式", "企业", "生产率", "工作流", "资本开支"
        ]
    ]

    static func classify(
        text: String,
        fallbackDomains: [SignalDomain] = [],
        kind: SourceKind? = nil
    ) -> [SignalDomain] {
        let lowered = text.lowercased()
        let direct = SignalDomain.allCases.filter { domain in
            if domain == .investmentBusiness, kind == .sec13F { return true }
            return terms[domain, default: []].contains { contains($0, in: lowered) }
        }
        return direct.isEmpty ? fallbackDomains : direct
    }

    private static func contains(_ term: String, in text: String) -> Bool {
        let loweredTerm = term.lowercased()
        guard loweredTerm.unicodeScalars.allSatisfy(\.isASCII),
              !loweredTerm.contains(" ") else {
            return text.contains(loweredTerm)
        }
        let escaped = NSRegularExpression.escapedPattern(for: loweredTerm)
        return text.range(
            of: "(?<![a-z0-9])\(escaped)(?![a-z0-9])",
            options: .regularExpression
        ) != nil
    }
}

enum FeedParser {
    static func parse(data: Data, allowEmpty: Bool = false) throws -> [ParsedFeedItem] {
        let delegate = FeedXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), allowEmpty || !delegate.items.isEmpty else {
            throw parser.parserError ?? FeedError.invalidFeed
        }
        return delegate.items
    }
}

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentText = ""
    private var current: Draft?
    private var isEntry = false
    var items: [ParsedFeedItem] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = normalized(elementName)
        currentElement = element
        currentText = ""

        if element == "item" || element == "entry" {
            current = Draft()
            isEntry = element == "entry"
        }
        if isEntry, element == "link", let href = attributeDict["href"], current?.link == nil {
            current?.link = href
        }
        if element == "transcript", let url = attributeDict["url"], current?.transcriptURL == nil {
            current?.transcriptURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) {
            currentText += value
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = normalized(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard current != nil else { return }
        switch element {
        case "title":
            if current?.title.isEmpty == true { current?.title = clean(text) }
        case "description", "summary", "content":
            if current?.summary.isEmpty == true { current?.summary = clean(text) }
        case "link":
            if !isEntry, !text.isEmpty { current?.link = text }
        case "transcript":
            if current?.transcriptURL == nil, !text.isEmpty { current?.transcriptURL = text }
        case "pubdate", "published", "updated", "filing-date":
            if current?.publishedAt == nil { current?.publishedAt = FeedDateParser.date(from: text) }
        case "item", "entry":
            if let current, !current.title.isEmpty {
                items.append(
                    ParsedFeedItem(
                        title: current.title,
                        summary: current.summary,
                        link: current.link,
                        transcriptURL: current.transcriptURL,
                        publishedAt: current.publishedAt ?? Date()
                    )
                )
            }
            self.current = nil
            isEntry = false
        default:
            break
        }
        currentText = ""
    }

    private func normalized(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    private func clean(_ source: String) -> String {
        source
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Draft {
        var title = ""
        var summary = ""
        var link: String?
        var transcriptURL: String?
        var publishedAt: Date?
    }
}

private enum FeedDateParser {
    private static let formatters: [DateFormatter] = {
        let patterns = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd"
        ]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    static func date(from string: String) -> Date? {
        formatters.lazy.compactMap { $0.date(from: string) }.first
    }
}

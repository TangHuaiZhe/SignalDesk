import Foundation
import PDFKit

struct StockResearchReportFilter {
    static let minimumPageCount = 10

    static func isEligible(
        publishedAt: Date,
        pageCount: Int,
        now: Date = Date()
    ) -> Bool {
        guard pageCount >= minimumPageCount else { return false }
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: now)
            ?? now.addingTimeInterval(-180 * 24 * 60 * 60)
        return publishedAt >= sixMonthsAgo && publishedAt <= now
    }
}

struct StockLookupClient {
    func search(_ input: String) async -> [StockCandidate] {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let fallback = Self.localCandidates(for: normalized)
        if !fallback.isEmpty { return fallback }

        guard var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search") else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: normalized),
            URLQueryItem(name: "quotesCount", value: "10"),
            URLQueryItem(name: "newsCount", value: "0")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("SignalDesk/0.1", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let payload = try? JSONDecoder().decode(YahooSearchResponse.self, from: data) else {
            return []
        }

        var seen = Set<String>()
        return payload.quotes.compactMap(Self.candidate(from:)).filter {
            seen.insert($0.id).inserted
        }
    }

    private static func localCandidates(for input: String) -> [StockCandidate] {
        let lowered = input.lowercased()
        let known: [String: [StockCandidate]] = [
            "腾讯": [candidate(symbol: "00700", name: "腾讯控股", market: "HK", exchange: "HKG")],
            "腾讯控股": [candidate(symbol: "00700", name: "腾讯控股", market: "HK", exchange: "HKG")],
            "tencent": [candidate(symbol: "00700", name: "Tencent Holdings", market: "HK", exchange: "HKG")],
            "阿里巴巴": [
                candidate(symbol: "9988", name: "阿里巴巴", market: "HK", exchange: "HKG"),
                candidate(symbol: "BABA", name: "Alibaba Group", market: "US", exchange: "NYSE")
            ],
            "alibaba": [
                candidate(symbol: "9988", name: "阿里巴巴", market: "HK", exchange: "HKG"),
                candidate(symbol: "BABA", name: "Alibaba Group", market: "US", exchange: "NYSE")
            ],
            "百度": [
                candidate(symbol: "9888", name: "百度集团", market: "HK", exchange: "HKG"),
                candidate(symbol: "BIDU", name: "Baidu", market: "US", exchange: "NASDAQ")
            ],
            "baidu": [
                candidate(symbol: "9888", name: "百度集团", market: "HK", exchange: "HKG"),
                candidate(symbol: "BIDU", name: "Baidu", market: "US", exchange: "NASDAQ")
            ]
        ]
        if let match = known[lowered] { return match }

        let digits = input.filter(\.isNumber)
        guard digits == input else { return [] }
        if digits.count <= 5 {
            return [candidate(
                symbol: String(repeating: "0", count: max(0, 5 - digits.count)) + digits,
                name: "",
                market: "HK",
                exchange: "HKG"
            )]
        }
        if digits.count == 6 {
            return [candidate(symbol: digits, name: "", market: "CN", exchange: "CN")]
        }
        return []
    }

    private static func candidate(symbol: String, name: String, market: String, exchange: String) -> StockCandidate {
        StockCandidate(symbol: symbol, name: name, market: market, exchange: exchange)
    }

    private static func candidate(from quote: YahooQuote) -> StockCandidate? {
        guard let rawSymbol = quote.symbol,
              let market = market(for: rawSymbol, exchange: quote.exchange) else { return nil }
        let symbol = market == StockMarket.hk.code
            ? rawSymbol.replacingOccurrences(of: ".HK", with: "")
            : rawSymbol
        return StockCandidate(
            symbol: symbol,
            name: quote.longname ?? quote.shortname ?? "",
            market: market,
            exchange: quote.exchange ?? rawSymbol
        )
    }

    private static func market(for symbol: String, exchange: String?) -> String? {
        let upperSymbol = symbol.uppercased()
        let upperExchange = exchange?.uppercased() ?? ""
        if upperSymbol.hasSuffix(".HK") || upperExchange == "HKG" { return StockMarket.hk.code }
        if ["SHG", "SHE", "CN"].contains(upperExchange) || upperSymbol.hasSuffix(".SS") || upperSymbol.hasSuffix(".SZ") {
            return StockMarket.cn.code
        }
        if ["NMS", "NYQ", "NGM", "ASE", "BTS", "NASDAQ", "NYSE"].contains(upperExchange) {
            return StockMarket.us.code
        }
        return nil
    }
}

private struct YahooSearchResponse: Decodable {
    var quotes: [YahooQuote]
}

private struct YahooQuote: Decodable {
    var symbol: String?
    var shortname: String?
    var longname: String?
    var exchange: String?
}

protocol StockFetching {
    func fetch(_ stock: StockWatchlistItem) async throws -> [StockUpdate]
}

struct StockNewsClient: StockFetching {
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func fetch(_ stock: StockWatchlistItem) async throws -> [StockUpdate] {
        var updates: [StockUpdate] = []
        for kind in StockInfoKind.allCases {
            updates.append(contentsOf: try await fetch(kind: kind, stock: stock))
        }
        return updates
    }

    private func fetch(kind: StockInfoKind, stock: StockWatchlistItem) async throws -> [StockUpdate] {
        if kind == .deepReports {
            return try await fetchDeepReports(stock: stock)
        }

        guard var components = URLComponents(string: "https://news.google.com/rss/search") else {
            throw FeedError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query(for: kind, stock: stock)),
            URLQueryItem(name: "hl", value: locale(for: stock.market).hl),
            URLQueryItem(name: "gl", value: locale(for: stock.market).gl),
            URLQueryItem(name: "ceid", value: locale(for: stock.market).ceid)
        ]
        guard let url = components.url else { throw FeedError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("SignalDesk/0.1 contact=local-user@signalsdesk.app", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }

        return try FeedParser.parse(data: data)
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(40)
            .map { item in
                let text = "\(item.title) \(item.summary)"
                return StockUpdate(
                    id: "\(stock.id.uuidString)|\(kind.rawValue)|\(item.link ?? item.title)|\(item.publishedAt.timeIntervalSince1970)",
                    stockID: stock.id,
                    symbol: stock.symbol,
                    stockName: stock.name,
                    kind: kind,
                    title: item.title,
                    summary: item.summary,
                    url: item.link,
                    publishedAt: item.publishedAt,
                    importance: importance(for: kind, text: text),
                    pageCount: nil
                )
            }
    }

    private func fetchDeepReports(stock: StockWatchlistItem) async throws -> [StockUpdate] {
        let candidates = try await fetchReportCandidates(stock: stock)
        var reports: [StockUpdate] = []

        for candidate in candidates {
            guard let urlString = candidate.link,
                  let url = URL(string: urlString),
                  let (data, response) = try? await fetchDocument(url: url),
                  let document = PDFDocument(data: data),
                  StockResearchReportFilter.isEligible(
                      publishedAt: candidate.publishedAt,
                      pageCount: document.pageCount,
                      now: now()
                  ) else {
                continue
            }

            reports.append(
                StockUpdate(
                    id: "\(stock.id.uuidString)|deepReports|\(urlString)",
                    stockID: stock.id,
                    symbol: stock.symbol,
                    stockName: stock.name,
                    kind: .deepReports,
                    title: candidate.title,
                    summary: candidate.summary,
                    url: response.url?.absoluteString ?? urlString,
                    publishedAt: candidate.publishedAt,
                    importance: 82,
                    pageCount: document.pageCount
                )
            )
        }

        return reports
    }

    private func fetchReportCandidates(stock: StockWatchlistItem) async throws -> [ParsedFeedItem] {
        guard var components = URLComponents(string: "https://news.google.com/rss/search") else {
            throw FeedError.invalidURL
        }
        let symbol = stock.market.uppercased() == StockMarket.hk.code
            ? "\(stock.symbol).HK"
            : stock.symbol
        let identity = "\(stock.name) \(stock.symbol) \(symbol)".trimmingCharacters(in: .whitespaces)
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: "\(identity) (研报 OR 深度报告 OR 研究报告 OR \"equity research\" OR \"research report\") filetype:pdf"
            ),
            URLQueryItem(name: "hl", value: locale(for: stock.market).hl),
            URLQueryItem(name: "gl", value: locale(for: stock.market).gl),
            URLQueryItem(name: "ceid", value: locale(for: stock.market).ceid)
        ]
        guard let url = components.url else { throw FeedError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("SignalDesk/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }

        let now = now()
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: now)
            ?? now.addingTimeInterval(-180 * 24 * 60 * 60)
        return try FeedParser.parse(data: data)
            .filter { $0.publishedAt >= sixMonthsAgo && $0.publishedAt <= now }
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(30)
            .map { $0 }
    }

    private func fetchDocument(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("SignalDesk/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw FeedError.invalidResponse
        }
        return (data, response)
    }

    private func query(for kind: StockInfoKind, stock: StockWatchlistItem) -> String {
        let symbol = stock.market.uppercased() == StockMarket.hk.code
            ? "\(stock.symbol).HK"
            : stock.symbol
        let identity = "\(stock.name) \(stock.symbol) \(symbol)".trimmingCharacters(in: .whitespaces)
        switch kind {
        case .fundamentals:
            return "\(identity) (财报 OR 业绩 OR 营收 OR 利润 OR 指引 OR earnings OR results OR guidance)"
        case .news:
            return identity
        case .announcements:
            return "\(identity) (公告 OR 回购 OR 收购 OR 监管 OR 定增 OR filing OR announcement)"
        case .deepReports:
            return identity
        }
    }

    private func locale(for market: String) -> (hl: String, gl: String, ceid: String) {
        switch market.uppercased() {
        case StockMarket.cn.code:
            ("zh-CN", "CN", "CN:zh-Hans")
        case StockMarket.hk.code:
            ("zh-Hant", "HK", "HK:zh-Hant")
        default:
            ("en-US", "US", "US:en")
        }
    }

    private func importance(for kind: StockInfoKind, text: String) -> Int {
        let lowered = text.lowercased()
        let highImpact = ["财报", "业绩", "营收", "利润", "指引", "公告", "回购", "收购", "监管", "earnings", "guidance", "filing"]
        return min((kind == .announcements ? 78 : kind == .fundamentals ? 68 : 52) +
            min(highImpact.filter { lowered.contains($0) }.count * 4, 16), 100)
    }
}

struct StockRefreshResult {
    let addedUpdates: [StockUpdate]
    let checkedAtByStockID: [UUID: Date]
    let failures: [String]
    let refreshedAt: Date
}

struct StockRefreshCoordinator {
    private let client: any StockFetching
    private let now: () -> Date

    init(client: any StockFetching = StockNewsClient(), now: @escaping () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func refresh(
        watchlist: [StockWatchlistItem],
        existingUpdates: [StockUpdate]
    ) async -> StockRefreshResult {
        let refreshedAt = now()
        var knownIDs = Set(existingUpdates.map(\.id))
        var addedUpdates: [StockUpdate] = []
        var checkedAtByStockID: [UUID: Date] = [:]
        var failures: [String] = []

        for stock in watchlist where stock.isEnabled {
            do {
                let incoming = try await client.fetch(stock)
                for update in incoming where knownIDs.insert(update.id).inserted {
                    addedUpdates.append(update)
                }
                checkedAtByStockID[stock.id] = refreshedAt
            } catch {
                failures.append("\(stock.displayName)：\(error.localizedDescription)")
            }
        }

        return StockRefreshResult(
            addedUpdates: addedUpdates,
            checkedAtByStockID: checkedAtByStockID,
            failures: failures,
            refreshedAt: refreshedAt
        )
    }
}

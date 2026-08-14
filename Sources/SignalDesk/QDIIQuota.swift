import Combine
import Foundation
import UserNotifications

enum QDIIQuotaStatus: String, Codable, CaseIterable, Identifiable {
    case open
    case limited
    case suspended
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "开放申购"
        case .limited: "限制申购"
        case .suspended: "暂停申购"
        case .unknown: "状态待核验"
        }
    }

    var icon: String {
        switch self {
        case .open: "checkmark.circle.fill"
        case .limited: "exclamationmark.circle.fill"
        case .suspended: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

struct QDIIQuotaWatchItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var fundCode: String
    var fundName: String = ""
    var isEnabled = true
    var lastCheckedAt: Date?
}

struct QDIIQuotaObservation: Identifiable, Codable, Hashable {
    var fundCode: String
    var fundName: String
    var fundType: String?
    var status: QDIIQuotaStatus
    var dailyLimit: Double?
    var isUnlimited: Bool
    var sourceURL: String
    var sourceTitle: String
    var observedAt: Date
    var managementFeeRate: Double? = nil
    var custodyFeeRate: Double? = nil
    var salesServiceFeeRate: Double? = nil
    var feeSourceURL: String? = nil

    var id: String { fundCode }

    var limitTitle: String {
        if isUnlimited { return "不限额" }
        guard let dailyLimit else { return "未披露" }
        return "\(Self.numberFormatter.string(from: NSNumber(value: dailyLimit)) ?? "\(dailyLimit)") 元/日"
    }

    var canBuyMore: Bool {
        status == .open || status == .limited
    }

    var annualOperatingFeeRate: Double? {
        guard let managementFeeRate, let custodyFeeRate else { return nil }
        return managementFeeRate + custodyFeeRate + (salesServiceFeeRate ?? 0)
    }

    var isLowFeeRate: Bool {
        guard let annualOperatingFeeRate else { return false }
        return annualOperatingFeeRate < 0.8
    }

    var comprehensiveFeeTitle: String {
        guard let annualOperatingFeeRate else { return "待读取" }
        return "\(Self.percentFormatter.string(from: NSNumber(value: annualOperatingFeeRate)) ?? "\(annualOperatingFeeRate)")%/年"
    }

    var feeBreakdownTitle: String {
        let management = feeTitle(managementFeeRate)
        let custody = feeTitle(custodyFeeRate)
        let sales = feeTitle(salesServiceFeeRate)
        return "管理 \(management) · 托管 \(custody) · 销售服务 \(sales)"
    }

    static func isImprovement(from old: QDIIQuotaObservation, to new: QDIIQuotaObservation) -> Bool {
        if old.status == .suspended && new.canBuyMore { return true }
        if old.status == .limited && new.status == .open { return true }
        if new.isUnlimited && !old.isUnlimited { return true }
        if let oldLimit = old.dailyLimit, let newLimit = new.dailyLimit, newLimit > oldLimit {
            return true
        }
        return false
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private func feeTitle(_ value: Double?) -> String {
        guard let value else { return "未披露" }
        return "\(Self.percentFormatter.string(from: NSNumber(value: value)) ?? "\(value)")%"
    }

    init(
        fundCode: String,
        fundName: String,
        fundType: String?,
        status: QDIIQuotaStatus,
        dailyLimit: Double?,
        isUnlimited: Bool,
        sourceURL: String,
        sourceTitle: String,
        observedAt: Date,
        managementFeeRate: Double? = nil,
        custodyFeeRate: Double? = nil,
        salesServiceFeeRate: Double? = nil,
        feeSourceURL: String? = nil
    ) {
        self.fundCode = fundCode
        self.fundName = fundName
        self.fundType = fundType
        self.status = status
        self.dailyLimit = dailyLimit
        self.isUnlimited = isUnlimited
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.observedAt = observedAt
        self.managementFeeRate = managementFeeRate
        self.custodyFeeRate = custodyFeeRate
        self.salesServiceFeeRate = salesServiceFeeRate
        self.feeSourceURL = feeSourceURL
    }

    enum CodingKeys: String, CodingKey {
        case fundCode, fundName, fundType, status, dailyLimit, isUnlimited
        case sourceURL, sourceTitle, observedAt
        case managementFeeRate, custodyFeeRate, salesServiceFeeRate, feeSourceURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fundCode = try container.decode(String.self, forKey: .fundCode)
        fundName = try container.decode(String.self, forKey: .fundName)
        fundType = try container.decodeIfPresent(String.self, forKey: .fundType)
        status = try container.decode(QDIIQuotaStatus.self, forKey: .status)
        dailyLimit = try container.decodeIfPresent(Double.self, forKey: .dailyLimit)
        isUnlimited = try container.decode(Bool.self, forKey: .isUnlimited)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        sourceTitle = try container.decode(String.self, forKey: .sourceTitle)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
        managementFeeRate = try container.decodeIfPresent(Double.self, forKey: .managementFeeRate)
        custodyFeeRate = try container.decodeIfPresent(Double.self, forKey: .custodyFeeRate)
        salesServiceFeeRate = try container.decodeIfPresent(Double.self, forKey: .salesServiceFeeRate)
        feeSourceURL = try container.decodeIfPresent(String.self, forKey: .feeSourceURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fundCode, forKey: .fundCode)
        try container.encode(fundName, forKey: .fundName)
        try container.encodeIfPresent(fundType, forKey: .fundType)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(dailyLimit, forKey: .dailyLimit)
        try container.encode(isUnlimited, forKey: .isUnlimited)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(sourceTitle, forKey: .sourceTitle)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encodeIfPresent(managementFeeRate, forKey: .managementFeeRate)
        try container.encodeIfPresent(custodyFeeRate, forKey: .custodyFeeRate)
        try container.encodeIfPresent(salesServiceFeeRate, forKey: .salesServiceFeeRate)
        try container.encodeIfPresent(feeSourceURL, forKey: .feeSourceURL)
    }
}

struct QDIIQuotaChange: Identifiable, Codable, Hashable {
    var id = UUID()
    var fundCode: String
    var fundName: String
    var oldLimitTitle: String
    var newLimitTitle: String
    var oldStatus: QDIIQuotaStatus
    var newStatus: QDIIQuotaStatus
    var changedAt: Date
    var sourceURL: String
}

struct QDIIQuotaCache: Codable {
    var watchlist: [QDIIQuotaWatchItem]
    var observations: [QDIIQuotaObservation]
    var changes: [QDIIQuotaChange]
    var lastRefreshAt: Date?
    var installedFeaturedCatalogVersion: Int? = nil
}

enum QDIIQuotaError: LocalizedError {
    case invalidFundCode
    case invalidResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidFundCode: "基金代码应为 6 位数字"
        case .invalidResponse: "未读取到有效的基金额度页面"
        case .unavailable(let message): message
        }
    }
}

protocol QDIIQuotaFetching {
    func fetch(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation
}

struct EastMoneyQDIIQuotaClient: QDIIQuotaFetching {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation {
        let code = item.fundCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw QDIIQuotaError.invalidFundCode
        }
        guard let url = URL(string: "https://fund.eastmoney.com/\(code).html") else {
            throw QDIIQuotaError.invalidFundCode
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QDIIQuotaError.unavailable("基金 \(code) 页面请求失败")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw QDIIQuotaError.invalidResponse
        }
        var observation = try Self.parse(html: html, fundCode: code, fallbackName: item.fundName, observedAt: Date())
        if let feeURL = URL(string: "https://fundf10.eastmoney.com/jjfl_\(code).html") {
            var feeRequest = URLRequest(url: feeURL)
            feeRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            if let (feeData, feeResponse) = try? await session.data(for: feeRequest),
               let feeHTTP = feeResponse as? HTTPURLResponse,
               (200..<300).contains(feeHTTP.statusCode),
               let feeHTML = String(data: feeData, encoding: .utf8) {
                let rates = Self.parseFeeRates(html: feeHTML)
                observation.managementFeeRate = rates.management
                observation.custodyFeeRate = rates.custody
                observation.salesServiceFeeRate = rates.salesService
                observation.feeSourceURL = feeURL.absoluteString
            }
        }
        return observation
    }

    static func parse(
        html: String,
        fundCode: String,
        fallbackName: String = "",
        observedAt: Date
    ) throws -> QDIIQuotaObservation {
        let name = firstMatch(
            #"<span class="funCur-FundName">\s*([^<]+)"#,
            in: html
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackName
        guard !name.isEmpty else { throw QDIIQuotaError.invalidResponse }

        let statusText = firstMatch(
            #"交易状态：</span><span class="staticCell">\s*([^<]+)"#,
            in: html
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status: QDIIQuotaStatus
        if statusText.contains("暂停") || statusText.contains("停止") {
            status = .suspended
        } else if statusText.contains("限大额") || statusText.contains("限制") {
            status = .limited
        } else if statusText.contains("开放") {
            status = .open
        } else {
            status = .unknown
        }

        let limitText = firstPairMatch(
            #"单日累计(?:购买|申购)上限\s*([0-9,.]+)\s*(元|万|亿)"#,
            in: html
        )
        let dailyLimit: Double? = limitText.flatMap { pair in
            let (amount, unit) = pair
            guard let value = Double(amount.replacingOccurrences(of: ",", with: "")) else { return nil }
            switch unit {
            case "万": return value * 10_000
            case "亿": return value * 100_000_000
            default: return value
            }
        }
        let isUnlimited = html.contains("单日累计购买上限不限") || html.contains("单日累计申购上限不限")
        let fundType = firstMatch(#"<span class="ui-color-blue">([^<]+)</span>\s*\|"#, in: html)

        return QDIIQuotaObservation(
            fundCode: fundCode,
            fundName: name,
            fundType: fundType,
            status: status,
            dailyLimit: dailyLimit,
            isUnlimited: isUnlimited,
            sourceURL: "https://fund.eastmoney.com/\(fundCode).html",
            sourceTitle: "天天基金基金详情页（东方财富）",
            observedAt: observedAt,
            feeSourceURL: "https://fundf10.eastmoney.com/jjfl_\(fundCode).html"
        )
    }

    static func parseFeeRates(html: String) -> (management: Double?, custody: Double?, salesService: Double?) {
        (
            management: rateAfter(label: "管理费率", in: html),
            custody: rateAfter(label: "托管费率", in: html),
            salesService: rateAfter(label: "销售服务费率", in: html)
        )
    }

    private static func rateAfter(label: String, in text: String) -> Double? {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = "\(escapedLabel)</td>\\s*<td[^>]*>\\s*([0-9]+(?:\\.[0-9]+)?)%"
        guard let value = firstMatch(pattern, in: text) else { return nil }
        return Double(value)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private static func firstPairMatch(_ pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 2,
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[amountRange]), String(text[unitRange]))
    }
}

@MainActor
final class QDIIQuotaStore: ObservableObject {
    static let cacheValidity: TimeInterval = 15 * 60
    static let featuredCatalogVersion = 2
    private static let legacyFeaturedCodes: Set<String> = [
        "000834", "012752", "012860", "012870", "016055",
        "018064", "018065", "018966", "018967", "161125", "161130"
    ]
    static let featured: [QDIIQuotaWatchItem] = [
        QDIIQuotaWatchItem(fundCode: "000834", fundName: "大成纳斯达克100ETF联接(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "006075", fundName: "博时标普500ETF联接C"),
        QDIIQuotaWatchItem(fundCode: "006479", fundName: "广发纳斯达克100ETF联接人民币(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "007721", fundName: "天弘标普500发起(QDII-FOF)A"),
        QDIIQuotaWatchItem(fundCode: "007722", fundName: "天弘标普500发起(QDII-FOF)C"),
        QDIIQuotaWatchItem(fundCode: "008401", fundName: "大成标普500等权重指数(QDII)C人民币"),
        QDIIQuotaWatchItem(fundCode: "008971", fundName: "大成纳斯达克100ETF联接(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "012752", fundName: "建信纳斯达克100指数(QDII)C人民币"),
        QDIIQuotaWatchItem(fundCode: "012860", fundName: "易方达标普500指数人民币C"),
        QDIIQuotaWatchItem(fundCode: "012870", fundName: "易方达纳斯达克100ETF联接(QDII-LOF)C(人民币)"),
        QDIIQuotaWatchItem(fundCode: "014978", fundName: "华安纳斯达克100ETF联接(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "015299", fundName: "华夏纳斯达克100ETF发起式联接(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "015300", fundName: "华夏纳斯达克100ETF发起式联接(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "016055", fundName: "博时纳斯达克100ETF发起式联接(QDII)A人民币"),
        QDIIQuotaWatchItem(fundCode: "016057", fundName: "博时纳斯达克100ETF发起式联接(QDII)C人民币"),
        QDIIQuotaWatchItem(fundCode: "016452", fundName: "南方纳斯达克100指数发起(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "016453", fundName: "南方纳斯达克100指数发起(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "016532", fundName: "嘉实纳斯达克100ETF发起联接(QDII)A人民币"),
        QDIIQuotaWatchItem(fundCode: "016533", fundName: "嘉实纳斯达克100ETF发起联接(QDII)C人民币"),
        QDIIQuotaWatchItem(fundCode: "017028", fundName: "国泰标普500ETF发起联接(QDII)A人民币"),
        QDIIQuotaWatchItem(fundCode: "017030", fundName: "国泰标普500ETF发起联接(QDII)C人民币"),
        QDIIQuotaWatchItem(fundCode: "017641", fundName: "摩根标普500指数(QDII)人民币A"),
        QDIIQuotaWatchItem(fundCode: "018043", fundName: "天弘纳斯达克100指数发起(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "018044", fundName: "天弘纳斯达克100指数发起(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "018064", fundName: "华夏标普500ETF发起式联接(QDII)A(人民币)"),
        QDIIQuotaWatchItem(fundCode: "018065", fundName: "华夏标普500ETF发起式联接(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "018738", fundName: "博时标普500ETF联接E(人民币)"),
        QDIIQuotaWatchItem(fundCode: "018966", fundName: "汇添富纳斯达克100ETF发起式联接(QDII)人民币A"),
        QDIIQuotaWatchItem(fundCode: "018967", fundName: "汇添富纳斯达克100ETF发起式联接(QDII)人民币C"),
        QDIIQuotaWatchItem(fundCode: "019172", fundName: "摩根纳斯达克100指数(QDII)人民币A"),
        QDIIQuotaWatchItem(fundCode: "019173", fundName: "摩根纳斯达克100指数(QDII)人民币C"),
        QDIIQuotaWatchItem(fundCode: "019305", fundName: "摩根标普500指数(QDII)人民币C"),
        QDIIQuotaWatchItem(fundCode: "019441", fundName: "万家纳斯达克100指数发起式(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "019442", fundName: "万家纳斯达克100指数发起式(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "019524", fundName: "华泰柏瑞纳斯达克100ETF发起式联接(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "019525", fundName: "华泰柏瑞纳斯达克100ETF发起式联接(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "019547", fundName: "招商纳斯达克100ETF发起式联接(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "019548", fundName: "招商纳斯达克100ETF发起式联接(QDII)C"),
        QDIIQuotaWatchItem(fundCode: "019736", fundName: "宝盈纳斯达克100指数发起(QDII)A人民币"),
        QDIIQuotaWatchItem(fundCode: "019737", fundName: "宝盈纳斯达克100指数发起(QDII)C人民币"),
        QDIIQuotaWatchItem(fundCode: "021000", fundName: "南方纳斯达克100指数发起(QDII)I"),
        QDIIQuotaWatchItem(fundCode: "021773", fundName: "汇添富纳斯达克100ETF发起式联接(QDII)人民币E"),
        QDIIQuotaWatchItem(fundCode: "021838", fundName: "嘉实纳斯达克100ETF发起联接(QDII)I人民币"),
        QDIIQuotaWatchItem(fundCode: "022523", fundName: "天弘标普500发起(QDII-FOF)D"),
        QDIIQuotaWatchItem(fundCode: "022525", fundName: "天弘纳斯达克100指数发起(QDII)D"),
        QDIIQuotaWatchItem(fundCode: "022664", fundName: "华泰柏瑞纳斯达克100ETF发起式联接(QDII)I"),
        QDIIQuotaWatchItem(fundCode: "023422", fundName: "建信纳斯达克100指数(QDII)D人民币"),
        QDIIQuotaWatchItem(fundCode: "024237", fundName: "博时纳斯达克100ETF发起式联接(QDII)I人民币"),
        QDIIQuotaWatchItem(fundCode: "040046", fundName: "华安纳斯达克100ETF联接(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "050025", fundName: "博时标普500ETF联接A"),
        QDIIQuotaWatchItem(fundCode: "096001", fundName: "大成标普500等权重指数(QDII)A人民币"),
        QDIIQuotaWatchItem(fundCode: "160213", fundName: "国泰纳斯达克100指数"),
        QDIIQuotaWatchItem(fundCode: "161125", fundName: "易方达标普500指数人民币A"),
        QDIIQuotaWatchItem(fundCode: "161130", fundName: "易方达纳斯达克100ETF联接(QDII-LOF)A(人民币)"),
        QDIIQuotaWatchItem(fundCode: "270042", fundName: "广发纳斯达克100ETF联接人民币(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "539001", fundName: "建信纳斯达克100指数(QDII)A人民币")
    ]

    @Published private(set) var watchlist: [QDIIQuotaWatchItem] = []
    @Published private(set) var observations: [String: QDIIQuotaObservation] = [:]
    @Published private(set) var changes: [QDIIQuotaChange] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var isRefreshing = false
    @Published var statusMessage: String?

    private let stateURL: URL
    private let client: any QDIIQuotaFetching
    private let notificationsEnabled: Bool
    private var installedFeaturedCatalogVersion = 1

    init(
        stateURL: URL? = nil,
        client: any QDIIQuotaFetching = EastMoneyQDIIQuotaClient(),
        notificationsEnabled: Bool = true
    ) {
        self.stateURL = stateURL ?? Self.defaultStateURL
        self.client = client
        self.notificationsEnabled = notificationsEnabled
        load()
        installFeaturedIfNeeded()
    }

    var enabledCount: Int { watchlist.filter(\.isEnabled).count }

    func observation(for fundCode: String) -> QDIIQuotaObservation? {
        observations[fundCode]
    }

    @discardableResult
    func addFund(code: String, name: String = "") -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count == 6, normalized.allSatisfy(\.isNumber),
              !watchlist.contains(where: { $0.fundCode == normalized }) else { return false }
        watchlist.append(QDIIQuotaWatchItem(fundCode: normalized, fundName: name.trimmingCharacters(in: .whitespacesAndNewlines)))
        save()
        return true
    }

    func removeFund(_ fundCode: String) {
        watchlist.removeAll { $0.fundCode == fundCode }
        observations[fundCode] = nil
        save()
    }

    func toggle(_ item: QDIIQuotaWatchItem) {
        guard let index = watchlist.firstIndex(where: { $0.id == item.id }) else { return }
        watchlist[index].isEnabled.toggle()
        save()
    }

    func refreshIfStale(now: Date = Date()) async {
        guard lastRefreshAt == nil || now.timeIntervalSince(lastRefreshAt!) >= Self.cacheValidity else { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = nil
        defer { isRefreshing = false }

        var failures: [String] = []
        var improved: [QDIIQuotaObservation] = []
        let refreshedAt = Date()
        let enabledItems = watchlist.filter(\.isEnabled)
        for item in enabledItems {
            do {
                let observation = try await client.fetch(item)
                if let old = observations[item.fundCode], QDIIQuotaObservation.isImprovement(from: old, to: observation) {
                    changes.insert(
                        QDIIQuotaChange(
                            fundCode: observation.fundCode,
                            fundName: observation.fundName,
                            oldLimitTitle: old.limitTitle,
                            newLimitTitle: observation.limitTitle,
                            oldStatus: old.status,
                            newStatus: observation.status,
                            changedAt: observation.observedAt,
                            sourceURL: observation.sourceURL
                        ),
                        at: 0
                    )
                    improved.append(observation)
                }
                observations[item.fundCode] = observation
                if let index = watchlist.firstIndex(where: { $0.id == item.id }) {
                    watchlist[index].lastCheckedAt = refreshedAt
                    if watchlist[index].fundName.isEmpty { watchlist[index].fundName = observation.fundName }
                }
            } catch {
                failures.append("\(item.fundCode)：\(error.localizedDescription)")
            }
        }
        changes = Array(changes.prefix(200))
        lastRefreshAt = refreshedAt
        statusMessage = failures.isEmpty
            ? (improved.isEmpty ? "额度已是最新" : "发现 \(improved.count) 个额度改善")
            : "成功 \(enabledItems.count - failures.count) 个；失败 \(failures.count)：\(failures[0])"
        save()
        if notificationsEnabled { await notify(for: improved) }
    }

    private func installFeaturedIfNeeded() {
        if watchlist.isEmpty {
            watchlist = Self.featured
            installedFeaturedCatalogVersion = Self.featuredCatalogVersion
            save()
            return
        }
        guard installedFeaturedCatalogVersion < Self.featuredCatalogVersion else { return }
        let existingCodes = Set(watchlist.map(\.fundCode))
        let additions = Self.featured.filter {
            !Self.legacyFeaturedCodes.contains($0.fundCode) && !existingCodes.contains($0.fundCode)
        }
        watchlist.append(contentsOf: additions)
        installedFeaturedCatalogVersion = Self.featuredCatalogVersion
        if !additions.isEmpty { save() }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: stateURL)
            let cache = try JSONDecoder.qdiiQuota.decode(QDIIQuotaCache.self, from: data)
            watchlist = cache.watchlist
            observations = Dictionary(uniqueKeysWithValues: cache.observations.map { ($0.fundCode, $0) })
            changes = cache.changes
            lastRefreshAt = cache.lastRefreshAt
            installedFeaturedCatalogVersion = cache.installedFeaturedCatalogVersion ?? 1
        } catch {
            watchlist = []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let cache = QDIIQuotaCache(
                watchlist: watchlist,
                observations: observations.values.sorted { $0.fundCode < $1.fundCode },
                changes: changes,
                lastRefreshAt: lastRefreshAt,
                installedFeaturedCatalogVersion: installedFeaturedCatalogVersion
            )
            try JSONEncoder.qdiiQuota.encode(cache).write(to: stateURL, options: .atomic)
        } catch {
            statusMessage = "额度缓存保存失败：\(error.localizedDescription)"
        }
    }

    private func notify(for observations: [QDIIQuotaObservation]) async {
        guard !observations.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "QDII 基金额度有变化"
        content.body = observations.count == 1
            ? "\(observations[0].fundName)：现在\(observations[0].limitTitle)"
            : "有 \(observations.count) 只基金的申购额度增加或恢复"
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SignalDesk", directoryHint: .isDirectory)
            .appending(path: "qdii-quotas.json")
    }
}

private extension JSONEncoder {
    static var qdiiQuota: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var qdiiQuota: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

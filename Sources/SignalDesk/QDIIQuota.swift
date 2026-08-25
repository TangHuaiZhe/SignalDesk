import Combine
import Foundation
import PDFKit
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

enum QDIIQuotaChannel: String, Codable, CaseIterable, Identifiable {
    case direct
    case tiantian
    case xueqiu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: "基金公司直销"
        case .tiantian: "天天基金"
        case .xueqiu: "雪球"
        }
    }
}

enum QDIIFundMarket: String, Codable, CaseIterable, Identifiable {
    case exchangeTraded
    case overTheCounter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exchangeTraded: "场内基金"
        case .overTheCounter: "场外基金"
        }
    }

    var subtitle: String {
        switch self {
        case .exchangeTraded: "ETF / LOF 行情"
        case .overTheCounter: "申购额度"
        }
    }
}

struct QDIIQuotaWatchItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var fundCode: String
    var fundName: String = ""
    var market: QDIIFundMarket = .overTheCounter
    var isEnabled = true
    var lastCheckedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, fundCode, fundName, market, isEnabled, lastCheckedAt
    }

    init(
        id: UUID = UUID(),
        fundCode: String,
        fundName: String = "",
        market: QDIIFundMarket = .overTheCounter,
        isEnabled: Bool = true,
        lastCheckedAt: Date? = nil
    ) {
        self.id = id
        self.fundCode = fundCode
        self.fundName = fundName
        self.market = market
        self.isEnabled = isEnabled
        self.lastCheckedAt = lastCheckedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fundCode = try container.decode(String.self, forKey: .fundCode)
        fundName = try container.decodeIfPresent(String.self, forKey: .fundName) ?? ""
        market = try container.decodeIfPresent(QDIIFundMarket.self, forKey: .market) ?? .overTheCounter
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fundCode, forKey: .fundCode)
        try container.encode(fundName, forKey: .fundName)
        try container.encode(market, forKey: .market)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
    }
}

struct QDIIQuotaObservation: Identifiable, Codable, Hashable {
    var fundCode: String
    var fundName: String
    var channel: QDIIQuotaChannel
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

    var id: String { storageKey }

    var storageKey: String { "\(fundCode):\(channel.rawValue)" }

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

    static func comesBeforeByPurchaseQuota(
        _ lhs: QDIIQuotaObservation?,
        _ rhs: QDIIQuotaObservation?
    ) -> Bool {
        let leftRank = purchaseQuotaRank(lhs)
        let rightRank = purchaseQuotaRank(rhs)
        if leftRank != rightRank { return leftRank > rightRank }

        if let leftLimit = lhs?.dailyLimit, let rightLimit = rhs?.dailyLimit, leftLimit != rightLimit {
            return leftLimit > rightLimit
        }
        if (lhs?.dailyLimit != nil) != (rhs?.dailyLimit != nil) {
            return lhs?.dailyLimit != nil
        }

        let leftStatusRank = lhs?.status == .open ? 2 : (lhs?.status == .limited ? 1 : 0)
        let rightStatusRank = rhs?.status == .open ? 2 : (rhs?.status == .limited ? 1 : 0)
        return leftStatusRank > rightStatusRank
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

    private static func purchaseQuotaRank(_ observation: QDIIQuotaObservation?) -> Int {
        guard let observation, observation.canBuyMore else { return 0 }
        if observation.isUnlimited { return 3 }
        if observation.dailyLimit != nil { return 2 }
        return 1
    }

    init(
        fundCode: String,
        fundName: String,
        channel: QDIIQuotaChannel = .tiantian,
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
        self.channel = channel
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
        case fundCode, fundName, channel, fundType, status, dailyLimit, isUnlimited
        case sourceURL, sourceTitle, observedAt
        case managementFeeRate, custodyFeeRate, salesServiceFeeRate, feeSourceURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fundCode = try container.decode(String.self, forKey: .fundCode)
        fundName = try container.decode(String.self, forKey: .fundName)
        channel = try container.decodeIfPresent(QDIIQuotaChannel.self, forKey: .channel) ?? .tiantian
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
        try container.encode(channel, forKey: .channel)
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

struct QDIIExchangeObservation: Identifiable, Codable, Hashable {
    var fundCode: String
    var fundName: String
    var lastPrice: Double
    var netAssetValue: Double?
    var premiumRate: Double?
    var premiumRateIsEstimated: Bool
    var changeAmount: Double?
    var changePercent: Double?
    var volume: Double?
    var turnover: Double?
    var turnoverRate: Double?
    var sourceURL: String
    var sourceTitle: String
    var observedAt: Date
    var managementFeeRate: Double? = nil
    var custodyFeeRate: Double? = nil
    var salesServiceFeeRate: Double? = nil
    var feeSourceURL: String? = nil

    var id: String { fundCode }

    var premiumRateTitle: String {
        guard let premiumRate else { return "待刷新" }
        let value = Self.percentFormatter.string(from: NSNumber(value: abs(premiumRate))) ?? "\(abs(premiumRate))"
        return premiumRate >= 0 ? "+\(value)%" : "-\(value)%"
    }

    var premiumRateSourceTitle: String {
        premiumRateIsEstimated ? "按最新公布净值估算" : "实时 IOPV"
    }

    var premiumColorIsPositive: Bool { (premiumRate ?? 0) >= 0 }

    var netAssetValueTitle: String {
        guard let netAssetValue else { return "待刷新" }
        return Self.priceFormatter.string(from: NSNumber(value: netAssetValue)) ?? "\(netAssetValue)"
    }

    var priceTitle: String {
        Self.priceFormatter.string(from: NSNumber(value: lastPrice)) ?? "\(lastPrice)"
    }

    var changePercentTitle: String {
        guard let changePercent else { return "待读取" }
        let value = Self.percentFormatter.string(from: NSNumber(value: abs(changePercent))) ?? "\(abs(changePercent))"
        return changePercent >= 0 ? "+\(value)%" : "-\(value)%"
    }

    var changeColorIsPositive: Bool { (changePercent ?? 0) >= 0 }

    var turnoverTitle: String {
        guard let turnover else { return "待读取" }
        if turnover >= 100_000_000 {
            return "\(Self.amountFormatter.string(from: NSNumber(value: turnover / 100_000_000)) ?? "\(turnover / 100_000_000)")亿"
        }
        if turnover >= 10_000 {
            return "\(Self.amountFormatter.string(from: NSNumber(value: turnover / 10_000)) ?? "\(turnover / 10_000)")万"
        }
        return "\(Self.amountFormatter.string(from: NSNumber(value: turnover)) ?? "\(turnover)")元"
    }

    var volumeTitle: String {
        guard let volume else { return "待读取" }
        return Self.amountFormatter.string(from: NSNumber(value: volume)) ?? "\(volume)"
    }

    var turnoverRateTitle: String {
        guard let turnoverRate else { return "待读取" }
        return "\(Self.percentFormatter.string(from: NSNumber(value: turnoverRate)) ?? "\(turnoverRate)")%"
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
        "管理 \(feeTitle(managementFeeRate)) · 托管 \(feeTitle(custodyFeeRate)) · 销售服务 \(feeTitle(salesServiceFeeRate))"
    }

    static func comesBeforeByTurnover(
        _ lhs: QDIIExchangeObservation?,
        _ rhs: QDIIExchangeObservation?
    ) -> Bool {
        let left = lhs?.turnover ?? -1
        let right = rhs?.turnover ?? -1
        if left != right { return left > right }
        return (lhs?.fundCode ?? "") < (rhs?.fundCode ?? "")
    }

    static func comesBeforeByPremium(
        _ lhs: QDIIExchangeObservation?,
        _ rhs: QDIIExchangeObservation?
    ) -> Bool {
        let left = lhs?.premiumRate ?? -.infinity
        let right = rhs?.premiumRate ?? -.infinity
        if left != right { return left > right }
        return comesBeforeByTurnover(lhs, rhs)
    }

    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 3
        formatter.maximumFractionDigits = 4
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

    private static let amountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
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
        lastPrice: Double,
        netAssetValue: Double? = nil,
        premiumRate: Double? = nil,
        premiumRateIsEstimated: Bool = false,
        changeAmount: Double?,
        changePercent: Double?,
        volume: Double?,
        turnover: Double?,
        turnoverRate: Double?,
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
        self.lastPrice = lastPrice
        self.netAssetValue = netAssetValue
        self.premiumRate = premiumRate
        self.premiumRateIsEstimated = premiumRateIsEstimated
        self.changeAmount = changeAmount
        self.changePercent = changePercent
        self.volume = volume
        self.turnover = turnover
        self.turnoverRate = turnoverRate
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.observedAt = observedAt
        self.managementFeeRate = managementFeeRate
        self.custodyFeeRate = custodyFeeRate
        self.salesServiceFeeRate = salesServiceFeeRate
        self.feeSourceURL = feeSourceURL
    }

    enum CodingKeys: String, CodingKey {
        case fundCode, fundName, lastPrice, netAssetValue, premiumRate, premiumRateIsEstimated
        case changeAmount, changePercent, volume, turnover, turnoverRate
        case sourceURL, sourceTitle, observedAt
        case managementFeeRate, custodyFeeRate, salesServiceFeeRate, feeSourceURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fundCode = try container.decode(String.self, forKey: .fundCode)
        fundName = try container.decode(String.self, forKey: .fundName)
        lastPrice = try container.decode(Double.self, forKey: .lastPrice)
        netAssetValue = try container.decodeIfPresent(Double.self, forKey: .netAssetValue)
        premiumRate = try container.decodeIfPresent(Double.self, forKey: .premiumRate)
        premiumRateIsEstimated = try container.decodeIfPresent(Bool.self, forKey: .premiumRateIsEstimated) ?? false
        changeAmount = try container.decodeIfPresent(Double.self, forKey: .changeAmount)
        changePercent = try container.decodeIfPresent(Double.self, forKey: .changePercent)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume)
        turnover = try container.decodeIfPresent(Double.self, forKey: .turnover)
        turnoverRate = try container.decodeIfPresent(Double.self, forKey: .turnoverRate)
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
        try container.encode(lastPrice, forKey: .lastPrice)
        try container.encodeIfPresent(netAssetValue, forKey: .netAssetValue)
        try container.encodeIfPresent(premiumRate, forKey: .premiumRate)
        try container.encode(premiumRateIsEstimated, forKey: .premiumRateIsEstimated)
        try container.encodeIfPresent(changeAmount, forKey: .changeAmount)
        try container.encodeIfPresent(changePercent, forKey: .changePercent)
        try container.encodeIfPresent(volume, forKey: .volume)
        try container.encodeIfPresent(turnover, forKey: .turnover)
        try container.encodeIfPresent(turnoverRate, forKey: .turnoverRate)
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
    var channel: QDIIQuotaChannel
    var oldLimitTitle: String
    var newLimitTitle: String
    var oldStatus: QDIIQuotaStatus
    var newStatus: QDIIQuotaStatus
    var changedAt: Date
    var sourceURL: String

    init(
        id: UUID = UUID(),
        fundCode: String,
        fundName: String,
        channel: QDIIQuotaChannel = .tiantian,
        oldLimitTitle: String,
        newLimitTitle: String,
        oldStatus: QDIIQuotaStatus,
        newStatus: QDIIQuotaStatus,
        changedAt: Date,
        sourceURL: String
    ) {
        self.id = id
        self.fundCode = fundCode
        self.fundName = fundName
        self.channel = channel
        self.oldLimitTitle = oldLimitTitle
        self.newLimitTitle = newLimitTitle
        self.oldStatus = oldStatus
        self.newStatus = newStatus
        self.changedAt = changedAt
        self.sourceURL = sourceURL
    }

    enum CodingKeys: String, CodingKey {
        case id, fundCode, fundName, channel, oldLimitTitle, newLimitTitle
        case oldStatus, newStatus, changedAt, sourceURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fundCode = try container.decode(String.self, forKey: .fundCode)
        fundName = try container.decode(String.self, forKey: .fundName)
        channel = try container.decodeIfPresent(QDIIQuotaChannel.self, forKey: .channel) ?? .tiantian
        oldLimitTitle = try container.decode(String.self, forKey: .oldLimitTitle)
        newLimitTitle = try container.decode(String.self, forKey: .newLimitTitle)
        oldStatus = try container.decode(QDIIQuotaStatus.self, forKey: .oldStatus)
        newStatus = try container.decode(QDIIQuotaStatus.self, forKey: .newStatus)
        changedAt = try container.decode(Date.self, forKey: .changedAt)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fundCode, forKey: .fundCode)
        try container.encode(fundName, forKey: .fundName)
        try container.encode(channel, forKey: .channel)
        try container.encode(oldLimitTitle, forKey: .oldLimitTitle)
        try container.encode(newLimitTitle, forKey: .newLimitTitle)
        try container.encode(oldStatus, forKey: .oldStatus)
        try container.encode(newStatus, forKey: .newStatus)
        try container.encode(changedAt, forKey: .changedAt)
        try container.encode(sourceURL, forKey: .sourceURL)
    }
}

struct QDIIQuotaCache: Codable {
    var watchlist: [QDIIQuotaWatchItem]
    var observations: [QDIIQuotaObservation]
    var exchangeObservations: [QDIIExchangeObservation]
    var changes: [QDIIQuotaChange]
    var lastRefreshAt: Date?
    var installedFeaturedCatalogVersion: Int? = nil

    enum CodingKeys: String, CodingKey {
        case watchlist, observations, exchangeObservations, changes, lastRefreshAt, installedFeaturedCatalogVersion
    }

    init(
        watchlist: [QDIIQuotaWatchItem],
        observations: [QDIIQuotaObservation],
        exchangeObservations: [QDIIExchangeObservation] = [],
        changes: [QDIIQuotaChange],
        lastRefreshAt: Date?,
        installedFeaturedCatalogVersion: Int? = nil
    ) {
        self.watchlist = watchlist
        self.observations = observations
        self.exchangeObservations = exchangeObservations
        self.changes = changes
        self.lastRefreshAt = lastRefreshAt
        self.installedFeaturedCatalogVersion = installedFeaturedCatalogVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        watchlist = try container.decode([QDIIQuotaWatchItem].self, forKey: .watchlist)
        observations = try container.decode([QDIIQuotaObservation].self, forKey: .observations)
        exchangeObservations = try container.decodeIfPresent([QDIIExchangeObservation].self, forKey: .exchangeObservations) ?? []
        changes = try container.decode([QDIIQuotaChange].self, forKey: .changes)
        lastRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshAt)
        installedFeaturedCatalogVersion = try container.decodeIfPresent(Int.self, forKey: .installedFeaturedCatalogVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(watchlist, forKey: .watchlist)
        try container.encode(observations, forKey: .observations)
        try container.encode(exchangeObservations, forKey: .exchangeObservations)
        try container.encode(changes, forKey: .changes)
        try container.encodeIfPresent(lastRefreshAt, forKey: .lastRefreshAt)
        try container.encodeIfPresent(installedFeaturedCatalogVersion, forKey: .installedFeaturedCatalogVersion)
    }
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
    func fetchExchange(_ item: QDIIQuotaWatchItem) async throws -> QDIIExchangeObservation?
    func fetchDirect(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation?
    func fetchXueqiu(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation?
}

extension QDIIQuotaFetching {
    func fetchExchange(_ item: QDIIQuotaWatchItem) async throws -> QDIIExchangeObservation? {
        nil
    }

    func fetchDirect(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation? {
        nil
    }

    func fetchXueqiu(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation? {
        nil
    }
}

struct XueqiuQuotaRecord: Hashable {
    var fundCode: String
    var fundName: String
    var recommendation: String
}

struct XueqiuQuotaPage {
    var records: [XueqiuQuotaRecord]
    var observedAt: Date
}

struct QDIIExchangePremiumQuote: Hashable {
    var netAssetValue: Double?
    var premiumRate: Double
    var isEstimated: Bool
}

struct QDIIExchangePremiumRecord: Hashable, Sendable {
    var netAssetValue: Double?
    var premiumRate: Double?
}

actor XueqiuQuotaPageCache {
    private var pages: [Int: XueqiuQuotaPage] = [:]
    private let validity: TimeInterval = 15 * 60

    func page(for activityID: Int, now: Date) -> XueqiuQuotaPage? {
        guard let page = pages[activityID], now.timeIntervalSince(page.observedAt) < validity else {
            return nil
        }
        return page
    }

    func store(_ page: XueqiuQuotaPage, for activityID: Int) {
        pages[activityID] = page
    }
}

actor QDIIExchangePremiumCache {
    private var records: [String: QDIIExchangePremiumRecord] = [:]
    private var observedAt: Date?
    private let validity: TimeInterval = 60

    func records(now: Date) -> [String: QDIIExchangePremiumRecord]? {
        guard let observedAt, now.timeIntervalSince(observedAt) < validity else { return nil }
        return records
    }

    func store(_ records: [String: QDIIExchangePremiumRecord], observedAt: Date) {
        self.records = records
        self.observedAt = observedAt
    }
}

struct EastMoneyQDIIQuotaClient: QDIIQuotaFetching {
    private let session: URLSession
    private static let xueqiuPageCache = XueqiuQuotaPageCache()
    private static let exchangePremiumCache = QDIIExchangePremiumCache()

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

    func fetchExchange(_ item: QDIIQuotaWatchItem) async throws -> QDIIExchangeObservation? {
        let code = item.fundCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw QDIIQuotaError.invalidFundCode
        }
        let secid = Self.exchangeSecID(for: code)
        let fields = "f43,f47,f48,f57,f58,f60,f168,f169,f170"
        guard let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=\(fields)") else {
            throw QDIIQuotaError.invalidFundCode
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QDIIQuotaError.unavailable("场内基金 \(code) 行情请求失败")
        }
        var observation = try Self.parseExchangeQuote(
            data: data,
            fundCode: code,
            fallbackName: item.fundName,
            observedAt: Date()
        )
        if let premium = try? await fetchExchangePremium(fundCode: code, lastPrice: observation.lastPrice) {
            observation.netAssetValue = premium.netAssetValue
            observation.premiumRate = premium.premiumRate
            observation.premiumRateIsEstimated = premium.isEstimated
        }
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

    private func fetchExchangePremium(
        fundCode: String,
        lastPrice: Double
    ) async throws -> QDIIExchangePremiumQuote? {
        let now = Date()
        let records: [String: QDIIExchangePremiumRecord]
        if let cached = await Self.exchangePremiumCache.records(now: now) {
            records = cached
        } else {
            if let fetched = try? await fetchExchangePremiumRecords() {
                records = fetched
                await Self.exchangePremiumCache.store(records, observedAt: now)
            } else {
                records = [:]
            }
        }

        if let record = records[fundCode], let premiumRate = record.premiumRate {
            return QDIIExchangePremiumQuote(
                netAssetValue: record.netAssetValue,
                premiumRate: premiumRate,
                isEstimated: false
            )
        }

        if let record = records[fundCode], let netAssetValue = record.netAssetValue,
           netAssetValue > 0, lastPrice > 0 {
            return QDIIExchangePremiumQuote(
                netAssetValue: netAssetValue,
                premiumRate: (lastPrice / netAssetValue - 1) * 100,
                isEstimated: false
            )
        }

        guard let pageURL = URL(string: "https://fund.eastmoney.com/cnjy_dwjz.html") else {
            return nil
        }
        var pageRequest = URLRequest(url: pageURL)
        pageRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (pageData, pageResponse) = try await session.data(for: pageRequest)
        guard let pageHTTP = pageResponse as? HTTPURLResponse,
              (200..<300).contains(pageHTTP.statusCode),
              let html = String(data: pageData, encoding: .utf8) else {
            return nil
        }
        return Self.parseExchangeDailyFundPage(html: html, fundCode: fundCode, fallbackMarketPrice: lastPrice)
    }

    private func fetchExchangePremiumRecords() async throws -> [String: QDIIExchangePremiumRecord] {
        var records: [String: QDIIExchangePremiumRecord] = [:]
        let pageSize = 100
        for page in 1...20 {
            var components = URLComponents(string: "https://push2delay.eastmoney.com/api/qt/clist/get")!
            components.queryItems = [
                URLQueryItem(name: "pn", value: "\(page)"),
                URLQueryItem(name: "pz", value: "\(pageSize)"),
                URLQueryItem(name: "po", value: "1"),
                URLQueryItem(name: "np", value: "1"),
                URLQueryItem(name: "ut", value: "bd1d9ddb04089700cf9c27f6f7426281"),
                URLQueryItem(name: "fltt", value: "2"),
                URLQueryItem(name: "invt", value: "2"),
                URLQueryItem(name: "wbp2u", value: "|0|0|web"),
                URLQueryItem(name: "fid", value: "f12"),
                URLQueryItem(name: "fs", value: "b:MK0021,b:MK0022,b:MK0023,b:MK0024"),
                URLQueryItem(name: "fields", value: "f2,f12,f14,f18,f402,f441")
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw QDIIQuotaError.unavailable("场内基金溢价率请求失败")
            }
            let pageRecords = Self.parseExchangePremiumRecords(data: data)
            records.merge(pageRecords) { current, _ in current }
            if pageRecords.count < pageSize { break }
        }
        return records
    }

    func fetchDirect(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation? {
        let code = item.fundCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw QDIIQuotaError.invalidFundCode
        }

        let announcements = try await fetchAnnouncements(fundCode: code)
        guard let announcement = announcements.first(where: Self.isDirectQuotaAnnouncement) else {
            return nil
        }
        guard let pdfURL = URL(string: "https://pdf.dfcfw.com/pdf/H2_\(announcement.id)_1.pdf") else {
            return nil
        }
        var request = URLRequest(url: pdfURL)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let document = PDFDocument(data: data),
              let text = document.string else {
            return nil
        }
        let parsed = Self.parseDirectQuota(text: text, fundCode: code)
        return QDIIQuotaObservation(
            fundCode: code,
            fundName: item.fundName,
            channel: .direct,
            fundType: nil,
            status: parsed.status,
            dailyLimit: parsed.dailyLimit,
            isUnlimited: parsed.isUnlimited,
            sourceURL: pdfURL.absoluteString,
            sourceTitle: announcement.title,
            observedAt: Date()
        )
    }

    func fetchXueqiu(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation? {
        let code = item.fundCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw QDIIQuotaError.invalidFundCode
        }

        let activityIDs: [Int]
        if item.fundName.contains("标普") {
            activityIDs = [577]
        } else if item.fundName.contains("纳斯达克") {
            activityIDs = [561]
        } else {
            activityIDs = [561, 577]
        }

        for activityID in activityIDs {
            let now = Date()
            let page: XueqiuQuotaPage
            if let cached = await Self.xueqiuPageCache.page(for: activityID, now: now) {
                page = cached
            } else {
                let url = URL(string: "https://xueqiu.com/snowball-activity/rank/\(activityID)")!
                var request = URLRequest(url: url)
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let html = String(data: data, encoding: .utf8) else {
                    throw QDIIQuotaError.unavailable("雪球基金榜单请求失败")
                }
                let fetched = XueqiuQuotaPage(
                    records: try Self.parseXueqiuQuotaPage(html: html),
                    observedAt: now
                )
                await Self.xueqiuPageCache.store(fetched, for: activityID)
                page = fetched
            }

            guard let record = page.records.first(where: { $0.fundCode == code }) else {
                continue
            }
            let parsed = Self.parseXueqiuRecommendation(record.recommendation)
            let title = activityID == 577 ? "雪球标普500基金榜单" : "雪球纳斯达克100基金榜单"
            return QDIIQuotaObservation(
                fundCode: code,
                fundName: record.fundName,
                channel: .xueqiu,
                fundType: nil,
                status: parsed.status,
                dailyLimit: parsed.dailyLimit,
                isUnlimited: parsed.isUnlimited,
                sourceURL: "https://xueqiu.com/snowball-activity/rank/\(activityID)",
                sourceTitle: title,
                observedAt: page.observedAt
            )
        }
        return nil
    }

    static func parseXueqiuQuotaPage(html: String) throws -> [XueqiuQuotaRecord] {
        guard let marker = html.range(of: "window.__INITIAL_STORE__ = "),
              let scriptEnd = html.range(of: "</script>", range: marker.upperBound..<html.endIndex) else {
            throw QDIIQuotaError.invalidResponse
        }
        var jsonText = String(html[marker.upperBound..<scriptEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.last == ";" { jsonText.removeLast() }
        jsonText = jsonText.replacingOccurrences(of: ":undefined", with: ":null")
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            throw QDIIQuotaError.invalidResponse
        }

        var recordsByCode: [String: XueqiuQuotaRecord] = [:]
        collectXueqiuRecords(from: object, into: &recordsByCode)
        return recordsByCode.values.sorted { $0.fundCode < $1.fundCode }
    }

    static func parseExchangeQuote(
        data: Data,
        fundCode: String,
        fallbackName: String = "",
        observedAt: Date
    ) throws -> QDIIExchangeObservation {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let rawPrice = numericValue(payload["f43"]),
              rawPrice > 0 || (numericValue(payload["f60"]) ?? 0) > 0 else {
            throw QDIIQuotaError.invalidResponse
        }
        let name = (payload["f58"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        let code = (payload["f57"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fundCode
        let hasLivePrice = rawPrice > 0
        let fallbackPrice = numericValue(payload["f60"]) ?? rawPrice
        return QDIIExchangeObservation(
            fundCode: code,
            fundName: resolvedName.isEmpty ? "基金 \(fundCode)" : resolvedName,
            lastPrice: (hasLivePrice ? rawPrice : fallbackPrice) / 1_000,
            changeAmount: hasLivePrice ? numericValue(payload["f169"]).map { $0 / 1_000 } : nil,
            changePercent: hasLivePrice ? numericValue(payload["f170"]).map { $0 / 100 } : nil,
            volume: hasLivePrice ? numericValue(payload["f47"]) : nil,
            turnover: hasLivePrice ? numericValue(payload["f48"]) : nil,
            turnoverRate: hasLivePrice ? numericValue(payload["f168"]).map { $0 / 100 } : nil,
            sourceURL: exchangeQuotePageURL(for: fundCode),
            sourceTitle: "东方财富场内行情",
            observedAt: observedAt
        )
    }

    static func parseExchangePremiumQuote(
        data: Data,
        fundCode: String,
        lastPrice: Double
    ) -> QDIIExchangePremiumQuote? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let records = payload["diff"] as? [[String: Any]],
              let record = records.first(where: { ($0["f12"] as? String) == fundCode }) else {
            return nil
        }
        let netAssetValue = numericValue(record["f441"]).flatMap { $0 > 0 ? $0 : nil }
        if let discountRate = numericValue(record["f402"]) {
            return QDIIExchangePremiumQuote(
                netAssetValue: netAssetValue,
                premiumRate: -discountRate,
                isEstimated: false
            )
        }
        guard let netAssetValue, netAssetValue > 0, lastPrice > 0 else { return nil }
        return QDIIExchangePremiumQuote(
            netAssetValue: netAssetValue,
            premiumRate: (lastPrice / netAssetValue - 1) * 100,
            isEstimated: false
        )
    }

    static func parseExchangePremiumRecords(data: Data) -> [String: QDIIExchangePremiumRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let records = payload["diff"] as? [[String: Any]] else {
            return [:]
        }

        var parsed: [String: QDIIExchangePremiumRecord] = [:]
        for record in records {
            guard let fundCode = record["f12"] as? String else { continue }
            let netAssetValue = numericValue(record["f441"]).flatMap { $0 > 0 ? $0 : nil }
            let premiumRate = numericValue(record["f402"]).map { -$0 }
                ?? numericValue(record["f2"]).flatMap { marketPrice in
                    guard let netAssetValue, netAssetValue > 0, marketPrice > 0 else { return nil }
                    return (marketPrice / netAssetValue - 1) * 100
                }
            parsed[fundCode] = QDIIExchangePremiumRecord(netAssetValue: netAssetValue, premiumRate: premiumRate)
        }
        return parsed
    }

    static func parseExchangeDailyFundPage(
        html: String,
        fundCode: String,
        fallbackMarketPrice: Double
    ) -> QDIIExchangePremiumQuote? {
        let pattern = #"<tr[^>]*id=["']tr\#(fundCode)["'][^>]*>(.*?)</tr>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              let rowRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let row = String(html[rowRange])
        guard let cellRegex = try? NSRegularExpression(pattern: #"<td[^>]*>(.*?)</td>"#, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let cellRange = NSRange(row.startIndex..<row.endIndex, in: row)
        let cells = cellRegex.matches(in: row, range: cellRange).compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: row) else { return nil }
            return String(row[valueRange])
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard cells.count > 13 else { return nil }
        let currentNetValue = parseNumericText(cells[6])
        let previousNetValue = parseNumericText(cells[8])
        let netAssetValue = [currentNetValue, previousNetValue].compactMap { $0 }.first(where: { $0 > 0 })
        let marketPrice = parseNumericText(cells[12]) ?? fallbackMarketPrice
        guard let netAssetValue, netAssetValue > 0, marketPrice > 0 else { return nil }
        if let discountRate = parseNumericText(cells[13]) {
            return QDIIExchangePremiumQuote(
                netAssetValue: netAssetValue,
                premiumRate: -discountRate,
                isEstimated: true
            )
        }
        return QDIIExchangePremiumQuote(
            netAssetValue: netAssetValue,
            premiumRate: (marketPrice / netAssetValue - 1) * 100,
            isEstimated: true
        )
    }

    private static func parseNumericText(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != "---", normalized != "-" else { return nil }
        return Double(normalized)
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func exchangeSecID(for code: String) -> String {
        code.hasPrefix("5") ? "1.\(code)" : "0.\(code)"
    }

    private static func exchangeQuotePageURL(for code: String) -> String {
        let market = code.hasPrefix("5") ? "sh" : "sz"
        return "https://quote.eastmoney.com/\(market)\(code).html"
    }

    static func parseXueqiuRecommendation(_ recommendation: String) -> (
        status: QDIIQuotaStatus,
        dailyLimit: Double?,
        isUnlimited: Bool
    ) {
        if recommendation.contains("暂停") {
            return (.suspended, nil, false)
        }
        if recommendation.contains("不限") {
            return (.open, nil, true)
        }
        let pattern = #"[0-9][0-9,.]*\s*(万|亿)?元"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: recommendation,
                range: NSRange(recommendation.startIndex..<recommendation.endIndex, in: recommendation)
              ),
              let valueRange = Range(match.range, in: recommendation) else {
            return (.unknown, nil, false)
        }
        let value = String(recommendation[valueRange])
        let valueWithoutUnit = value.dropLast()
        let unit = valueWithoutUnit.last == "万" ? 10_000.0 : (valueWithoutUnit.last == "亿" ? 100_000_000.0 : 1.0)
        let number = String(valueWithoutUnit
            .dropLast(valueWithoutUnit.last == "万" || valueWithoutUnit.last == "亿" ? 1 : 0))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
        return (.limited, Double(number).map { $0 * unit }, false)
    }

    private static func collectXueqiuRecords(from object: Any, into records: inout [String: XueqiuQuotaRecord]) {
        if let dictionary = object as? [String: Any] {
            if let fundCode = dictionary["fund_code"] as? String,
               let fundName = dictionary["fund_name"] as? String,
               let recommendation = dictionary["recommend"] as? String {
                records[fundCode] = XueqiuQuotaRecord(
                    fundCode: fundCode,
                    fundName: fundName,
                    recommendation: recommendation
                )
            }
            for value in dictionary.values {
                collectXueqiuRecords(from: value, into: &records)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectXueqiuRecords(from: value, into: &records)
            }
        }
    }

    static func parseDirectQuota(text: String, fundCode: String) -> (
        status: QDIIQuotaStatus,
        dailyLimit: Double?,
        isUnlimited: Bool
    ) {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let status: QDIIQuotaStatus
        if normalized.contains("恢复大额申购") || normalized.contains("恢复申购") || normalized.contains("取消大额") {
            status = .open
        } else if normalized.contains("暂停大额申购") || normalized.contains("限制申购") || normalized.contains("暂停申购") {
            status = .limited
        } else {
            status = .unknown
        }

        let codeSection = section(in: normalized, startingWith: "交易代码", endingWith: "该分级基金")
        let codes = matches(#"\b\d{6}\b"#, in: codeSection)
        guard let codeIndex = codes.firstIndex(of: fundCode) else {
            return (status, nil, status == .open)
        }
        let limitSection = section(in: normalized, startingWith: "限制申购金额", endingWith: "限制定期定额投资金额")
        let values = matches(#"(?:\d[\d,.]*(?:\s*[万亿])?|[-—])"#, in: limitSection)
        guard codeIndex < values.count else {
            return (status, nil, status == .open)
        }
        let value = values[codeIndex]
        if value == "-" || value == "—" {
            return (status, nil, status == .open)
        }
        let unit = value.last == "万" ? 10_000.0 : (value.last == "亿" ? 100_000_000.0 : 1.0)
        let number = String(value
            .drop(while: { $0 == "-" })
            .dropLast(value.last == "万" || value.last == "亿" ? 1 : 0))
            .replacingOccurrences(of: ",", with: "")
        return (status, Double(number).map { $0 * unit }, false)
    }

    private struct FundAnnouncement: Decodable {
        let title: String
        let id: String

        enum CodingKeys: String, CodingKey {
            case title = "TITLE"
            case id = "ID"
        }
    }

    private struct FundAnnouncementResponse: Decodable {
        let data: [FundAnnouncement]

        enum CodingKeys: String, CodingKey {
            case data = "Data"
        }
    }

    private func fetchAnnouncements(fundCode: String) async throws -> [FundAnnouncement] {
        var components = URLComponents(string: "https://api.fund.eastmoney.com/f10/JJGG")!
        components.queryItems = [
            URLQueryItem(name: "callback", value: "qdiiQuotaCallback"),
            URLQueryItem(name: "fundcode", value: fundCode),
            URLQueryItem(name: "pageIndex", value: "1"),
            URLQueryItem(name: "pageSize", value: "50"),
            URLQueryItem(name: "type", value: "0")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://fund.eastmoney.com/f10/jjgg_\(fundCode).html", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QDIIQuotaError.unavailable("基金 \(fundCode) 公告列表请求失败")
        }
        let jsonp = String(decoding: data, as: UTF8.self)
        guard let start = jsonp.firstIndex(of: "{"), let end = jsonp.lastIndex(of: "}") else {
            throw QDIIQuotaError.invalidResponse
        }
        let payload = Data(jsonp[start...end].utf8)
        return try JSONDecoder().decode(FundAnnouncementResponse.self, from: payload).data
    }

    private static func isDirectQuotaAnnouncement(_ announcement: FundAnnouncement) -> Bool {
        announcement.title.contains("直销") &&
            (announcement.title.contains("大额申购") || announcement.title.contains("申购上限") || announcement.title.contains("暂停申购"))
    }

    private static func section(in text: String, startingWith start: String, endingWith end: String) -> String {
        guard let startRange = text.range(of: start) else { return "" }
        let suffix = text[startRange.upperBound...]
        let endIndex = suffix.range(of: end)?.lowerBound ?? suffix.endIndex
        return String(suffix[..<endIndex])
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return String(text[valueRange])
        }
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
    static let featuredCatalogVersion = 5
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
        QDIIQuotaWatchItem(fundCode: "159501", fundName: "嘉实纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159513", fundName: "大成纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159612", fundName: "国泰标普500ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159632", fundName: "华安纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159659", fundName: "招商纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159660", fundName: "汇添富纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159655", fundName: "华夏标普500ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159696", fundName: "易方达纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "159941", fundName: "广发纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "513110", fundName: "华泰柏瑞纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "513100", fundName: "国泰纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "513300", fundName: "华夏纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "513390", fundName: "博时纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "513500", fundName: "博时标普500ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "513650", fundName: "南方标普500ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "513870", fundName: "富国纳斯达克100ETF(QDII)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "160213", fundName: "国泰纳斯达克100指数"),
        QDIIQuotaWatchItem(fundCode: "161125", fundName: "易方达标普500指数人民币A", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "161130", fundName: "易方达纳斯达克100ETF联接(QDII-LOF)A(人民币)", market: .exchangeTraded),
        QDIIQuotaWatchItem(fundCode: "270042", fundName: "广发纳斯达克100ETF联接人民币(QDII)A"),
        QDIIQuotaWatchItem(fundCode: "539001", fundName: "建信纳斯达克100指数(QDII)A人民币")
    ]

    static let exchangeFeaturedCodes: Set<String> = Set(
        featured.filter { $0.market == .exchangeTraded }.map(\.fundCode)
    )

    @Published private(set) var watchlist: [QDIIQuotaWatchItem] = []
    @Published private(set) var observations: [String: QDIIQuotaObservation] = [:]
    @Published private(set) var exchangeObservations: [String: QDIIExchangeObservation] = [:]
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
        observation(for: fundCode, channel: .tiantian)
    }

    func observation(for fundCode: String, channel: QDIIQuotaChannel) -> QDIIQuotaObservation? {
        observations["\(fundCode):\(channel.rawValue)"]
    }

    func exchangeObservation(for fundCode: String) -> QDIIExchangeObservation? {
        exchangeObservations[fundCode]
    }

    @discardableResult
    func addFund(code: String, name: String = "") -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count == 6, normalized.allSatisfy(\.isNumber),
              !watchlist.contains(where: { $0.fundCode == normalized }) else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let market: QDIIFundMarket = Self.exchangeFeaturedCodes.contains(normalized) ? .exchangeTraded : .overTheCounter
        watchlist.append(QDIIQuotaWatchItem(fundCode: normalized, fundName: trimmedName, market: market))
        save()
        return true
    }

    func removeFund(_ fundCode: String) {
        watchlist.removeAll { $0.fundCode == fundCode }
        observations = observations.filter { $0.value.fundCode != fundCode }
        exchangeObservations.removeValue(forKey: fundCode)
        save()
    }

    func toggle(_ item: QDIIQuotaWatchItem) {
        guard let index = watchlist.firstIndex(where: { $0.id == item.id }) else { return }
        watchlist[index].isEnabled.toggle()
        save()
    }

    func refreshIfStale(now: Date = Date()) async {
        let needsExchangeRefresh = exchangeObservations.isEmpty && watchlist.contains { $0.market == .exchangeTraded }
        guard needsExchangeRefresh || lastRefreshAt == nil || now.timeIntervalSince(lastRefreshAt!) >= Self.cacheValidity else { return }
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
                if item.market == .exchangeTraded {
                    guard let exchangeObservation = try await client.fetchExchange(item) else {
                        throw QDIIQuotaError.unavailable("场内基金 \(item.fundCode) 暂无行情")
                    }
                    exchangeObservations[item.fundCode] = exchangeObservation
                    if let index = watchlist.firstIndex(where: { $0.id == item.id }) {
                        watchlist[index].lastCheckedAt = refreshedAt
                        if watchlist[index].fundName.isEmpty { watchlist[index].fundName = exchangeObservation.fundName }
                    }
                    continue
                }
                let tiantianObservation = try await client.fetch(item)
                var fetchedObservations = [tiantianObservation]
                if let fetchedDirectObservation = try? await client.fetchDirect(item) {
                    var directObservation = fetchedDirectObservation
                    directObservation.fundName = tiantianObservation.fundName
                    directObservation.fundType = tiantianObservation.fundType
                    directObservation.managementFeeRate = tiantianObservation.managementFeeRate
                    directObservation.custodyFeeRate = tiantianObservation.custodyFeeRate
                    directObservation.salesServiceFeeRate = tiantianObservation.salesServiceFeeRate
                    directObservation.feeSourceURL = tiantianObservation.feeSourceURL
                    fetchedObservations.append(directObservation)
                }
                if let fetchedXueqiuObservation = try? await client.fetchXueqiu(item) {
                    var xueqiuObservation = fetchedXueqiuObservation
                    xueqiuObservation.fundName = tiantianObservation.fundName
                    xueqiuObservation.fundType = tiantianObservation.fundType
                    xueqiuObservation.managementFeeRate = tiantianObservation.managementFeeRate
                    xueqiuObservation.custodyFeeRate = tiantianObservation.custodyFeeRate
                    xueqiuObservation.salesServiceFeeRate = tiantianObservation.salesServiceFeeRate
                    xueqiuObservation.feeSourceURL = tiantianObservation.feeSourceURL
                    fetchedObservations.append(xueqiuObservation)
                }
                for observation in fetchedObservations {
                    if let old = observations[observation.storageKey], QDIIQuotaObservation.isImprovement(from: old, to: observation) {
                        changes.insert(
                            QDIIQuotaChange(
                                fundCode: observation.fundCode,
                                fundName: observation.fundName,
                                channel: observation.channel,
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
                    observations[observation.storageKey] = observation
                }
                if let index = watchlist.firstIndex(where: { $0.id == item.id }) {
                    watchlist[index].lastCheckedAt = refreshedAt
                    if watchlist[index].fundName.isEmpty { watchlist[index].fundName = tiantianObservation.fundName }
                }
            } catch {
                failures.append("\(item.fundCode)：\(error.localizedDescription)")
            }
        }
        changes = Array(changes.prefix(200))
        lastRefreshAt = refreshedAt
        statusMessage = failures.isEmpty
            ? (improved.isEmpty ? "额度和行情已更新" : "发现 \(improved.count) 个额度改善")
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
        for index in watchlist.indices where Self.exchangeFeaturedCodes.contains(watchlist[index].fundCode) {
            watchlist[index].market = .exchangeTraded
        }
        for index in watchlist.indices where watchlist[index].fundCode == "160213" {
            watchlist[index].market = .overTheCounter
        }
        let existingCodes = Set(watchlist.map(\.fundCode))
        let additions = Self.featured.filter {
            !Self.legacyFeaturedCodes.contains($0.fundCode) && !existingCodes.contains($0.fundCode)
        }
        watchlist.append(contentsOf: additions)
        installedFeaturedCatalogVersion = Self.featuredCatalogVersion
        lastRefreshAt = nil
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: stateURL)
            let cache = try JSONDecoder.qdiiQuota.decode(QDIIQuotaCache.self, from: data)
            watchlist = cache.watchlist
            observations = Dictionary(uniqueKeysWithValues: cache.observations.map { ($0.storageKey, $0) })
            exchangeObservations = Dictionary(uniqueKeysWithValues: cache.exchangeObservations.map { ($0.fundCode, $0) })
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
                observations: observations.values.sorted { $0.storageKey < $1.storageKey },
                exchangeObservations: exchangeObservations.values.sorted { $0.fundCode < $1.fundCode },
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
            ? "\(observations[0].fundName)（\(observations[0].channel.title)）：现在\(observations[0].limitTitle)"
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

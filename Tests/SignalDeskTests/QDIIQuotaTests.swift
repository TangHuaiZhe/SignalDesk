import Foundation
import Testing
@testable import SignalDesk

struct QDIIQuotaTests {
    @Test @MainActor
    func includesBroadRMBNasdaqAndSP500Catalog() {
        let codes = Set(QDIIQuotaStore.featured.map(\.fundCode))

        #expect(QDIIQuotaStore.featured.count > 50)
        #expect(codes.contains("015299"))
        #expect(codes.contains("017028"))
        #expect(codes.contains("270042"))
        #expect(QDIIQuotaStore.featured.allSatisfy {
            !$0.fundName.contains("美元") &&
            !$0.fundName.contains("现汇") &&
            !$0.fundName.contains("现钞") &&
            !$0.fundName.contains("美钞")
        })
    }

    @Test @MainActor
    func separatesExchangeListedFundsFromOverTheCounterCatalog() {
        let exchangeCodes = Set(QDIIQuotaStore.featured.filter { $0.market == .exchangeTraded }.map(\.fundCode))

        #expect(exchangeCodes.contains("513300"))
        #expect(exchangeCodes.contains("159632"))
        #expect(exchangeCodes.contains("159612"))
        #expect(exchangeCodes.contains("513500"))
        for code in ["159501", "159513", "159659", "159660", "159696", "513110", "513390", "513870"] {
            #expect(exchangeCodes.contains(code))
        }
        #expect(QDIIQuotaStore.featured.first { $0.fundCode == "160213" }?.market == .overTheCounter)
        #expect(QDIIQuotaStore.featured.first { $0.fundCode == "012752" }?.market == .overTheCounter)
    }

    @Test
    func decodesLegacyWatchItemWithoutMarketAsOverTheCounter() throws {
        let data = Data(#"""
        {
          "fundCode": "012752",
          "fundName": "测试基金",
          "isEnabled": true,
          "lastCheckedAt": null
        }
        """#.utf8)

        let item = try JSONDecoder().decode(QDIIQuotaWatchItem.self, from: data)

        #expect(item.market == .overTheCounter)
    }

    @Test
    func parsesExchangeQuoteFieldsAndScalesEastMoneyValues() throws {
        let data = Data(#"""
        {
          "data": {
            "f43": 2708,
            "f47": 1014421,
            "f48": 275372834.0,
            "f57": "513300",
            "f58": "纳斯达克ETF华夏",
            "f168": 192,
            "f169": 3,
            "f170": 11
          }
        }
        """#.utf8)

        let observation = try EastMoneyQDIIQuotaClient.parseExchangeQuote(
            data: data,
            fundCode: "513300",
            fallbackName: "华夏纳斯达克100ETF(QDII)",
            observedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(observation.lastPrice == 2.708)
        #expect(observation.changeAmount == 0.003)
        #expect(observation.changePercent == 0.11)
        #expect(observation.turnover == 275372834)
        #expect(observation.turnoverRate == 1.92)
        #expect(observation.fundName == "纳斯达克ETF华夏")
    }

    @Test
    func parsesLiveIOPVAndConvertsEastMoneyDiscountToPremium() throws {
        let data = Data(#"""
        {
          "data": {
            "diff": [
              {
                "f12": "513300",
                "f2": 2.708,
                "f402": -1.25,
                "f441": 2.674
              }
            ]
          }
        }
        """#.utf8)

        let quote = EastMoneyQDIIQuotaClient.parseExchangePremiumQuote(
            data: data,
            fundCode: "513300",
            lastPrice: 2.708
        )

        #expect(quote?.netAssetValue == 2.674)
        #expect(quote?.premiumRate == 1.25)
        #expect(quote?.isEstimated == false)
    }

    @Test
    func parsesPremiumRecordsForFundsReturnedOnLaterQuotePages() throws {
        let data = Data(#"""
        {
          "data": {
            "diff": [
              {"f12": "159941", "f2": 1.699, "f402": -11.42, "f441": 1.5248}
            ]
          }
        }
        """#.utf8)

        let records = EastMoneyQDIIQuotaClient.parseExchangePremiumRecords(data: data)

        #expect(records["159941"]?.netAssetValue == 1.5248)
        #expect(records["159941"]?.premiumRate == 11.42)
    }

    @Test
    func estimatesPremiumFromLatestPublishedNetValueBeforeIOPVIsAvailable() {
        let html = #"""
        <tr id="tr513300">
          <td></td><td><input id="513300"/></td><td>1567</td><td>513300</td>
          <td>华夏纳斯达克ETF</td><td>指数型-股票</td>
          <td>---</td><td>---</td><td>2.4978</td><td>2.4978</td>
          <td>---</td><td>---</td><td>2.7080</td><td>---</td>
        </tr>
        """#

        let quote = EastMoneyQDIIQuotaClient.parseExchangeDailyFundPage(
            html: html,
            fundCode: "513300",
            fallbackMarketPrice: 2.708
        )

        #expect(quote?.netAssetValue == 2.4978)
        #expect(quote?.isEstimated == true)
        #expect(abs((quote?.premiumRate ?? 0) - 8.416) < 0.01)
    }

    @Test
    func decodesExchangeObservationWrittenBeforePremiumFields() throws {
        let data = Data(#"""
        {
          "fundCode": "513300",
          "fundName": "测试ETF",
          "lastPrice": 2.708,
          "changeAmount": 0.003,
          "changePercent": 0.11,
          "volume": 100,
          "turnover": 1000,
          "turnoverRate": 0.1,
          "sourceURL": "https://example.com",
          "sourceTitle": "test",
          "observedAt": 0
        }
        """#.utf8)

        let observation = try JSONDecoder().decode(QDIIExchangeObservation.self, from: data)

        #expect(observation.premiumRate == nil)
        #expect(observation.premiumRateIsEstimated == false)
    }

    @Test
    func usesPreviousCloseBeforeExchangeOpensWithoutInventingIntradayChange() throws {
        let data = Data(#"""
        {
          "data": {
            "f43": 0,
            "f47": 0,
            "f48": 0,
            "f57": "513300",
            "f58": "纳斯达克ETF华夏",
            "f60": 2708,
            "f168": 0,
            "f169": 0,
            "f170": 0
          }
        }
        """#.utf8)

        let observation = try EastMoneyQDIIQuotaClient.parseExchangeQuote(
            data: data,
            fundCode: "513300",
            observedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(observation.lastPrice == 2.708)
        #expect(observation.changePercent == nil)
        #expect(observation.turnover == nil)
    }

    @Test
    func parsesFundStatusAndDailyLimit() throws {
        let html = #"""
        <span class="funCur-FundName">测试纳斯达克基金</span>
        <span class="itemTit">交易状态：</span><span class="staticCell">限大额  (<span>单日累计购买上限10.00元</span>)</span>
        """#

        let observation = try EastMoneyQDIIQuotaClient.parse(
            html: html,
            fundCode: "000001",
            observedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(observation.fundName == "测试纳斯达克基金")
        #expect(observation.status == .limited)
        #expect(observation.dailyLimit == 10)
        #expect(observation.limitTitle == "10 元/日")
    }

    @Test
    func parsesDirectChannelQuotaFromAnnouncementText() {
        let text = """
        建信纳斯达克100指数型证券投资基金（QDII）在直销渠道暂停大额申购公告
        下属分级基金的交易代码
        012751 539001 012753 012752 023422
        该分级基金是否暂停大额申购 是 是 是 是 是
        下属分级基金的限制申购金额（单位：人民币元）
        - 10,000.00 - 10,000.00 -
        """

        let result = EastMoneyQDIIQuotaClient.parseDirectQuota(text: text, fundCode: "012752")

        #expect(result.status == .limited)
        #expect(result.dailyLimit == 10_000)
        #expect(!result.isUnlimited)
    }

    @Test
    func parsesSnowballFundQuotaFromPublicRankStore() throws {
        let html = #"""
        <script id="initStore">
        window.__INITIAL_STORE__ = {"initStore":{"types":[{"modules":[
          {"content":{"fund_code":"012752","fund_name":"建信纳斯达克100指数(QDII)C人民币","recommend":"日限购50元"}},
          {"content":{"fund_code":"160213","fund_name":"国泰纳斯达克100指数","recommend":"已暂停申购"}},
          {"content":{"fund_code":"000001","fund_name":"其他基金","recommend":"不限购"}}
        ]}]},"preview":undefined};
        </script>
        """#

        let records = try EastMoneyQDIIQuotaClient.parseXueqiuQuotaPage(html: html)
        let quota = records.first { $0.fundCode == "012752" }
        let parsed = EastMoneyQDIIQuotaClient.parseXueqiuRecommendation(quota?.recommendation ?? "")

        #expect(records.count == 3)
        #expect(quota?.fundName.contains("建信纳斯达克") == true)
        #expect(parsed.status == .limited)
        #expect(parsed.dailyLimit == 50)
        #expect(!parsed.isUnlimited)
        #expect(EastMoneyQDIIQuotaClient.parseXueqiuRecommendation("已暂停申购").status == .suspended)
        #expect(EastMoneyQDIIQuotaClient.parseXueqiuRecommendation("不限购").isUnlimited)
    }

    @Test
    func decodesLegacyObservationWithoutChannelAsTiantian() throws {
        let data = Data(#"""
        {
          "fundCode": "012752",
          "fundName": "测试基金",
          "fundType": null,
          "status": "limited",
          "dailyLimit": 10,
          "isUnlimited": false,
          "sourceURL": "https://example.com",
          "sourceTitle": "test",
          "observedAt": 0
        }
        """#.utf8)

        let observation = try JSONDecoder().decode(QDIIQuotaObservation.self, from: data)

        #expect(observation.channel == .tiantian)
        #expect(observation.storageKey == "012752:tiantian")
    }

    @Test
    func parsesAnnualOperatingFeeRatesAndSumsThem() {
        let html = #"""
        <h4><label class="left">运作费用</label></h4>
        <table><tr>
          <td class="th">管理费率</td><td>0.60%（每年）</td>
          <td class="th">托管费率</td><td>0.15%（每年）</td>
          <td class="th">销售服务费率</td><td>0.30%（每年）</td>
        </tr></table>
        """#

        let rates = EastMoneyQDIIQuotaClient.parseFeeRates(html: html)
        let observation = QDIIQuotaObservation(
            fundCode: "018065",
            fundName: "测试基金",
            fundType: nil,
            status: .limited,
            dailyLimit: 10,
            isUnlimited: false,
            sourceURL: "https://example.com",
            sourceTitle: "test",
            observedAt: Date(),
            managementFeeRate: rates.management,
            custodyFeeRate: rates.custody,
            salesServiceFeeRate: rates.salesService
        )

        #expect(rates.management == 0.60)
        #expect(rates.custody == 0.15)
        #expect(rates.salesService == 0.30)
        #expect(observation.annualOperatingFeeRate == 1.05)
        #expect(observation.comprehensiveFeeTitle == "1.05%/年")
    }

    @Test
    func marksOnlyFeesBelowPointEightPercentAsLowFeeRate() {
        let makeObservation: (Double?) -> QDIIQuotaObservation = { total in
            QDIIQuotaObservation(
                fundCode: "000001",
                fundName: "测试基金",
                fundType: nil,
                status: .open,
                dailyLimit: nil,
                isUnlimited: false,
                sourceURL: "https://example.com",
                sourceTitle: "test",
                observedAt: Date(),
                managementFeeRate: total,
                custodyFeeRate: total == nil ? nil : 0
            )
        }

        #expect(makeObservation(0.79).isLowFeeRate)
        #expect(!makeObservation(0.80).isLowFeeRate)
        #expect(!makeObservation(nil).isLowFeeRate)
    }

    @Test
    func sortsFundsByCurrentlyPurchasableQuotaDescending() {
        let makeObservation: (QDIIQuotaStatus, Double?, Bool) -> QDIIQuotaObservation = {
            status, limit, unlimited in
            QDIIQuotaObservation(
                fundCode: "000001",
                fundName: "测试基金",
                fundType: nil,
                status: status,
                dailyLimit: limit,
                isUnlimited: unlimited,
                sourceURL: "https://example.com",
                sourceTitle: "test",
                observedAt: Date()
            )
        }
        let unlimited = makeObservation(.open, nil, true)
        let oneHundred = makeObservation(.limited, 100, false)
        let ten = makeObservation(.limited, 10, false)
        let suspended = makeObservation(.suspended, 1_000, false)

        #expect(QDIIQuotaObservation.comesBeforeByPurchaseQuota(unlimited, oneHundred))
        #expect(QDIIQuotaObservation.comesBeforeByPurchaseQuota(oneHundred, ten))
        #expect(QDIIQuotaObservation.comesBeforeByPurchaseQuota(ten, suspended))
        #expect(!QDIIQuotaObservation.comesBeforeByPurchaseQuota(suspended, ten))
    }

    @Test
    func detectsImprovedQuotaOnly() {
        let old = QDIIQuotaObservation(
            fundCode: "000001", fundName: "基金", fundType: nil, status: .limited,
            dailyLimit: 10, isUnlimited: false, sourceURL: "https://example.com", sourceTitle: "test", observedAt: Date()
        )
        let increased = QDIIQuotaObservation(
            fundCode: "000001", fundName: "基金", fundType: nil, status: .limited,
            dailyLimit: 100, isUnlimited: false, sourceURL: "https://example.com", sourceTitle: "test", observedAt: Date()
        )
        let reduced = QDIIQuotaObservation(
            fundCode: "000001", fundName: "基金", fundType: nil, status: .limited,
            dailyLimit: 1, isUnlimited: false, sourceURL: "https://example.com", sourceTitle: "test", observedAt: Date()
        )

        #expect(QDIIQuotaObservation.isImprovement(from: old, to: increased))
        #expect(!QDIIQuotaObservation.isImprovement(from: old, to: reduced))
    }

    @Test @MainActor
    func refreshPersistsAndRecordsImprovement() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let stateURL = directory.appending(path: "qdii.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstClient = StubQDIIClient(limit: 10)
        let store = QDIIQuotaStore(stateURL: stateURL, client: firstClient, notificationsEnabled: false)
        store.watchlist.forEach { store.removeFund($0.fundCode) }
        #expect(store.addFund(code: "123456", name: "测试基金"))
        await store.refresh()

        let secondClient = StubQDIIClient(limit: 100)
        let restored = QDIIQuotaStore(stateURL: stateURL, client: secondClient, notificationsEnabled: false)
        await restored.refresh()

        #expect(restored.observation(for: "123456")?.dailyLimit == 100)
        #expect(restored.changes.count == 1)
        #expect(restored.changes.first?.newLimitTitle == "100 元/日")
    }

    @Test @MainActor
    func refreshesExchangeFundIntoMarketObservation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let stateURL = directory.appending(path: "qdii.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = QDIIQuotaStore(stateURL: stateURL, client: StubExchangeQDIIClient(), notificationsEnabled: false)
        store.watchlist.forEach { store.removeFund($0.fundCode) }
        #expect(store.addFund(code: "513300", name: "华夏纳斯达克100ETF(QDII)"))

        await store.refresh()

        #expect(store.watchlist.first?.market == .exchangeTraded)
        #expect(store.exchangeObservation(for: "513300")?.lastPrice == 2.708)
        #expect(store.observation(for: "513300") == nil)
    }
}

private struct StubQDIIClient: QDIIQuotaFetching {
    let limit: Double

    func fetch(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation {
        QDIIQuotaObservation(
            fundCode: item.fundCode,
            fundName: item.fundName,
            fundType: "指数型-海外股票",
            status: .limited,
            dailyLimit: limit,
            isUnlimited: false,
            sourceURL: "https://example.com/\(item.fundCode)",
            sourceTitle: "test",
            observedAt: Date()
        )
    }
}

private struct StubExchangeQDIIClient: QDIIQuotaFetching {
    func fetch(_ item: QDIIQuotaWatchItem) async throws -> QDIIQuotaObservation {
        QDIIQuotaObservation(
            fundCode: item.fundCode,
            fundName: item.fundName,
            fundType: nil,
            status: .unknown,
            dailyLimit: nil,
            isUnlimited: false,
            sourceURL: "https://example.com/\(item.fundCode)",
            sourceTitle: "test",
            observedAt: Date()
        )
    }

    func fetchExchange(_ item: QDIIQuotaWatchItem) async throws -> QDIIExchangeObservation? {
        QDIIExchangeObservation(
            fundCode: item.fundCode,
            fundName: item.fundName,
            lastPrice: 2.708,
            changeAmount: 0.003,
            changePercent: 0.11,
            volume: 1_014_421,
            turnover: 275_372_834,
            turnoverRate: 1.92,
            sourceURL: "https://example.com/\(item.fundCode)",
            sourceTitle: "test",
            observedAt: Date()
        )
    }
}

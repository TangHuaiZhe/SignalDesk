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

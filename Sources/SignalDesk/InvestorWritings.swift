import Combine
import Foundation

enum InvestorWritingKind: String, Codable {
    case shareholderLetter
    case presentation
    case investorCall

    var title: String {
        switch self {
        case .shareholderLetter: "基金信"
        case .presentation: "投资者演示"
        case .investorCall: "投资者交流"
        }
    }

    var icon: String {
        switch self {
        case .shareholderLetter: "doc.text"
        case .presentation: "rectangle.on.rectangle"
        case .investorCall: "waveform"
        }
    }
}

enum InvestorWritingAttribution: String, Codable {
    case namedAuthor
    case officialTeam

    var title: String {
        switch self {
        case .namedAuthor: "本人署名"
        case .officialTeam: "基金官方"
        }
    }
}

struct InvestorWriting: Identifiable, Codable, Equatable {
    var id: String
    var investorID: String
    var title: String
    var author: String
    var publisher: String
    var publishedAt: Date
    var period: String?
    var kind: InvestorWritingKind
    var attribution: InvestorWritingAttribution
    var sourceURL: String
    var sourceNote: String
    var displaysYearOnly: Bool? = nil
    var aiSummary: AISummary?
    var aiTranslation: AITranslation? = nil
}

enum InvestorWritingCatalog {
    static func curated(for investorID: String) -> [InvestorWriting] {
        if investorID == "warren-buffett" {
            return berkshireShareholderLetters
        }
        return all.filter { $0.investorID == investorID }
    }

    static func archiveURL(for investorID: String) -> URL? {
        let raw: String?
        switch investorID {
        case "warren-buffett":
            raw = "https://www.berkshirehathaway.com/letters/letters.html"
        case "bill-ackman":
            raw = "https://pershingsquareholdings.com/materials/"
        case "terry-smith":
            raw = "https://www.fundsmith.co.uk/documents"
        case "chuck-akre":
            raw = "https://www.akrefund.com/"
        default:
            raw = nil
        }
        return raw.flatMap(URL.init(string:))
    }

    private static let all: [InvestorWriting] = [
        writing(
            investorID: "bill-ackman",
            title: "Letter to Shareholders in the 2025 Annual Report",
            author: "William A. Ackman",
            publisher: "Pershing Square Holdings",
            date: "2026-02-18",
            period: "2025",
            url: "https://assets.pershingsquareholdings.com/wp-content/uploads/2026/02/18175039/Pershing-Square-Holdings-Ltd.-2025-Annual-Report.pdf",
            note: "Pershing Square Holdings 官方年报内的股东信。"
        ),
        writing(
            investorID: "terry-smith",
            title: "2026 Semi-Annual Letter to Shareholders",
            author: "Terry Smith",
            publisher: "Fundsmith",
            date: "2026-07-01",
            period: "2026 H1",
            url: "https://www.fundsmith.co.uk/media/lfhpxi1x/2026-fef-semi-annual-letter-to-shareholders-web.pdf",
            note: "Fundsmith 官方半年度股东信。"
        ),
        writing(
            investorID: "terry-smith",
            title: "2025 Annual Letter to Shareholders",
            author: "Terry Smith",
            publisher: "Fundsmith",
            date: "2026-01-01",
            period: "2025",
            url: "https://www.fundsmith.co.uk/media/4hcfd1pg/2025-fef-annual-letter-web.pdf",
            note: "Fundsmith 官方年度股东信。"
        ),
        writing(
            investorID: "chuck-akre",
            title: "A Letter from the Investment Team",
            author: "Akre investment team",
            publisher: "Akre Focus ETF",
            date: "2026-02-06",
            period: "2026",
            url: "https://www.akrefund.com/documents/a-letter-to-the-investment-team-february-6-2026/",
            note: "Akre 官方材料；由投资团队发布，不标作 Chuck Akre 本人署名。",
            attribution: .officialTeam
        ),
        writing(
            investorID: "chuck-akre",
            title: "Letter to Shareholders",
            author: "Akre investment team",
            publisher: "Akre Focus ETF",
            date: "2025-09-01",
            period: "2025",
            url: "https://www.akrefund.com/wp-content/uploads/2025/10/September-2025-CSU-Letter-Final.pdf",
            note: "Akre 官方股东信；由投资团队发布。",
            attribution: .officialTeam
        )
    ]

    private static let berkshireShareholderLetters: [InvestorWriting] = (1977...2024).map { year in
        let file = year <= 2003 ? "\(year).html" : "\(year)ltr.pdf"
        let url = "https://www.berkshirehathaway.com/letters/\(file)"
        return InvestorWriting(
            id: url,
            investorID: "warren-buffett",
            title: "\(year) Berkshire Hathaway Shareholder Letter",
            author: "Warren Buffett",
            publisher: "Berkshire Hathaway",
            publishedAt: dateValue("\(year)-12-31"),
            period: "\(year)",
            kind: .shareholderLetter,
            attribution: .namedAuthor,
            sourceURL: url,
            sourceNote: "Berkshire Hathaway 官方 \(year) 年股东信。",
            displaysYearOnly: true
        )
    }

    private static func writing(
        investorID: String,
        title: String,
        author: String,
        publisher: String,
        date: String,
        period: String,
        url: String,
        note: String,
        attribution: InvestorWritingAttribution = .namedAuthor
    ) -> InvestorWriting {
        InvestorWriting(
            id: url,
            investorID: investorID,
            title: title,
            author: author,
            publisher: publisher,
            publishedAt: dateValue(date),
            period: period,
            kind: .shareholderLetter,
            attribution: attribution,
            sourceURL: url,
            sourceNote: note
        )
    }

    private static func dateValue(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: "\(value)T12:00:00Z") ?? .distantPast
    }
}

struct InvestorWritingClient {
    func fetch(for investor: InvestorPreset) async throws -> [InvestorWriting] {
        var result = InvestorWritingCatalog.curated(for: investor.id)
        switch investor.id {
        case "bill-ackman":
            result += try await fetchPershingMaterials()
        case "chuck-akre":
            result += try await fetchAkreFeed()
        default:
            break
        }
        return Self.deduplicated(result)
    }

    static func parsePershingMaterials(html: String) -> [InvestorWriting] {
        matches(in: html, pattern: #"(?is)<li\b[^>]*materials--list--item[^>]*>(.*?)</li>"#)
            .compactMap { block in
                guard let rawDate = firstMatch(
                    in: block,
                    pattern: #"(?is)materials--list--item--date[^>]*>(.*?)</span>"#
                ).map(plainText),
                let title = firstMatch(
                    in: block,
                    pattern: #"(?is)materials--list--item--description[^>]*>(.*?)</span>"#
                ).map(plainText),
                title.localizedCaseInsensitiveContains("Letter to Shareholders")
                    || title.localizedCaseInsensitiveContains("Annual Investor Update"),
                let href = firstMatch(in: block, pattern: #"(?is)<a\b[^>]*href=["']([^"']+)["']"#),
                let publishedAt = pershingDateFormatter.date(from: rawDate) else {
                    return nil
                }

                let kind: InvestorWritingKind = title.localizedCaseInsensitiveContains("Update")
                    ? .presentation
                    : .shareholderLetter
                return InvestorWriting(
                    id: decodeEntities(href),
                    investorID: "bill-ackman",
                    title: title,
                    author: "William A. Ackman / Pershing Square",
                    publisher: "Pershing Square Holdings",
                    publishedAt: publishedAt,
                    period: year(in: title),
                    kind: kind,
                    attribution: .officialTeam,
                    sourceURL: decodeEntities(href),
                    sourceNote: "Pershing Square Holdings 官方材料；署名以原文为准。"
                )
            }
    }

    private func fetchPershingMaterials() async throws -> [InvestorWriting] {
        let html = try await fetchText("https://pershingsquareholdings.com/materials/")
        return Self.parsePershingMaterials(html: html)
    }

    private func fetchAkreFeed() async throws -> [InvestorWriting] {
        let data = try await fetchData("https://www.akrefund.com/feed/")
        return try FeedParser.parse(data: data)
            .filter {
                let title = $0.title.lowercased()
                return title.contains("letter") || title.contains("investor call")
            }
            .prefix(20)
            .compactMap { item in
                guard let link = item.link else { return nil }
                return InvestorWriting(
                    id: link,
                    investorID: "chuck-akre",
                    title: item.title,
                    author: "Akre investment team",
                    publisher: "Akre Focus ETF",
                    publishedAt: item.publishedAt,
                    period: Self.year(in: item.title),
                    kind: item.title.localizedCaseInsensitiveContains("call")
                        ? .investorCall
                        : .shareholderLetter,
                    attribution: .officialTeam,
                    sourceURL: link,
                    sourceNote: "Akre 官方来源；不自动归因给 Chuck Akre 本人。"
                )
            }
    }

    private func fetchText(_ rawURL: String) async throws -> String {
        let data = try await fetchData(rawURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw FeedError.invalidResponse
        }
        return text
    }

    private func fetchData(_ rawURL: String) async throws -> Data {
        guard let url = URL(string: rawURL) else { throw FeedError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(
            "TrackAI/0.7 contact=local-user@signalsdesk.app",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        return data
    }

    private static func deduplicated(_ writings: [InvestorWriting]) -> [InvestorWriting] {
        var byID: [String: InvestorWriting] = [:]
        for writing in writings {
            if let prior = byID[writing.id],
               prior.attribution == .namedAuthor,
               writing.attribution == .officialTeam {
                continue
            }
            if let priorSummary = byID[writing.id]?.aiSummary, writing.aiSummary == nil {
                var merged = writing
                merged.aiSummary = priorSummary
                byID[writing.id] = merged
            } else {
                byID[writing.id] = writing
            }
        }
        return byID.values.sorted { $0.publishedAt > $1.publishedAt }
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        matches(in: text, pattern: pattern).first
    }

    private static func plainText(_ value: String) -> String {
        decodeEntities(
            value.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: .regularExpression
            )
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8217;", with: "’")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func year(in text: String) -> String? {
        firstMatch(in: text, pattern: #"\b(20\d{2})\b"#)
    }

    private static let pershingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
}

@MainActor
final class InvestorWritingStore: ObservableObject {
    @Published private(set) var writingsByInvestor: [String: [InvestorWriting]] = [:]
    @Published private(set) var refreshingInvestorID: String?
    @Published private(set) var statusInvestorID: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastRefreshedAt: Date?

    private let stateURL: URL
    private let client = InvestorWritingClient()
    private var deletedWritingIDs = Set<String>()

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? Self.defaultStateURL
        load()
        installCuratedWritings()
    }

    func writings(for investorID: String) -> [InvestorWriting] {
        writingsByInvestor[investorID, default: []]
    }

    func writing(id: String, investorID: String) -> InvestorWriting? {
        writings(for: investorID).first { $0.id == id }
    }

    func deleteWriting(id: String, investorID: String) {
        guard writingsByInvestor[investorID]?.contains(where: { $0.id == id }) == true else { return }
        writingsByInvestor[investorID]?.removeAll { $0.id == id }
        deletedWritingIDs.insert(id)
        save()
    }

    func refresh(_ investor: InvestorPreset) async {
        guard refreshingInvestorID == nil else { return }
        refreshingInvestorID = investor.id
        statusInvestorID = investor.id
        statusMessage = "正在检查 \(investor.firm) 的官方材料…"
        defer { refreshingInvestorID = nil }

        do {
            let incoming = try await client.fetch(for: investor)
            writingsByInvestor[investor.id] = merge(
                incoming,
                with: writingsByInvestor[investor.id, default: []]
            )
            lastRefreshedAt = Date()
            statusMessage = incoming.isEmpty
                ? "暂无稳定公开基金信"
                : "已更新 \(incoming.count) 份官方材料"
            save()
        } catch {
            statusMessage = "观点刷新失败：\(error.localizedDescription)"
        }
    }

    func saveSummary(_ summary: AISummary, writingID: String, investorID: String) {
        guard let index = writingsByInvestor[investorID]?.firstIndex(where: { $0.id == writingID }) else {
            return
        }
        writingsByInvestor[investorID]?[index].aiSummary = summary
        save()
    }

    func clearSummary(writingID: String, investorID: String) {
        guard let index = writingsByInvestor[investorID]?.firstIndex(where: { $0.id == writingID }) else {
            return
        }
        writingsByInvestor[investorID]?[index].aiSummary = nil
        save()
    }

    func saveTranslation(_ translation: AITranslation, writingID: String, investorID: String) {
        guard let index = writingsByInvestor[investorID]?.firstIndex(where: { $0.id == writingID }) else {
            return
        }
        writingsByInvestor[investorID]?[index].aiTranslation = translation
        save()
    }

    func clearTranslation(writingID: String, investorID: String) {
        guard let index = writingsByInvestor[investorID]?.firstIndex(where: { $0.id == writingID }) else {
            return
        }
        writingsByInvestor[investorID]?[index].aiTranslation = nil
        save()
    }

    private func installCuratedWritings() {
        for investor in InvestorPreset.featured {
            let curated = InvestorWritingCatalog.curated(for: investor.id)
                .filter { !deletedWritingIDs.contains($0.id) }
            guard !curated.isEmpty else { continue }
            let existing: [InvestorWriting]
            if investor.id == "warren-buffett" {
                let officialIDs = Set(curated.map(\.id))
                existing = writingsByInvestor[investor.id, default: []]
                    .filter { officialIDs.contains($0.id) }
            } else {
                existing = writingsByInvestor[investor.id, default: []]
            }
            writingsByInvestor[investor.id] = merge(
                curated,
                with: existing
            )
        }
    }

    private func merge(
        _ incoming: [InvestorWriting],
        with existing: [InvestorWriting]
    ) -> [InvestorWriting] {
        var byID = Dictionary(
            existing.filter { !deletedWritingIDs.contains($0.id) }.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for writing in incoming where !deletedWritingIDs.contains(writing.id) {
            var merged = writing
            merged.aiSummary = merged.aiSummary ?? byID[writing.id]?.aiSummary
            merged.aiTranslation = merged.aiTranslation ?? byID[writing.id]?.aiTranslation
            byID[writing.id] = merged
        }
        return byID.values.sorted { $0.publishedAt > $1.publishedAt }
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let cache = try? JSONDecoder.investorWritings.decode(
                InvestorWritingCache.self,
                from: data
              ) else {
            return
        }
        writingsByInvestor = Dictionary(
            grouping: cache.writings,
            by: \.investorID
        )
        deletedWritingIDs = Set(cache.deletedWritingIDs ?? [])
        lastRefreshedAt = cache.lastRefreshedAt
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let cache = InvestorWritingCache(
                writings: writingsByInvestor.values
                    .flatMap { $0 }
                    .sorted { $0.publishedAt > $1.publishedAt },
                lastRefreshedAt: lastRefreshedAt,
                deletedWritingIDs: Array(deletedWritingIDs).sorted()
            )
            let data = try JSONEncoder.investorWritings.encode(cache)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            statusMessage = "观点缓存保存失败：\(error.localizedDescription)"
        }
    }

    private static var defaultStateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "SignalDesk", directoryHint: .isDirectory)
            .appending(path: "investor-writings.json")
    }
}

private struct InvestorWritingCache: Codable {
    var writings: [InvestorWriting]
    var lastRefreshedAt: Date?
    var deletedWritingIDs: [String]? = nil
}

private extension JSONEncoder {
    static var investorWritings: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var investorWritings: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

import Foundation
import Testing
@testable import SignalDesk

struct FeedParserTests {
    @Test func parsesRSS() throws {
        let xml = """
        <rss version="2.0"><channel><item>
        <title>Robotics model launch</title>
        <description><![CDATA[New <b>AI</b> system]]></description>
        <link>https://example.com/one</link>
        <pubDate>Sun, 27 Jul 2026 10:00:00 +0800</pubDate>
        </item></channel></rss>
        """

        let items = try FeedParser.parse(data: Data(xml.utf8))

        #expect(items.count == 1)
        #expect(items[0].title == "Robotics model launch")
        #expect(items[0].summary == "New AI system")
        #expect(items[0].link == "https://example.com/one")
    }

    @Test func parsesAtomLinkAttribute() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom"><entry>
        <title>13F-HR filing</title>
        <summary>Quarterly holdings report</summary>
        <link rel="alternate" href="https://example.com/filing"/>
        <updated>2026-07-27T12:00:00Z</updated>
        </entry></feed>
        """

        let items = try FeedParser.parse(data: Data(xml.utf8))

        #expect(items.count == 1)
        #expect(items[0].link == "https://example.com/filing")
    }

    @Test func parsesPodcastTranscriptURL() throws {
        let xml = """
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><item>
        <title>AI podcast</title>
        <description>Episode description</description>
        <link>https://example.com/episode</link>
        <podcast:transcript url="https://cdn.example.com/episode.vtt" type="text/vtt" language="en" />
        <pubDate>Sun, 27 Jul 2026 10:00:00 +0800</pubDate>
        </item></channel></rss>
        """

        let items = try FeedParser.parse(data: Data(xml.utf8))

        #expect(items.count == 1)
        #expect(items[0].transcriptURL == "https://cdn.example.com/episode.vtt")
    }

    @Test func scoringRewardsTopicsAndHoldings() {
        let regular = ImportanceScorer.score(
            text: "New product update",
            topics: ["robotics"],
            kind: .rss
        )
        let relevant = ImportanceScorer.score(
            text: "AI robotics model launch and investment",
            topics: ["AI", "robotics"],
            kind: .rss
        )
        let holding = ImportanceScorer.score(
            text: "13F quarterly holdings",
            topics: ["13F"],
            kind: .sec13F
        )

        #expect(relevant > regular)
        #expect(holding >= 75)
        #expect(ImportanceScorer.category(text: "filing", kind: .sec13F) == .holding)
    }

    @Test func sortsSignalEventsByImportanceAndUpdatedAt() {
        let olderHighValue = SignalEvent(
            id: "older-high-value",
            sourceID: UUID(),
            sourceName: "Test",
            title: "Older",
            summary: "",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 100),
            category: .viewpoint,
            importance: 90,
            matchedTopics: []
        )
        let newerLowValue = SignalEvent(
            id: "newer-low-value",
            sourceID: UUID(),
            sourceName: "Test",
            title: "Newer",
            summary: "",
            url: nil,
            publishedAt: Date(timeIntervalSince1970: 200),
            category: .activity,
            importance: 50,
            matchedTopics: []
        )

        #expect(SignalSortOption.importance.sorted([newerLowValue, olderHighValue]).map(\.id) == ["older-high-value", "newer-low-value"])
        #expect(SignalSortOption.updatedAt.sorted([olderHighValue, newerLowValue]).map(\.id) == ["newer-low-value", "older-high-value"])
    }

    @Test func shortTopicUsesWordBoundaries() {
        #expect(ImportanceScorer.matchedTopics(in: "AI model", topics: ["AI"]) == ["AI"])
        #expect(ImportanceScorer.matchedTopics(in: "The speaker said hello", topics: ["AI"]).isEmpty)
    }

    @Test func mediaClassifierRejectsOrdinaryNews() {
        #expect(MediaClassifier.isLongForm(title: "Exclusive interview with Satya Nadella"))
        #expect(MediaClassifier.isLongForm(title: "黄仁勋最新访谈：AI 工厂的未来"))
        #expect(MediaClassifier.isLongForm(title: "Dario Amodei on the Dwarkesh Podcast"))
        #expect(!MediaClassifier.isLongForm(title: "Elon Musk drops a five-year prediction"))
        #expect(!MediaClassifier.isLongForm(title: "AMD announces a new AI chip"))
        #expect(MediaClassifier.matchesPerson(title: "Exclusive interview with Satya Nadella", aliases: ["Satya Nadella"]))
        #expect(!MediaClassifier.matchesPerson(title: "Bill Gates keynote at AI Summit", aliases: ["Yann LeCun"]))
    }

    @Test func classifiesCanonicalDomainsWithoutGenericTechnologyBucket() {
        let domains = SignalDomainClassifier.classify(
            text: "A foundation model agent runs on GPUs and controls a humanoid robot after new funding"
        )

        #expect(domains.contains(.modelsAgents))
        #expect(domains.contains(.robotics))
        #expect(domains.contains(.compute))
        #expect(domains.contains(.investmentBusiness))
        #expect(SignalDomainClassifier.classify(text: "A general technology keynote").isEmpty)
        #expect(
            SignalDomainClassifier.classify(text: "Quarterly 13F filing", kind: .sec13F)
                == [.investmentBusiness]
        )
        #expect(
            SignalDomainClassifier.classify(
                text: "A conversation with Fei-Fei Li",
                fallbackDomains: [.robotics]
            ).contains(.robotics)
        )
    }
}

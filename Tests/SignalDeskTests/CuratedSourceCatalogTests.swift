import Foundation
import Testing
@testable import SignalDesk

struct CuratedSourceCatalogTests {
    @Test func containsAllRequestedResearchSources() {
        let sources = CuratedSourcePreset.researchSources.map { $0.trackedSource() }
        let keys = Set(sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL)" })

        #expect(sources.count == 9)
        #expect(keys.count == 9)
        #expect(sources.allSatisfy { $0.sourceKind == .rss })
        #expect(sources.contains { $0.name.contains("Howard Marks") })
        #expect(sources.contains { $0.name.contains("AI + a16z") })
    }

    @Test func usesWorkingRSSAndPodcastEndpoints() {
        let feedURLs = Set(CuratedSourcePreset.researchSources.map(\.feedURL))

        #expect(feedURLs.contains("https://aswathdamodaran.blogspot.com/feeds/posts/default?alt=rss"))
        #expect(feedURLs.contains("https://www.bloomberg.com/opinion/authors/ARbTQlRLRjE/matthew-s-levine.rss"))
        #expect(feedURLs.contains("https://feeds.simplecast.com/JGE3yC0V"))
        #expect(feedURLs.contains("https://feeds.simplecast.com/Hb_IuXOo"))
    }

    @Test func containsDedicatedChinaEconomySources() {
        let sources = CuratedSourcePreset.chinaEconomySources.map { $0.trackedSource() }
        let keys = Set(sources.map { "\($0.sourceKind.rawValue)|\($0.feedURL)" })

        #expect(sources.count == 6)
        #expect(keys.count == sources.count)
        #expect(sources.allSatisfy { $0.channel == .chinaEconomy })
        #expect(sources.contains { $0.name.contains("Goldman Sachs") })
        #expect(sources.contains { $0.name.contains("BBC") })
        #expect(sources.contains { $0.name.contains("IMF") })
        #expect(sources.allSatisfy { $0.feedURL.contains("news.google.com/rss/search") })
    }

    @Test func containsDedicatedMagazineSources() {
        let sources = CuratedSourcePreset.magazineSources.map { $0.trackedSource() }
        let paths = Set(sources.map(\.feedURL))

        #expect(sources.count == 4)
        #expect(paths.count == sources.count)
        #expect(sources.allSatisfy { $0.channel == .magazines })
        #expect(sources.allSatisfy { $0.sourceKind == .rss })
        #expect(paths.contains("https://github.com/hehonghui/awesome-english-ebooks/commits/master/01_economist.atom"))
        #expect(paths.contains("https://github.com/hehonghui/awesome-english-ebooks/commits/master/02_new_yorker.atom"))
        #expect(paths.contains("https://github.com/hehonghui/awesome-english-ebooks/commits/master/04_atlantic.atom"))
        #expect(paths.contains("https://github.com/hehonghui/awesome-english-ebooks/commits/master/05_wired.atom"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_CURATED_TEST"] == "1"))
    func fetchesLiveCuratedFeeds() async {
        var failures: [String] = []
        await withTaskGroup(of: (String, String?).self) { group in
            for preset in CuratedSourcePreset.researchSources {
                group.addTask {
                    do {
                        let events = try await FeedClient().fetch(preset.trackedSource())
                        return (preset.name, events.isEmpty ? "返回 0 条" : nil)
                    } catch {
                        return (preset.name, error.localizedDescription)
                    }
                }
            }
            for await (name, failure) in group where failure != nil {
                failures.append("\(name)：\(failure!)")
            }
        }
        #expect(failures.isEmpty, "真实来源失败：\(failures.joined(separator: "；"))")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_CHINA_ECONOMY_TEST"] == "1"))
    func fetchesLiveChinaEconomyFeeds() async {
        var failures: [String] = []
        await withTaskGroup(of: (String, String?).self) { group in
            for preset in CuratedSourcePreset.chinaEconomySources {
                group.addTask {
                    do {
                        let events = try await FeedClient().fetch(preset.trackedSource())
                        return (preset.name, events.isEmpty ? "返回 0 条" : nil)
                    } catch {
                        return (preset.name, error.localizedDescription)
                    }
                }
            }
            for await (name, failure) in group where failure != nil {
                failures.append("\(name)：\(failure!)")
            }
        }
        #expect(failures.isEmpty, "真实来源失败：\(failures.joined(separator: "；"))")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRACKAI_LIVE_MAGAZINE_TEST"] == "1"))
    func fetchesLiveMagazineFeeds() async {
        var failures: [String] = []
        await withTaskGroup(of: (String, String?).self) { group in
            for preset in CuratedSourcePreset.magazineSources {
                group.addTask {
                    do {
                        let events = try await FeedClient().fetch(preset.trackedSource())
                        return (preset.name, events.first?.title == nil ? "返回 0 条" : nil)
                    } catch {
                        return (preset.name, error.localizedDescription)
                    }
                }
            }
            for await (name, failure) in group where failure != nil {
                failures.append("\(name)：\(failure!)")
            }
        }
        #expect(failures.isEmpty, "真实杂志来源失败：\(failures.joined(separator: "；"))")
    }
}

import Foundation
import Testing
@testable import SignalDesk

struct XBloggerCatalogTests {
    @Test func exposesDedicatedXFeedSection() {
        #expect(AppSection.allCases.contains(.xFeed))
        #expect(AppSection.xFeed.title == "X 情报")
        #expect(AppSection.xFeed.icon == "at.circle.fill")
    }

    @Test func exposesDedicatedLongFormSection() {
        #expect(AppSection.allCases.contains(.longForm))
        #expect(AppSection.longForm.title == "长篇信息")
        #expect(AppSection.longForm.icon == "doc.text.fill")
    }

    @Test func exposesDedicatedChinaEconomySection() {
        #expect(AppSection.allCases.contains(.chinaEconomy))
        #expect(AppSection.chinaEconomy.title == "海外看中国")
        #expect(AppSection.chinaEconomy.icon == "globe.asia.australia.fill")
    }

    @Test func exposesDedicatedMagazineSection() {
        #expect(AppSection.allCases.contains(.magazines))
        #expect(AppSection.magazines.title == "英语杂志")
        #expect(AppSection.magazines.icon == "books.vertical.fill")
    }

    @Test func catalogHasUniqueAccountsAndBalancedRecommendations() {
        let bloggers = XBloggerPreset.catalog
        let usernames = Set(bloggers.map { $0.username.lowercased() })
        let recommended = bloggers.filter(\.isRecommended)

        #expect(bloggers.count == 24)
        #expect(usernames.count == bloggers.count)
        #expect(recommended.count == 16)
        for category in XBloggerCategory.allCases {
            #expect(bloggers.filter { $0.category == category }.count == 6)
            #expect(recommended.filter { $0.category == category }.count == 4)
        }
    }

    @Test @MainActor
    func batchImportIsIdempotentAndPreservesDisabledState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let stateURL = directory.appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SignalStore(stateURL: stateURL)
        let chosen = Array(XBloggerPreset.catalog.prefix(3))

        let firstAdded = store.importXBloggers(chosen, isEnabled: false)
        let secondAdded = store.importXBloggers(chosen, isEnabled: true)
        let importedUsernames = Set(chosen.map { $0.username.lowercased() })
        let imported = store.sources.filter {
            $0.sourceKind == .x && importedUsernames.contains($0.feedURL.lowercased())
        }

        #expect(firstAdded == 3)
        #expect(secondAdded == 0)
        #expect(imported.count == 3)
        #expect(imported.allSatisfy { !$0.isEnabled })
    }
}

import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct OverviewAccountRowsTests {
    private func makeSettings() -> SettingsStore {
        let settings = testSettingsStore(
            suiteName: "OverviewAccountRowsTests",
            userDefaults: InMemoryUserDefaults())
        settings.providerDetectionCompleted = true
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.multiAccountMenuLayout = .stacked
        return settings
    }

    private func snapshot(percent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: percent,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
    }

    private func controller(store: UsageStore, settings: SettingsStore) -> StatusItemController {
        StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: testStatusBar())
    }

    @Test
    func `stacked token accounts keep separate identities and usage`() {
        let settings = self.makeSettings()
        enableTestProviders([.claude], settings: settings)
        for label in ["Primary", "Secondary", "Third"] {
            settings.addTokenAccount(provider: .claude, label: label, token: "Bearer sk-ant-oat-fixture-\(label)")
        }
        let store = UsageStore(
            fetcher: UsageFetcher(), browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let accounts = settings.tokenAccounts(for: .claude)
        store.accountSnapshots[.claude] = accounts.enumerated().map { index, account in
            TokenAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(percent: Double(10 + index * 20)),
                error: nil,
                sourceLabel: "test",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: account))
        }
        let controller = self.controller(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .claude)

        #expect(rows.count == 3)
        #expect(Set(rows.map(\.identifier)).count == 3)
        #expect(Set(rows.map(\.heightCacheScope)).count == 3)
        #expect(Set(rows.map(\.model.email)) == Set(["Primary", "Secondary", "Third"]))
        #expect(Set(rows.compactMap { $0.model.metrics.first?.percent }).count == 3)
        #expect(rows.allSatisfy { $0.provider == .claude })
        for account in accounts {
            #expect(rows.contains { $0.identifier.hasSuffix(account.id.uuidString) })
        }

        settings.multiAccountMenuLayout = .segmented
        #expect(controller.overviewAccountRows(for: .claude).count <= 1)
    }

    @Test
    func `stacked Codex profiles use their own cached snapshots`() {
        let settings = self.makeSettings()
        enableTestProviders([.codex], settings: settings)
        let accounts = (0..<3).map { index in
            CodexVisibleAccount(
                id: "profile-\(index)",
                email: "profile\(index)@example.com",
                storedAccountID: nil,
                selectionSource: .profileHome(path: "/fixture/profile-\(index)"),
                isActive: index == 0,
                isLive: false,
                canReauthenticate: false,
                canRemove: false)
        }
        settings.codexActiveSource = accounts[0].selectionSource
        settings.cachedCodexAccountMenuProjection = CachedCodexAccountMenuProjection(
            activeSource: accounts[0].selectionSource,
            loadedAt: Date(),
            projection: CodexVisibleAccountProjection(
                visibleAccounts: accounts,
                activeVisibleAccountID: accounts[0].id,
                liveVisibleAccountID: nil,
                hasUnreadableAddedAccountStore: false))
        let store = UsageStore(
            fetcher: UsageFetcher(), browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store.codexAccountSnapshots = accounts.enumerated().map { index, account in
            CodexAccountUsageSnapshot(
                account: account,
                snapshot: self.snapshot(percent: Double(15 + index * 25)),
                error: nil,
                sourceLabel: "test")
        }
        let controller = self.controller(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .codex)

        #expect(rows.count == 3)
        #expect(Set(rows.map(\.identifier)).count == 3)
        #expect(Set(rows.map(\.heightCacheScope)).count == 3)
        #expect(Set(rows.map(\.model.email)) == Set(accounts.map(\.email)))
        #expect(Set(rows.compactMap { $0.model.metrics.first?.percent }).count == 3)
        #expect(rows.allSatisfy { $0.provider == .codex })
    }
}

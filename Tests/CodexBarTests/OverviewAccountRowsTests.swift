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

        store.accountSnapshots[.claude]?[1] = TokenAccountUsageSnapshot(
            account: accounts[1],
            snapshot: nil,
            error: "Sign in again",
            sourceLabel: "test",
            cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: accounts[1]))
        let rowsWithExpiredAccount = controller.overviewAccountRows(for: .claude)
        #expect(rowsWithExpiredAccount.count == 3)
        #expect(rowsWithExpiredAccount.contains { $0.model.email == "Secondary" && $0.model.isOverviewErrorOnly })

        settings.multiAccountMenuLayout = .segmented
        #expect(controller.overviewAccountRows(for: .claude).count <= 1)
    }

    @Test
    func `stacked Codex profiles use their own cached snapshots`() {
        let settings = self.makeSettings()
        enableTestProviders([.codex], settings: settings)
        let managedAccounts = (0..<3).map { index in
            ManagedCodexAccount(
                id: UUID(),
                email: "profile\(index)@example.com",
                managedHomePath: "/fixture/profile-\(index)",
                createdAt: 1,
                updatedAt: 1,
                lastAuthenticatedAt: 1)
        }
        let reconciliation = CodexAccountReconciliationSnapshot(
            storedAccounts: managedAccounts,
            activeStoredAccount: managedAccounts[0],
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: managedAccounts[0].id),
            hasUnreadableAddedAccountStore: false)
        let projection = CodexVisibleAccountProjection.make(from: reconciliation)
        let accounts = projection.visibleAccounts
        settings._test_codexAccountSnapshotLoader = { _ in reconciliation }
        defer { settings._test_codexAccountSnapshotLoader = nil }
        settings.codexActiveSource = reconciliation.activeSource
        settings.cachedCodexAccountMenuProjection = CachedCodexAccountMenuProjection(
            activeSource: reconciliation.activeSource,
            loadedAt: Date(),
            projection: projection)
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

        store.codexAccountSnapshots[1] = CodexAccountUsageSnapshot(
            account: accounts[1],
            snapshot: nil,
            error: "Sign in again",
            sourceLabel: "test")
        let rowsWithExpiredAccount = controller.overviewAccountRows(for: .codex)
        #expect(rowsWithExpiredAccount.count == 3)
        #expect(rowsWithExpiredAccount.contains {
            $0.model.email == accounts[1].email && $0.model.isOverviewErrorOnly
        })
    }
}

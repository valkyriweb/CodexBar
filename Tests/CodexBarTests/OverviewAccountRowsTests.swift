import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct OverviewAccountRowsTests {
    @Test
    func `stacked overview keeps each Claude account weekly usage separate`() throws {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-claude")
        settings.multiAccountMenuLayout = .stacked
        settings.usageBarsShowUsed = true
        settings.mergeIcons = true
        settings.mergedMenuLastSelectedWasOverview = true
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        Self.enableOnly([.claude, .codex], settings)
        settings.addTokenAccount(
            provider: .claude,
            label: "alpha@example.com",
            token: "sessionKey=sk-ant-sid01-alpha")
        settings.addTokenAccount(
            provider: .claude,
            label: "beta@example.com",
            token: "sessionKey=sk-ant-sid01-beta")
        let accounts = settings.tokenAccounts(for: .claude)
        let alphaReset = Date(timeIntervalSince1970: 1_800_000_000)
        let betaReset = Date(timeIntervalSince1970: 1_900_000_000)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.snapshots[.claude] = Self.usageSnapshot(
            provider: .claude,
            email: "selected@example.com",
            sessionUsed: 99,
            weeklyUsed: 99,
            weeklyReset: Date(timeIntervalSince1970: 1_700_000_000))
        store.accountSnapshots[.claude] = [
            Self.tokenSnapshot(
                store: store,
                account: accounts[0],
                usage: .init(
                    provider: .claude,
                    email: "alpha@example.com",
                    sessionUsed: 11,
                    weeklyUsed: 22,
                    weeklyReset: alphaReset)),
            TokenAccountUsageSnapshot(
                account: accounts[1],
                snapshot: nil,
                error: "session expired",
                sourceLabel: "web",
                cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: accounts[1])),
        ]

        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }
        StatusItemController.menuCardRenderingEnabled = false

        let rows = controller.overviewAccountRows(for: .claude)
        #expect(rows.map(\.provider) == [.claude, .claude])
        #expect(rows.map(\.model.email) == ["alpha@example.com", "beta@example.com"])
        #expect(rows.map(\.identifier) == accounts.map {
            StatusItemController.overviewRowIdentifier(provider: .claude, accountID: $0.id.uuidString)
        })

        let alphaWeekly = try #require(rows[0].model.metrics.first { $0.id == "secondary" })
        let alphaSession = try #require(rows[0].model.metrics.first { $0.id == "primary" })
        #expect(alphaWeekly.title == "Weekly")
        #expect(alphaSession.title == "Session")
        #expect(alphaWeekly.percent == 22)
        #expect(alphaSession.percent == 11)
        #expect(alphaWeekly.resetText?.isEmpty == false)
        #expect(rows[1].model.metrics.isEmpty)
        #expect(rows[1].model.subtitleStyle == .error)
        #expect(rows[1].model.subtitleText == "session expired")
        #expect(rows.allSatisfy { $0.model.email != "selected@example.com" })
        #expect(rows.allSatisfy { row in
            row.model.metrics.allSatisfy { $0.percent != 99 }
        })

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let ids = menu.items.compactMap { $0.representedObject as? String }
        #expect(ids.contains(rows[0].identifier))
        #expect(ids.contains(rows[1].identifier))
        #expect(ids.contains("overviewRow-claude") == false)

        let item = NSMenuItem()
        item.representedObject = rows[0].identifier
        item.menu = menu
        controller.selectOverviewProvider(item)
        #expect(settings.mergedMenuLastSelectedWasOverview == false)
        #expect(controller.selectedMenuProvider == .claude)
    }

    @Test
    func `missing stacked account does not inherit another account snapshot`() throws {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-missing")
        settings.multiAccountMenuLayout = .stacked
        settings.usageBarsShowUsed = true
        Self.enableOnly(.claude, settings)
        settings.addTokenAccount(provider: .claude, label: "alpha@example.com", token: "sessionKey=sk-ant-sid01-alpha")
        settings.addTokenAccount(provider: .claude, label: "beta@example.com", token: "sessionKey=sk-ant-sid01-beta")
        let accounts = settings.tokenAccounts(for: .claude)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.accountSnapshots[.claude] = [
            Self.tokenSnapshot(
                store: store,
                account: accounts[0],
                usage: .init(
                    provider: .claude,
                    email: "alpha@example.com",
                    sessionUsed: 10,
                    weeklyUsed: 40,
                    weeklyReset: Date(timeIntervalSince1970: 1_800_000_000))),
        ]
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .claude)
        #expect(rows.map(\.model.email) == ["alpha@example.com", "beta@example.com"])
        #expect(rows[1].model.metrics.isEmpty)
        #expect(rows[1].model.subtitleText == "Unavailable")
        let weekly = try #require(rows[0].model.metrics.first { $0.id == "secondary" })
        #expect(weekly.percent == 40)
    }

    @Test
    func `account overview rows do not open provider-level submenus`() {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-submenu")
        settings.multiAccountMenuLayout = .stacked
        Self.enableOnly(.claude, settings)
        settings.addTokenAccount(provider: .claude, label: "alpha@example.com", token: "sessionKey=sk-ant-sid01-alpha")
        settings.addTokenAccount(provider: .claude, label: "beta@example.com", token: "sessionKey=sk-ant-sid01-beta")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let accountRows = controller.overviewAccountRows(for: .claude)
        #expect(accountRows.count == 2)
        #expect(accountRows.allSatisfy { $0.accountID != nil })
        #expect(accountRows.allSatisfy { $0.storageText == nil })
        #expect(accountRows.allSatisfy { controller.makeOverviewRowSubmenu(row: $0, width: 320) == nil })

        settings.multiAccountMenuLayout = .segmented
        let providerRows = controller.overviewAccountRows(for: .claude)
        #expect(providerRows.map(\.accountID) == [nil])
        #expect(controller.makeOverviewRowSubmenu(row: providerRows[0], width: 320) != nil)
    }

    @Test
    func `stacked accounts fan out even when every snapshot is missing`() {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-nosnapshots")
        settings.multiAccountMenuLayout = .stacked
        settings.usageBarsShowUsed = true
        Self.enableOnly(.claude, settings)
        settings.addTokenAccount(provider: .claude, label: "alpha@example.com", token: "sessionKey=sk-ant-sid01-alpha")
        settings.addTokenAccount(provider: .claude, label: "beta@example.com", token: "sessionKey=sk-ant-sid01-beta")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.snapshots[.claude] = Self.usageSnapshot(
            provider: .claude,
            email: "selected@example.com",
            sessionUsed: 77,
            weeklyUsed: 88,
            weeklyReset: Date(timeIntervalSince1970: 1_700_000_000))
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .claude)
        #expect(rows.map(\.model.email) == ["alpha@example.com", "beta@example.com"])
        #expect(rows.allSatisfy { row in
            row.model.metrics.isEmpty
        })
        #expect(rows.allSatisfy { $0.model.subtitleText == "Unavailable" })
        #expect(rows.allSatisfy { $0.model.email != "selected@example.com" })
    }

    @Test
    func `stacked claude-swap accounts each get an overview row`() {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-claudeswap")
        settings.multiAccountMenuLayout = .stacked
        settings.usageBarsShowUsed = true
        Self.enableOnly(.claude, settings)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.snapshots[.claude] = Self.usageSnapshot(
            provider: .claude,
            email: "signedin@example.com",
            sessionUsed: 95,
            weeklyUsed: 96,
            weeklyReset: Date(timeIntervalSince1970: 1_700_000_000))
        store.claudeSwapAccountSnapshots = Self.claudeSwapAccounts(count: 2)
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .claude)
        #expect(rows.count == 2)
        #expect(rows.map(\.provider) == [.claude, .claude])
        #expect(rows.map(\.identifier) == [
            StatusItemController.overviewRowIdentifier(
                provider: .claude,
                accountID: "\(ClaudeSwapAccountProjection.sourceName):1"),
            StatusItemController.overviewRowIdentifier(
                provider: .claude,
                accountID: "\(ClaudeSwapAccountProjection.sourceName):2"),
        ])
        #expect(rows.allSatisfy { $0.model.email != "signedin@example.com" })
        let weeklyPercents = rows.compactMap { row in
            row.model.metrics.first { $0.id == "secondary" }?.percent
        }
        #expect(weeklyPercents == [41, 42])
        #expect(rows.allSatisfy { controller.makeOverviewRowSubmenu(row: $0, width: 320) == nil })
    }

    @Test
    func `stacked claude-swap overview rows show the snapshot plan not the switch action`() {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-claudeswap-plan")
        settings.multiAccountMenuLayout = .stacked
        settings.usageBarsShowUsed = true
        Self.enableOnly(.claude, settings)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let planned = Self.claudeSwapAccount(ClaudeSwapPlanFixture(
            number: 1,
            email: "planned@example.com",
            isActive: true,
            canActivate: true,
            weeklyUsed: 41,
            loginMethod: "Max"))
        let unplanned = Self.claudeSwapAccount(ClaudeSwapPlanFixture(
            number: 2,
            email: "unplanned@example.com",
            isActive: false,
            canActivate: true,
            weeklyUsed: 42,
            loginMethod: nil))
        store.claudeSwapAccountSnapshots = [planned, unplanned]
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .claude)
        let menuPlans = [planned, unplanned].map { controller.claudeSwapCardModel(for: $0)?.planText }
        #expect(menuPlans == ["Re-authenticate", "Switch Account..."])
        #expect(rows.map(\.model.planText) == ["Max", nil])
        #expect(rows.map { $0.model.metrics.first { $0.id == "secondary" }?.percent } == [41, 42])
        let switchActions = [
            "Switch Account...",
            "Re-authenticate",
            "Switching account…",
            "Refreshing account status…",
            "Active",
        ]
        #expect(rows.allSatisfy { row in
            guard let plan = row.model.planText else { return true }
            return !switchActions.contains(plan)
        })
    }

    @Test
    func `segmented claude-swap layout keeps one provider overview row`() {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-claudeswap-segmented")
        settings.multiAccountMenuLayout = .segmented
        Self.enableOnly(.claude, settings)
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.snapshots[.claude] = Self.usageSnapshot(
            provider: .claude,
            email: "signedin@example.com",
            sessionUsed: 12,
            weeklyUsed: 13,
            weeklyReset: Date(timeIntervalSince1970: 1_700_000_000))
        store.claudeSwapAccountSnapshots = Self.claudeSwapAccounts(count: 2)
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        #expect(controller.overviewAccountRows(for: .claude).map(\.identifier) == ["overviewRow-claude"])
    }

    private struct ClaudeSwapPlanFixture {
        var number: Int
        var email: String
        var isActive: Bool
        var canActivate: Bool
        var weeklyUsed: Double
        var loginMethod: String?
    }

    private static func claudeSwapAccount(_ fixture: ClaudeSwapPlanFixture) -> ProviderAccountUsageSnapshot {
        let reset = Date(timeIntervalSince1970: 1_782_086_400)
        return ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(
                source: ClaudeSwapAccountProjection.sourceName,
                opaqueID: String(fixture.number)),
            provider: .claude,
            displayLabel: fixture.email,
            accountEmail: fixture.email,
            isActive: fixture.isActive,
            canActivate: fixture.canActivate,
            snapshot: UsageSnapshot(
                primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: reset, resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: fixture.weeklyUsed,
                    windowMinutes: 10080,
                    resetsAt: reset,
                    resetDescription: nil),
                updatedAt: reset,
                identity: ProviderIdentitySnapshot(
                    providerID: UsageProvider.claude.instanceID,
                    accountEmail: fixture.email,
                    accountOrganization: nil,
                    loginMethod: fixture.loginMethod)),
            error: nil,
            sourceLabel: ClaudeSwapAccountProjection.sourceLabel)
    }

    private static func claudeSwapAccounts(count: Int) -> [ProviderAccountUsageSnapshot] {
        let now = Date(timeIntervalSince1970: 1_782_000_000)
        return ClaudeSwapAccountProjection.accountSnapshots(
            from: ClaudeSwapAccountList(
                activeAccountNumber: 1,
                accounts: (1...count).map { number in
                    ClaudeSwapAccountRow(
                        number: number,
                        email: "swap\(number)@example.com",
                        isActive: number == 1,
                        usageStatus: .ok,
                        fiveHour: ClaudeSwapUsageWindow(
                            usedPercent: Double(20 + number),
                            resetsAt: now.addingTimeInterval(3600)),
                        sevenDay: ClaudeSwapUsageWindow(
                            usedPercent: Double(40 + number),
                            resetsAt: now.addingTimeInterval(86400)),
                        scoped: [])
                }),
            now: now)
    }

    @Test
    func `segmented layout keeps one provider overview row`() {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-segmented")
        settings.multiAccountMenuLayout = .segmented
        Self.enableOnly(.claude, settings)
        settings.addTokenAccount(provider: .claude, label: "alpha@example.com", token: "sessionKey=sk-ant-sid01-alpha")
        settings.addTokenAccount(provider: .claude, label: "beta@example.com", token: "sessionKey=sk-ant-sid01-beta")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .claude)
        #expect(rows.map(\.identifier) == ["overviewRow-claude"])
    }

    @Test
    func `stacked Codex overview rows use each account snapshot`() {
        let settings = testSettingsStore(suiteName: "OverviewAccountRowsTests-codex")
        settings.multiAccountMenuLayout = .stacked
        settings.usageBarsShowUsed = true
        Self.enableOnly(.codex, settings)
        let firstID = UUID()
        let secondID = UUID()
        let first = ManagedCodexAccount(
            id: firstID,
            email: "first@example.com",
            managedHomePath: "/tmp/codexbar-overview-first",
            createdAt: 1,
            updatedAt: 1,
            lastAuthenticatedAt: 1)
        let snapshot = CodexAccountReconciliationSnapshot(
            storedAccounts: [
                first,
                ManagedCodexAccount(
                    id: secondID,
                    email: "second@example.com",
                    managedHomePath: "/tmp/codexbar-overview-second",
                    createdAt: 1,
                    updatedAt: 1,
                    lastAuthenticatedAt: 1),
            ],
            activeStoredAccount: first,
            liveSystemAccount: nil,
            matchingStoredAccountForLiveSystemAccount: nil,
            activeSource: .managedAccount(id: firstID),
            hasUnreadableAddedAccountStore: false)
        settings.codexActiveSource = .managedAccount(id: firstID)
        let projection = CodexVisibleAccountProjection.make(from: snapshot)
        settings.cachedCodexAccountMenuProjection = CachedCodexAccountMenuProjection(
            activeSource: snapshot.activeSource,
            loadedAt: Date(timeIntervalSinceNow: -3600),
            projection: projection)
        let accounts = projection.visibleAccounts
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store.snapshots[.codex] = Self.usageSnapshot(
            provider: .codex,
            email: "live@example.com",
            sessionUsed: 91,
            weeklyUsed: 92,
            weeklyReset: Date(timeIntervalSince1970: 1_700_000_000))
        store.codexAccountSnapshots = accounts.enumerated().map { index, account in
            CodexAccountUsageSnapshot(
                account: account,
                snapshot: Self.usageSnapshot(
                    provider: .codex,
                    email: account.email,
                    sessionUsed: Double(10 + index),
                    weeklyUsed: Double(30 + index),
                    weeklyReset: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 86400)),
                error: nil,
                sourceLabel: "fixture")
        }
        let controller = Self.makeController(store: store, settings: settings)
        defer { controller.releaseStatusItemsForTesting() }

        let rows = controller.overviewAccountRows(for: .codex)
        #expect(rows.count == accounts.count)
        #expect(rows.count > 1)
        #expect(Set(rows.map(\.model.email)) == Set(accounts.map(\.email)))
        let weeklyPercents = rows.compactMap { row in
            row.model.metrics.first { $0.id == "secondary" }?.percent
        }
        #expect(Set(weeklyPercents) == [30, 31])
        #expect(rows.allSatisfy { $0.model.email != "live@example.com" })
        #expect(rows.allSatisfy { row in row.model.metrics.allSatisfy { $0.percent != 91 && $0.percent != 92 } })
    }

    @Test
    func `account overview identifier still selects its provider`() {
        #expect(StatusItemController.overviewProvider(fromRepresentedObject: "overviewRow-claude") == .claude)
        let accountID = UUID().uuidString
        #expect(
            StatusItemController.overviewProvider(
                fromRepresentedObject: "overviewRow-opencodego-\(accountID)") == .opencodego)
        #expect(
            StatusItemController.overviewProvider(
                fromRepresentedObject: "overviewRow-opencode-\(accountID)") == .opencode)
        #expect(StatusItemController.overviewProvider(fromRepresentedObject: "menuCard") == nil)
    }

    private static func enableOnly(_ provider: UsageProvider, _ settings: SettingsStore) {
        self.enableOnly([provider], settings)
    }

    private static func enableOnly(_ providers: Set<UsageProvider>, _ settings: SettingsStore) {
        for candidate in UsageProvider.allCases {
            guard let metadata = ProviderRegistry.shared.metadata[candidate] else { continue }
            settings.setProviderEnabled(
                provider: candidate,
                metadata: metadata,
                enabled: providers.contains(candidate))
        }
    }

    private static func makeController(store: UsageStore, settings: SettingsStore) -> StatusItemController {
        StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
    }

    private struct FixtureUsage {
        var provider: UsageProvider
        var email: String
        var sessionUsed: Double
        var weeklyUsed: Double
        var weeklyReset: Date
    }

    private static func tokenSnapshot(
        store: UsageStore,
        account: ProviderTokenAccount,
        usage: FixtureUsage) -> TokenAccountUsageSnapshot
    {
        TokenAccountUsageSnapshot(
            account: account,
            snapshot: self.usageSnapshot(usage),
            error: nil,
            sourceLabel: "web",
            cacheKey: store.tokenAccountSnapshotCacheKey(provider: .claude, account: account))
    }

    private static func usageSnapshot(
        provider: UsageProvider,
        email: String,
        sessionUsed: Double,
        weeklyUsed: Double,
        weeklyReset: Date) -> UsageSnapshot
    {
        self.usageSnapshot(FixtureUsage(
            provider: provider,
            email: email,
            sessionUsed: sessionUsed,
            weeklyUsed: weeklyUsed,
            weeklyReset: weeklyReset))
    }

    private static func usageSnapshot(_ usage: FixtureUsage) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: usage.sessionUsed,
                windowMinutes: 300,
                resetsAt: usage.weeklyReset.addingTimeInterval(-86400),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: usage.weeklyUsed,
                windowMinutes: 10080,
                resetsAt: usage.weeklyReset,
                resetDescription: nil),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            identity: ProviderIdentitySnapshot(
                providerID: usage.provider.instanceID,
                accountEmail: usage.email,
                accountOrganization: nil,
                loginMethod: "fixture"))
    }
}

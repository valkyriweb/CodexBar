import AppKit
import CodexBarCore

// MARK: - Overview per-account row fan-out

extension StatusItemController {
    struct OverviewAccountRow {
        let provider: UsageProvider
        let model: UsageMenuCardView.Model
        let identifier: String
        let heightCacheScope: String
        let accountID: String?
        var storageText: String?
    }

    /// Overview rows for one provider. Stacked multi-account layouts get one row per configured
    /// account, using that account's snapshot only. A missing snapshot is unavailable, never the
    /// selected account's live usage. Single-account and segmented layouts keep the provider row,
    /// which alone carries the provider-wide storage footprint.
    func overviewAccountRows(for provider: UsageProvider) -> [OverviewAccountRow] {
        if let accountRows = self.stackedAccountOverviewRows(for: provider), !accountRows.isEmpty {
            return accountRows
        }

        guard let model = self.menuCardModel(for: provider), !model.isOverviewErrorOnly else { return [] }
        return [OverviewAccountRow(
            provider: provider,
            model: model,
            identifier: Self.overviewRowIdentifier(provider: provider),
            heightCacheScope: provider.rawValue,
            accountID: nil,
            storageText: self.store.storageFootprintText(for: provider))]
    }

    static func overviewProvider(fromRepresentedObject represented: String) -> UsageProvider? {
        guard represented.hasPrefix(overviewRowIdentifierPrefix) else { return nil }
        let raw = String(represented.dropFirst(Self.overviewRowIdentifierPrefix.count))
        if let provider = UsageProvider(rawValue: raw) {
            return provider
        }
        // No provider raw value contains a hyphen, so the first prefix match is unambiguous.
        return UsageProvider.allCases.first { raw.hasPrefix($0.rawValue + "-") }
    }

    static func overviewRowIdentifier(provider: UsageProvider, accountID: String? = nil) -> String {
        let base = "\(Self.overviewRowIdentifierPrefix)\(provider.rawValue)"
        guard let accountID, !accountID.isEmpty else { return base }
        return "\(base)-\(accountID)"
    }

    private func stackedAccountOverviewRows(for provider: UsageProvider) -> [OverviewAccountRow]? {
        if provider == .codex,
           let display = self.codexAccountMenuDisplay(for: .codex),
           display.showAll,
           display.accounts.count > 1
        {
            return self.codexOverviewRows(display)
        }

        if let claudeSwapRows = self.claudeSwapOverviewRows(for: provider) {
            return claudeSwapRows
        }

        guard let display = self.tokenAccountMenuDisplay(for: provider),
              display.showAll,
              display.accounts.count > 1
        else {
            return nil
        }
        return self.tokenAccountOverviewRows(display)
    }

    private func codexOverviewRows(_ display: CodexAccountMenuDisplay) -> [OverviewAccountRow] {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: display.snapshots.map { ($0.id, $0) })
        return display.accounts.compactMap { account in
            let accountSnapshot = snapshotsByID[account.id] ?? Self.unavailableCodexSnapshot(account)
            guard let model = self.codexAccountMenuCardModel(for: account, accountSnapshot: accountSnapshot) else {
                return nil
            }
            return OverviewAccountRow(
                provider: .codex,
                model: model,
                identifier: Self.overviewRowIdentifier(provider: .codex, accountID: account.id),
                heightCacheScope: "overview-\(account.id)",
                accountID: account.id,
                storageText: nil)
        }
    }

    private func tokenAccountOverviewRows(_ display: TokenAccountMenuDisplay) -> [OverviewAccountRow] {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: display.snapshots.map { ($0.account.id, $0) })
        return display.accounts.compactMap { account in
            let accountSnapshot = snapshotsByID[account.id] ?? Self.unavailableTokenAccountSnapshot(account)
            guard let model = self.tokenAccountMenuCardModel(
                for: display.provider,
                accountSnapshot: accountSnapshot) else { return nil }
            return OverviewAccountRow(
                provider: display.provider,
                model: model,
                identifier: Self.overviewRowIdentifier(
                    provider: display.provider,
                    accountID: account.id.uuidString),
                heightCacheScope: "overview-\(account.id.uuidString)",
                accountID: account.id.uuidString,
                storageText: nil)
        }
    }

    private func claudeSwapOverviewRows(for provider: UsageProvider) -> [OverviewAccountRow]? {
        let accounts = self.store.claudeSwapAccountSnapshots
        guard self.settings.multiAccountMenuLayout == .stacked,
              accounts.count > 1,
              ClaudeSwapMenuPrecedence.prefersClaudeSwap(
                  provider: provider,
                  accountCount: accounts.count,
                  showSingleAccount: self.settings.claudeSwapShowSingleAccount)
        else {
            return nil
        }
        return accounts.compactMap { account in
            guard let model = self.claudeSwapOverviewCardModel(for: account) else { return nil }
            let accountID = "\(account.id.source):\(account.id.opaqueID)"
            return OverviewAccountRow(
                provider: .claude,
                model: model,
                identifier: Self.overviewRowIdentifier(provider: .claude, accountID: accountID),
                heightCacheScope: "overview-\(accountID)",
                accountID: accountID,
                storageText: nil)
        }
    }

    private static func unavailableCodexSnapshot(_ account: CodexVisibleAccount) -> CodexAccountUsageSnapshot {
        CodexAccountUsageSnapshot(
            account: account,
            snapshot: nil,
            error: L("Unavailable"),
            sourceLabel: nil)
    }

    private static func unavailableTokenAccountSnapshot(_ account: ProviderTokenAccount) -> TokenAccountUsageSnapshot {
        TokenAccountUsageSnapshot(
            account: account,
            snapshot: nil,
            error: L("Unavailable"),
            sourceLabel: nil,
            cacheKey: "overview-missing")
    }
}

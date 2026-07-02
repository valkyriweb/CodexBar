import AppKit
import CodexBarCore

// MARK: - Overview per-account row fan-out

extension StatusItemController {
    struct OverviewAccountRow {
        let provider: UsageProvider
        let model: UsageMenuCardView.Model
        let identifier: String
        let heightCacheScope: String
        var storageText: String?
    }

    /// Overview rows for one provider: one compact row per account when stacked
    /// multi-account snapshots are available, otherwise the single provider-level row.
    func overviewAccountRows(for provider: UsageProvider) -> [OverviewAccountRow] {
        let storageText = self.store.storageFootprintText(for: provider)

        if provider == .codex,
           let display = self.codexAccountMenuDisplay(for: .codex),
           display.showAll,
           !display.snapshots.isEmpty
        {
            let snapshotsByID = Dictionary(uniqueKeysWithValues: display.snapshots.map { ($0.id, $0) })
            let accountRows = display.accounts.compactMap { account -> OverviewAccountRow? in
                let accountSnapshot = snapshotsByID[account.id]
                let health = CodexAccountHealth.status(for: account, error: accountSnapshot?.error)
                guard let model = self.menuCardModel(
                    for: .codex,
                    snapshotOverride: accountSnapshot?.snapshot,
                    errorOverride: health.label,
                    forceOverrideCard: accountSnapshot == nil,
                    accountOverride: self.accountInfo(for: account)) else { return nil }
                guard !model.isOverviewErrorOnly else { return nil }
                return OverviewAccountRow(
                    provider: provider,
                    model: model,
                    identifier: Self.overviewRowIdentifier(provider: provider, accountID: account.id),
                    heightCacheScope: "overview-\(account.id)",
                    storageText: nil)
            }
            if accountRows.count > 1 {
                return Self.attachingStorageText(storageText, to: accountRows)
            }
        }

        if let display = self.tokenAccountMenuDisplay(for: provider),
           display.showAll,
           !display.snapshots.isEmpty
        {
            let accountRows = display.snapshots.compactMap { accountSnapshot -> OverviewAccountRow? in
                guard let model = self.menuCardModel(
                    for: provider,
                    snapshotOverride: accountSnapshot.snapshot,
                    errorOverride: accountSnapshot.error,
                    forceOverrideCard: accountSnapshot.snapshot == nil) else { return nil }
                guard !model.isOverviewErrorOnly else { return nil }
                return OverviewAccountRow(
                    provider: provider,
                    model: model,
                    identifier: Self.overviewRowIdentifier(
                        provider: provider,
                        accountID: accountSnapshot.account.id.uuidString),
                    heightCacheScope: "overview-\(accountSnapshot.account.id.uuidString)",
                    storageText: nil)
            }
            if accountRows.count > 1 {
                return Self.attachingStorageText(storageText, to: accountRows)
            }
        }

        guard let model = self.menuCardModel(for: provider), !model.isOverviewErrorOnly else { return [] }
        return [OverviewAccountRow(
            provider: provider,
            model: model,
            identifier: "\(Self.overviewRowIdentifierPrefix)\(provider.rawValue)",
            heightCacheScope: provider.rawValue,
            storageText: storageText)]
    }

    private static func overviewRowIdentifier(
        provider: UsageProvider,
        accountID: some CustomStringConvertible) -> String
    {
        "\(self.overviewRowIdentifierPrefix)\(provider.rawValue)-\(accountID)"
    }

    private static func attachingStorageText(_ text: String?, to rows: [OverviewAccountRow]) -> [OverviewAccountRow] {
        guard let text, !rows.isEmpty else { return rows }
        var rows = rows
        rows[rows.count - 1].storageText = text
        return rows
    }
}

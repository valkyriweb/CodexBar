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

    /// Overview rows for one provider. Stacked multi-account layouts get one row per configured
    /// account, using that account's snapshot only. A missing snapshot is unavailable, never the
    /// selected account's live usage. Single-account and segmented layouts keep the provider row.
    func overviewAccountRows(for provider: UsageProvider) -> [OverviewAccountRow] {
        let storageText = self.store.storageFootprintText(for: provider)
        if let accountRows = self.stackedAccountOverviewRows(for: provider), !accountRows.isEmpty {
            return Self.attachingStorageText(storageText, to: accountRows)
        }

        guard let model = self.menuCardModel(for: provider), !model.isOverviewErrorOnly else { return [] }
        return [OverviewAccountRow(
            provider: provider,
            model: model,
            identifier: Self.overviewRowIdentifier(provider: provider),
            heightCacheScope: provider.rawValue,
            storageText: storageText)]
    }

    static func overviewProvider(fromRepresentedObject represented: String) -> UsageProvider? {
        guard represented.hasPrefix(overviewRowIdentifierPrefix) else { return nil }
        let raw = String(represented.dropFirst(Self.overviewRowIdentifierPrefix.count))
        if let provider = UsageProvider(rawValue: raw) {
            return provider
        }
        return UsageProvider.allCases
            .filter { raw.hasPrefix($0.rawValue + "-") }
            .max { $0.rawValue.count < $1.rawValue.count }
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
           display.accounts.count > 1,
           !display.snapshots.isEmpty
        {
            return self.codexOverviewRows(display)
        }

        guard let display = self.tokenAccountMenuDisplay(for: provider),
              display.showAll,
              display.accounts.count > 1,
              !display.snapshots.isEmpty
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

    private static func attachingStorageText(
        _ text: String?,
        to rows: [OverviewAccountRow]) -> [OverviewAccountRow]
    {
        guard let text, !rows.isEmpty else { return rows }
        var rows = rows
        rows[rows.count - 1].storageText = text
        return rows
    }
}

# Custom Overview fork

This fork keeps one compact Overview row per account when the multi-account layout is **Stacked**. Codex rows use upstream visible-account projections and account-scoped snapshots; token-account rows use upstream credential-scoped snapshots. Row identities and height-cache keys stay distinct. Shared storage usage appears once per provider. An account requiring reauthentication stays visible with its own error instead of disappearing. Segmented mode retains upstream’s single-provider row.

## Upstream sync

- Original base: `v0.65.0`, `20a70d955d4744c795fefd720ff617da9d18480c`.
- Previous custom source: `ba88eb898a26a3f5e8731beaeb4e4f0cec79189e` (`wip/codexbar-typesafe-0650-overview`); verified against the installed 0.65.0 bundle’s `CodexGitCommit`.
- New upstream: `v0.74.0`, `c2f22ccf8751efc8fe697bfe4714769107965274`.
- Operation: merge the stable upstream tag, retaining ancestry.
- Adopt: upstream release behavior, dependencies, build scripts and credential/account isolation.
- Retain: `StatusItemController+OverviewAccountRows.swift` and the Menu/OverviewSubmenus integration.
- Equivalent: old architecture-test line-number corrections are replaced by upstream’s content-anchor matching. No tests or assertions are removed.

## Verification

`OverviewAccountRowsTests` checks separate identities, cache scopes and quota values for three Claude token accounts and three Codex profiles, plus expired-account visibility and segmented fallback. Also run the upstream account-display, account-switcher and provider-architecture suites, `make check`, and `make test`.

Build/package with full Xcode and the pinned SwiftPM dependencies. Test scripts require a recent Python with `waitid`/`WNOWAIT`; on the M2 Max, prepend `/opt/homebrew/opt/python@3.14/libexec/bin` to PATH. Use `--disable-keychain` for initial SwiftPM resolution: public dependencies do not need GitHub Keychain credentials.

Use an ad-hoc release package for the local fork. The upstream packager disables the Sparkle feed for ad-hoc builds. Remove the stock Homebrew cask without `--zap` before installing at `/Applications/CodexBar.app`, so a later cask upgrade cannot overwrite the custom build. Preserve all profile configuration and account stores.

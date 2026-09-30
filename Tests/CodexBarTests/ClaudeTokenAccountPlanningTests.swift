import Foundation
import Testing
@testable import CodexBarCore

/// Multi-account regression: a token-account fetch carrying that account's web session cookie
/// must not plan machine-global sources (keychain OAuth, local CLI) ahead of web — they always
/// describe the Mac's own signed-in account, so every per-account menu row would mirror it.
struct ClaudeTokenAccountPlanningTests {
    private func makeContext(
        selectedTokenAccountID: UUID?,
        cookieSource: ProviderCookieSource,
        manualCookieHeader: String?) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: ProviderSettingsSnapshot.make(
                claude: ProviderSettingsSnapshot.ClaudeProviderSettings(
                    usageDataSource: .auto,
                    webExtrasEnabled: false,
                    cookieSource: cookieSource,
                    manualCookieHeader: manualCookieHeader)),
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            selectedTokenAccountID: selectedTokenAccountID)
    }

    @Test
    func `token account with session cookie is account scoped`() {
        let context = self.makeContext(
            selectedTokenAccountID: UUID(),
            cookieSource: .manual,
            manualCookieHeader: "sessionKey=sk-ant-sid01-test")

        #expect(ClaudeProviderDescriptor.hasAccountScopedWebCookie(context: context))
    }

    @Test
    func `token account session cookie plans web only in app auto`() {
        let context = self.makeContext(
            selectedTokenAccountID: UUID(),
            cookieSource: .manual,
            manualCookieHeader: "sessionKey=sk-ant-sid01-test")

        let input = ClaudeProviderDescriptor.makePlanningInput(context: context)

        #expect(input.hasOAuthCredentials == false)
        #expect(input.hasCLI == false)
        #expect(input.hasWebSession)

        let plan = ClaudeSourcePlanner.resolve(input: input)
        #expect(plan.availableSteps.map(\.dataSource) == [.web])
    }

    @Test
    func `oauth token account is not account scoped web cookie`() {
        // OAuth setup-token accounts snapshot as cookieSource .off with no manual header;
        // they resolve through env/keychain OAuth and must keep the stock auto plan.
        let context = self.makeContext(
            selectedTokenAccountID: UUID(),
            cookieSource: .off,
            manualCookieHeader: nil)

        #expect(ClaudeProviderDescriptor.hasAccountScopedWebCookie(context: context) == false)
    }

    @Test
    func `manual cookie without token account keeps stock planning`() {
        // A single manually-pasted cookie (no token accounts) predates multi-account and
        // keeps the stock oauth-first auto order.
        let context = self.makeContext(
            selectedTokenAccountID: nil,
            cookieSource: .manual,
            manualCookieHeader: "sessionKey=sk-ant-sid01-test")

        #expect(ClaudeProviderDescriptor.hasAccountScopedWebCookie(context: context) == false)
    }

    @Test
    func `token account without session key in header is not account scoped`() {
        let context = self.makeContext(
            selectedTokenAccountID: UUID(),
            cookieSource: .manual,
            manualCookieHeader: "other=value")

        #expect(ClaudeProviderDescriptor.hasAccountScopedWebCookie(context: context) == false)
    }
}

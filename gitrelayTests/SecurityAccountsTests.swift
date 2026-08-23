import Foundation
import Testing
@testable import GitRelay

// MARK: - 最后使用 copy (#104)

struct ProviderAccountLastUsedTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func anAccountNobodyHasUsedSaysSo() {
        #expect(ProviderAccountLastUsed.state(for: nil, now: now) == .never)
    }

    @Test func aTimestampFromSecondsAgoReadsAsJustNow() {
        #expect(
            ProviderAccountLastUsed.state(for: now.addingTimeInterval(-1), now: now) == .justNow
        )
        #expect(
            ProviderAccountLastUsed.state(for: now.addingTimeInterval(-59), now: now) == .justNow
        )
    }

    @Test func aMinuteIsWhereTheRelativePhraseTakesOver() {
        let minuteAgo = now.addingTimeInterval(-60)
        #expect(ProviderAccountLastUsed.state(for: minuteAgo, now: now) == .at(minuteAgo))

        let hoursAgo = now.addingTimeInterval(-3 * 3_600)
        #expect(ProviderAccountLastUsed.state(for: hoursAgo, now: now) == .at(hoursAgo))
    }

    /// A machine whose clock jumped forward should not report a use in the future.
    @Test func aTimestampAheadOfTheClockStillReadsAsJustNow() {
        #expect(
            ProviderAccountLastUsed.state(for: now.addingTimeInterval(600), now: now) == .justNow
        )
    }

    @Test func eachStateSaysSomethingAndTheyDoNotCollide() {
        let never = ProviderAccountLastUsed.never.text
        let justNow = ProviderAccountLastUsed.justNow.text
        let dated = ProviderAccountLastUsed.at(now.addingTimeInterval(-86_400)).text

        #expect(!never.isEmpty)
        #expect(!justNow.isEmpty)
        #expect(!dated.isEmpty)
        #expect(never != justNow)
        #expect(dated != never)
    }

    @Test func theSummaryCellReadsFromTheRecordTimestamp() {
        let used = ProviderAccountSummary(
            provider: .github,
            label: "work",
            host: nil,
            hasToken: true,
            lastUsedAt: now.addingTimeInterval(-7_200)
        )
        let untouched = ProviderAccountSummary(
            provider: .github,
            label: "spare",
            host: nil,
            hasToken: true
        )

        #expect(used.lastUsed(now: now) == .at(now.addingTimeInterval(-7_200)))
        #expect(untouched.lastUsed(now: now) == .never)
        #expect(used.lastUsedText(now: now) != untouched.lastUsedText(now: now))
    }
}

// MARK: - The 安全 account list and its provider filter (#104)

struct ProviderAccountListTests {
    private func summaries() -> [ProviderAccountSummary] {
        ProviderAccountSummary.summaries(
            recordsByProvider: [
                .gitlab: [ProviderAccountRecord(label: "work")],
                .github: [
                    ProviderAccountRecord(label: "work"),
                    ProviderAccountRecord(label: "personal")
                ],
                .gitea: [ProviderAccountRecord(label: "homelab")]
            ],
            hasToken: { _, label in label != "personal" }
        )
    }

    @Test func theListRunsInSidebarOrderThenByName() {
        let rows = summaries()
        #expect(rows.map(\.provider) == [.github, .github, .gitlab, .gitea])
        #expect(rows.map(\.label) == ["personal", "work", "work", "homelab"])
    }

    @Test func tokenPresenceIsReportedPerAccountNotPerProvider() {
        let rows = summaries()
        #expect(rows.map(\.hasToken) == [false, true, true, true])
    }

    @Test func noFilterMeansEveryProvider() {
        let rows = summaries()
        #expect(ProviderAccountSummary.filtered(rows, provider: nil) == rows)
    }

    @Test func aProviderFilterKeepsOnlyThatProvider() {
        let rows = summaries()

        let github = ProviderAccountSummary.filtered(rows, provider: .github)
        #expect(github.map(\.label) == ["personal", "work"])
        #expect(github.allSatisfy { $0.provider == .github })

        #expect(ProviderAccountSummary.filtered(rows, provider: .gitlab).count == 1)
        #expect(ProviderAccountSummary.filtered(rows, provider: .gitea).count == 1)
    }

    @Test func filteringToAProviderWithNothingSavedComesBackEmpty() {
        let onlyGitHub = ProviderAccountSummary.summaries(
            recordsByProvider: [.github: [ProviderAccountRecord(label: "work")]],
            hasToken: { _, _ in true }
        )
        #expect(ProviderAccountSummary.filtered(onlyGitHub, provider: .gitlab).isEmpty)
    }

    @Test func theUntouchedDefaultRecordIsNotAnAccount() {
        let placeholder = ProviderAccountSummary(
            provider: .github,
            label: ProviderAccount.defaultLabel,
            host: nil,
            hasToken: false
        )
        #expect(placeholder.isUntouchedPlaceholder)
        #expect(
            ProviderAccountSummary(
                provider: .github,
                label: ProviderAccount.defaultLabel,
                host: "   ",
                hasToken: false
            ).isUntouchedPlaceholder
        )
    }

    @Test func aDefaultRecordSomebodyTouchedIsAnAccount() {
        let withToken = ProviderAccountSummary(
            provider: .github,
            label: ProviderAccount.defaultLabel,
            host: nil,
            hasToken: true
        )
        let withHost = ProviderAccountSummary(
            provider: .gitlab,
            label: ProviderAccount.defaultLabel,
            host: "git.example.com",
            hasToken: false
        )
        let used = ProviderAccountSummary(
            provider: .gitea,
            label: ProviderAccount.defaultLabel,
            host: nil,
            hasToken: false,
            lastUsedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let named = ProviderAccountSummary(
            provider: .github,
            label: "work",
            host: nil,
            hasToken: false
        )

        #expect(!withToken.isUntouchedPlaceholder)
        #expect(!withHost.isUntouchedPlaceholder)
        #expect(!used.isUntouchedPlaceholder)
        #expect(!named.isUntouchedPlaceholder)
    }

    @Test func aFreshInstallListsNothingRatherThanThreeEmptyProviders() {
        let rows = ProviderAccountSummary.summaries(
            recordsByProvider: [
                .github: [ProviderAccountRecord(label: ProviderAccount.defaultLabel)],
                .gitlab: [ProviderAccountRecord(label: ProviderAccount.defaultLabel)],
                .gitea: [ProviderAccountRecord(label: ProviderAccount.defaultLabel)]
            ],
            hasToken: { _, _ in false }
        )
        #expect(rows.count == 3)
        #expect(ProviderAccountSummary.listed(rows).isEmpty)
    }
}

// MARK: - What 测试 reports (#104)

struct ProviderTokenTestDecisionTests {
    @Test func githubAndGitlabTokensAreCheckedAgainstListingScopes() {
        #expect(ProviderTokenTest.usage(for: .github).requiredScopes == ["repo"])
        #expect(ProviderTokenTest.usage(for: .gitlab).requiredScopes == ["read_api"])
    }

    /// Gitea only ever acts as a target here, so its token has to be able to
    /// create repositories rather than merely list them.
    @Test func giteaTokensAreCheckedAgainstTargetCreation() {
        #expect(ProviderTokenTest.usage(for: .gitea) == .giteaTargetCreate)
        #expect(ProviderTokenTest.usage(for: .gitea).requiredScopes == ["write:repository"])
    }

    @Test func aTokenWithTheRequiredScopeIsOK() {
        let outcome = ProviderTokenTest.outcome(probe: .scopes(["repo"]), provider: .github)
        #expect(outcome == .ok(grantedScopes: ["repo"]))
        #expect(outcome.tone == .ok)
    }

    @Test func anAcceptedSubstituteScopeIsAlsoOK() {
        #expect(
            ProviderTokenTest.outcome(probe: .scopes(["public_repo"]), provider: .github)
                == .ok(grantedScopes: ["public_repo"])
        )
        #expect(
            ProviderTokenTest.outcome(probe: .scopes(["api"]), provider: .gitlab)
                == .ok(grantedScopes: ["api"])
        )
    }

    @Test func aTokenShortOfAScopeNamesTheOneItIsMissing() {
        let outcome = ProviderTokenTest.outcome(probe: .scopes(["read:user"]), provider: .github)
        #expect(outcome == .missingScopes(["repo"]))
        #expect(outcome.tone == .warning)
        #expect(outcome.rowText.contains("repo"))

        #expect(
            ProviderTokenTest.outcome(probe: .scopes(["read:repository"]), provider: .gitea)
                == .missingScopes(["write:repository"])
        )
    }

    /// A GitHub fine-grained token authenticates without sending any scope
    /// header. That is a token whose scopes cannot be read, not a token short
    /// of one, so it must not be reported as missing a scope.
    @Test func aProviderThatWillNotNameScopesStillCountsAsAccepted() {
        let outcome = ProviderTokenTest.outcome(probe: .scopes([]), provider: .github)
        #expect(outcome == .ok(grantedScopes: []))
        #expect(outcome.tone == .ok)
        #expect(outcome.rowText != ProviderTokenTestOutcome.ok(grantedScopes: ["repo"]).rowText)
    }

    @Test func aRefusedCheckKeepsTheReasonItWasRefusedFor() {
        for rejection in [
            ProviderTokenRejection.unauthorized,
            .forbidden,
            .notFound,
            .network,
            .unreadableResponse,
            .httpError,
            .unknown
        ] {
            let outcome = ProviderTokenTest.outcome(probe: .refused(rejection), provider: .github)
            #expect(outcome == .rejected(rejection))
            #expect(outcome.tone == .error)
            #expect(!outcome.rowText.isEmpty)
        }
    }

    @Test func eachRefusalReadsDifferentlyFromTheOthers() {
        let texts = [
            ProviderTokenRejection.unauthorized,
            .forbidden,
            .notFound,
            .network,
            .unreadableResponse,
            .httpError,
            .unknown
        ].map(\.text)
        #expect(Set(texts).count == texts.count)
    }

    @Test func anAccountWithNothingSavedIsNotReportedAsRejected() {
        let outcome = ProviderTokenTest.outcome(probe: .noToken, provider: .gitlab)
        #expect(outcome == .noToken)
        #expect(outcome.tone == .neutral)
    }

    /// A token one scope short still reached its host, so it counts as a use.
    @Test func onlyAnAnsweredCheckUpdatesLastUsed() {
        #expect(ProviderTokenTestOutcome.ok(grantedScopes: ["repo"]).marksAccountUsed)
        #expect(ProviderTokenTestOutcome.ok(grantedScopes: []).marksAccountUsed)
        #expect(ProviderTokenTestOutcome.missingScopes(["repo"]).marksAccountUsed)
        #expect(!ProviderTokenTestOutcome.rejected(.unauthorized).marksAccountUsed)
        #expect(!ProviderTokenTestOutcome.noToken.marksAccountUsed)
    }

    @Test func everyOutcomeHasALineAndAGlyphForItsRow() {
        let outcomes: [ProviderTokenTestOutcome] = [
            .ok(grantedScopes: ["repo"]),
            .ok(grantedScopes: []),
            .missingScopes(["repo"]),
            .rejected(.unauthorized),
            .noToken
        ]
        for outcome in outcomes {
            #expect(!outcome.rowText.isEmpty)
            #expect(!outcome.symbolName.isEmpty)
        }
    }
}

// MARK: - API errors as row copy (#104)

struct ProviderTokenTesterRejectionTests {
    @Test func listingErrorsMapOntoTheirOwnReason() {
        #expect(ProviderTokenTester.rejection(for: ProviderAPIError.unauthorized(nil)) == .unauthorized)
        #expect(ProviderTokenTester.rejection(for: ProviderAPIError.forbidden("rate limited")) == .forbidden)
        #expect(ProviderTokenTester.rejection(for: ProviderAPIError.notFound(nil)) == .notFound)
        #expect(
            ProviderTokenTester.rejection(for: ProviderAPIError.network(URLError(.notConnectedToInternet)))
                == .network
        )
        #expect(
            ProviderTokenTester.rejection(for: ProviderAPIError.decoding(URLError(.cannotParseResponse)))
                == .unreadableResponse
        )
        #expect(
            ProviderTokenTester.rejection(for: ProviderAPIError.http(status: 500, message: nil))
                == .httpError
        )
    }

    @Test func targetErrorsMapOntoTheSameReasons() {
        #expect(ProviderTokenTester.rejection(for: TargetProviderAPIError.unauthorized(nil)) == .unauthorized)
        #expect(ProviderTokenTester.rejection(for: TargetProviderAPIError.forbidden(nil)) == .forbidden)
        #expect(ProviderTokenTester.rejection(for: TargetProviderAPIError.validation(nil)) == .httpError)
        #expect(
            ProviderTokenTester.rejection(for: TargetProviderAPIError.network(URLError(.timedOut)))
                == .network
        )
    }

    @Test func aBareTransportFailureIsANetworkProblem() {
        #expect(ProviderTokenTester.rejection(for: URLError(.timedOut)) == .network)
    }

    @Test func anythingElseIsReportedAsAPlainFailure() {
        struct Surprise: Error {}
        #expect(ProviderTokenTester.rejection(for: Surprise()) == .unknown)
    }
}

// MARK: - Host to API root (#104)

struct ProviderAPIBaseURLTests {
    @Test func aBareHostGetsHTTPSAndTheAPIPath() {
        #expect(
            ProviderAPIBaseURL.resolve(provider: .gitlab, host: "gitlab.example.com")?.absoluteString
                == "https://gitlab.example.com/api/v4"
        )
        #expect(
            ProviderAPIBaseURL.resolve(provider: .gitea, host: "gitea.example.com")?.absoluteString
                == "https://gitea.example.com/api/v1"
        )
    }

    @Test func aHostThatAlreadyCarriesTheAPIPathIsNotDoubled() {
        #expect(
            ProviderAPIBaseURL.resolve(provider: .gitlab, host: "https://gitlab.example.com/api/v4/")?
                .absoluteString == "https://gitlab.example.com/api/v4"
        )
        #expect(
            ProviderAPIBaseURL.resolve(provider: .gitea, host: "gitea.example.com/api/v1")?
                .absoluteString == "https://gitea.example.com/api/v1"
        )
    }

    /// A self-hosted instance reachable only over plain HTTP has to stay reachable.
    @Test func aTypedSchemeIsKept() {
        #expect(
            ProviderAPIBaseURL.resolve(provider: .gitea, host: "http://git.internal:3000")?
                .absoluteString == "http://git.internal:3000/api/v1"
        )
    }

    @Test func githubDotComAnswersOnItsOwnAPIHost() {
        #expect(
            ProviderAPIBaseURL.resolve(provider: .github, host: "github.com")
                == GitProvider.github.apiBaseURL
        )
        #expect(
            ProviderAPIBaseURL.resolve(provider: .github, host: "https://www.github.com/")
                == GitProvider.github.apiBaseURL
        )
    }

    @Test func aGitHubEnterpriseHostAnswersUnderItsOwnPath() {
        #expect(
            ProviderAPIBaseURL.resolve(provider: .github, host: "ghe.example.com")?.absoluteString
                == "https://ghe.example.com/api/v3"
        )
    }

    @Test func noHostIsNoAnswerUntilACallerAsksForTheDefault() {
        #expect(ProviderAPIBaseURL.resolve(provider: .gitlab, host: nil) == nil)
        #expect(ProviderAPIBaseURL.resolve(provider: .gitlab, host: "   ") == nil)
        #expect(
            ProviderAPIBaseURL.resolveOrDefault(provider: .gitlab, host: nil)
                == GitProvider.gitlab.apiBaseURL
        )
        #expect(
            ProviderAPIBaseURL.resolveOrDefault(provider: .github, host: "")
                == GitProvider.github.apiBaseURL
        )
    }
}

// MARK: - Last used on the account record (#104)

struct ProviderAccountLastUsedStoreTests {
    private func scratchDefaults() throws -> (UserDefaults, String) {
        let suite = "gitrelay.tests.security-accounts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test func anAccountStartsWithNothingRecorded() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        ProviderAccountStore.ensureInitialized(defaults: defaults)
        #expect(
            ProviderAccountStore.lastUsedAt(
                for: .github,
                label: ProviderAccount.defaultLabel,
                defaults: defaults
            ) == nil
        )
    }

    @Test func markingAnAccountUsedRecordsTheMoment() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let moment = Date(timeIntervalSince1970: 1_750_000_000)
        _ = try ProviderAccountStore.addAccount(label: "Work", for: .github, defaults: defaults)
        ProviderAccountStore.markUsed(for: .github, label: "work", at: moment, defaults: defaults)

        #expect(
            ProviderAccountStore.lastUsedAt(for: .github, label: "work", defaults: defaults) == moment
        )
        // The neighbouring account is untouched by the one that was used.
        #expect(
            ProviderAccountStore.lastUsedAt(
                for: .github,
                label: ProviderAccount.defaultLabel,
                defaults: defaults
            ) == nil
        )
    }

    @Test func markingAnAccountThatIsNotThereChangesNothing() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        ProviderAccountStore.markUsed(for: .gitlab, label: "ghost", defaults: defaults)
        #expect(ProviderAccountStore.accountLabels(for: .gitlab, defaults: defaults) == ["default"])
        #expect(
            ProviderAccountStore.lastUsedAt(for: .gitlab, label: "ghost", defaults: defaults) == nil
        )
    }

    @Test func aRecordWithoutLastUsedDateDecodesAsNeverUsed() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let encoded = #"{"github":[{"label":"default"},{"label":"work","host":"github.com"}]}"#
        defaults.set(Data(encoded.utf8), forKey: "GitRelay.connections.registry")

        let records = ProviderAccountStore.accounts(for: .github, defaults: defaults)
        #expect(records.map(\.label) == ["default", "work"])
        #expect(records.allSatisfy { $0.lastUsedAt == nil })
    }

    @Test func everyProviderShowsUpInTheOneCallTheListMakes() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = try ProviderAccountStore.addAccount(label: "work", for: .gitlab, defaults: defaults)
        let all = ProviderAccountStore.allAccounts(defaults: defaults)

        #expect(Set(all.keys) == Set(GitProvider.allCases))
        #expect(all[.gitlab]?.map(\.label) == ["default", "work"])
    }

    @Test func aRepeatedAccountNameReusesTheAccountInsteadOfFailing() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = try ProviderAccountStore.ensureAccount(label: "Work", for: .github, defaults: defaults)
        let again = try ProviderAccountStore.ensureAccount(label: "work", for: .github, defaults: defaults)

        #expect(first.label == "work")
        #expect(again.label == "work")
        #expect(ProviderAccountStore.accountLabels(for: .github, defaults: defaults) == ["default", "work"])
    }

    @Test func anUnusableAccountNameIsStillRefused() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(throws: ProviderAccountStoreError.self) {
            _ = try ProviderAccountStore.ensureAccount(label: "  ", for: .github, defaults: defaults)
        }
    }

    /// Last used is local bookkeeping, not part of the portable configuration.
    @Test func exportCarriesNeitherTheTimestampNorTheToken() throws {
        let (defaults, suite) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = try ProviderAccountStore.addAccount(label: "work", for: .github, defaults: defaults)
        ProviderAccountStore.markUsed(for: .github, label: "work", defaults: defaults)

        let document = ConfigExportCodec.makeDocument(
            mirrors: [],
            providerAccounts: ProviderAccountStore.exportedAccounts(defaults: defaults),
            orgSubscriptions: [],
            orgSubscriptionPreferences: nil
        )
        let data = try ConfigExportCodec.encode(document)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"work\""))
        #expect(!json.lowercased().contains("lastused"))
        #expect(!ConfigExportCodec.containsForbiddenSecretFields(json))
    }
}

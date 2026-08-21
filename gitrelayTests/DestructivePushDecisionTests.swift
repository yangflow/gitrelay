import Foundation
import Testing
@testable import GitRelay

// MARK: - The tri-state (#102)

struct DestructivePushDecisionTests {
    @Test func cancelIsTheOnlyChoiceThatStopsTheSync() {
        #expect(!DestructivePushDecision.cancel.pushesToDestination)
        #expect(DestructivePushDecision.overwrite.pushesToDestination)
        #expect(DestructivePushDecision.checkBranch.pushesToDestination)
    }

    @Test func onlyOverwriteMovesTheDestinationsOwnBranches() {
        #expect(DestructivePushDecision.overwrite.preservesDestinationBranches == false)
        #expect(DestructivePushDecision.cancel.preservesDestinationBranches)
        #expect(DestructivePushDecision.checkBranch.preservesDestinationBranches)
    }

    @Test func theTriStateHasExactlyThreeChoices() {
        #expect(DestructivePushDecision.allCases == [.cancel, .overwrite, .checkBranch])
    }

    @Test func headlessSyncNeverPicksCheckBranchOnItsOwn() {
        // No sheet without a UI, so `.auto` overwrites and `.strict` stops. The
        // check branch stays a deliberate choice.
        let plan = DestructivePushPlan(deletedRefs: ["gone"], forcedUpdateRefs: ["main"])

        func headlessDecision(_ policy: DestructivePushPolicy) -> DestructivePushDecision {
            policy.requiresConfirmation(for: plan) ? .cancel : .overwrite
        }

        #expect(headlessDecision(.strict) == .cancel)
        #expect(headlessDecision(.auto) == .overwrite)
    }
}

// MARK: - Check-branch ref mapping (#102)

struct CheckBranchRefMappingTests {
    @Test func namespaceIsTheDocumentedOne() {
        #expect(CheckBranchRefMapping.namespace == "gitrelay-check")
        #expect(CheckBranchRefMapping.displayPrefix == "gitrelay-check/")
    }

    @Test func branchesAndTagsKeepTheirCategory() {
        #expect(CheckBranchRefMapping.checkRef(for: "refs/heads/main") == "refs/heads/gitrelay-check/main")
        #expect(CheckBranchRefMapping.checkRef(for: "refs/tags/v1.0.0") == "refs/tags/gitrelay-check/v1.0.0")
        #expect(CheckBranchRefMapping.checkRef(for: "refs/notes/commits") == "refs/notes/gitrelay-check/commits")
    }

    @Test func wildcardsSurviveTheMapping() {
        #expect(CheckBranchRefMapping.checkRef(for: "refs/heads/*") == "refs/heads/gitrelay-check/*")
        #expect(CheckBranchRefMapping.checkRef(for: "refs/tags/*") == "refs/tags/gitrelay-check/*")
    }

    @Test func bareNamesAreReadAsBranches() {
        #expect(CheckBranchRefMapping.checkRef(for: "main") == "refs/heads/gitrelay-check/main")
        #expect(CheckBranchRefMapping.checkRef(for: " release/2.0 ") == "refs/heads/gitrelay-check/release/2.0")
    }

    @Test func refsAlreadyInsideTheNamespaceAreLeftAlone() {
        let once = CheckBranchRefMapping.checkRef(for: "refs/heads/main")
        #expect(once == "refs/heads/gitrelay-check/main")
        #expect(CheckBranchRefMapping.checkRef(for: "gitrelay-check/main") == "refs/heads/gitrelay-check/main")
        #expect(once.flatMap { CheckBranchRefMapping.checkRef(for: $0) } == once)
    }

    @Test func unusableRefsAreDropped() {
        #expect(CheckBranchRefMapping.checkRef(for: "") == nil)
        #expect(CheckBranchRefMapping.checkRef(for: "   ") == nil)
        #expect(CheckBranchRefMapping.checkRef(for: "refs/stash") == nil)
    }

    @Test func defaultMirrorRefSpecsMapOntoTheNamespace() {
        let pushRefSpecs = GitSyncArguments.pushRefSpecs(from: RepoConfig.defaultRefSpecs)

        #expect(CheckBranchRefMapping.refSpecs(from: pushRefSpecs) == [
            "+refs/heads/*:refs/heads/gitrelay-check/*",
            "+refs/tags/*:refs/tags/gitrelay-check/*"
        ])
    }

    @Test func selectiveRefSpecsKeepTheirSourceSide() {
        let pushRefSpecs = GitSyncArguments.pushRefSpecs(from: [
            "+refs/heads/main:refs/heads/main",
            "refs/heads/release/*:refs/heads/release/*"
        ])

        #expect(CheckBranchRefMapping.refSpecs(from: pushRefSpecs) == [
            "+refs/heads/main:refs/heads/gitrelay-check/main",
            "+refs/heads/release/*:refs/heads/gitrelay-check/release/*"
        ])
    }

    @Test func noMappedRefSpecCanTouchARefOutsideTheNamespace() {
        let mapped = CheckBranchRefMapping.refSpecs(from: GitSyncArguments.pushRefSpecs(
            from: RepoConfig.defaultRefSpecs + ["+refs/heads/main:refs/heads/main"]
        ))

        #expect(!mapped.isEmpty)
        for refSpec in mapped {
            let destination = refSpec.split(separator: ":", maxSplits: 1).last.map(String.init)
            #expect(destination?.contains("/gitrelay-check/") == true)
        }
    }

    @Test func refSpecsWithoutBothSidesAreDropped() {
        #expect(CheckBranchRefMapping.refSpec(from: "") == nil)
        // No colon, so there is no source side to push from.
        #expect(CheckBranchRefMapping.refSpec(from: "refs/heads/main") == nil)
        #expect(CheckBranchRefMapping.refSpec(from: ":refs/heads/main") == nil)
        #expect(CheckBranchRefMapping.refSpec(from: "refs/heads/main:") == nil)
        #expect(CheckBranchRefMapping.refSpecs(from: ["", "  ", "refs/heads/main"]).isEmpty)
    }
}

// MARK: - Sheet copy (#102)

struct DestructivePushCopyTests {
    @Test func titleMatchesTheLockedCopy() {
        #expect(DestructivePushCopy.title == "Target already has different history")
        #expect(DestructivePushCopy.cancelTitle == "Cancel")
        #expect(DestructivePushCopy.overwriteTitle == "Overwrite and Sync")
        #expect(DestructivePushCopy.checkBranchTitle == "Push to Check Branch")
    }

    @Test func divergenceNamesTheCountWhenGitCouldAnswer() {
        let plan = DestructivePushPlan(deletedRefs: [], forcedUpdateRefs: ["main"])
            .withDestinationOnlyCommits(14)

        #expect(DestructivePushCopy.divergence(destinationLabel: "gitlab.com/yangflow/keychord", plan: plan)
            == "gitlab.com/yangflow/keychord already has 14 commits that the source does not.")
    }

    @Test func divergenceDropsTheCountWhenItIsUnknown() {
        let plan = DestructivePushPlan(deletedRefs: [], forcedUpdateRefs: ["main"])

        #expect(plan.destinationOnlyCommits == nil)
        #expect(DestructivePushCopy.divergence(destinationLabel: "example.com/a/b", plan: plan)
            == "example.com/a/b already has commits that the source does not.")
        #expect(DestructivePushCopy.divergence(
            destinationLabel: "example.com/a/b",
            plan: plan.withDestinationOnlyCommits(0)
        ) == "example.com/a/b already has commits that the source does not.")
    }

    @Test func explanationsCoverBothOutcomes() {
        #expect(DestructivePushCopy.overwriteExplanation.contains("replaced"))
        #expect(DestructivePushCopy.checkBranchExplanation.contains("gitrelay-check/"))
    }

    @Test func destinationLabelReadsBackAsHostAndPath() {
        #expect(DestructivePushCopy.destinationLabel(
            targetURL: "https://gitlab.com/yangflow/keychord.git",
            fallback: "keychord"
        ) == "gitlab.com/yangflow/keychord")

        #expect(DestructivePushCopy.destinationLabel(
            targetURL: "git@github.com:user/mirror.git",
            fallback: "mirror"
        ) == "github.com/user/mirror")
    }

    @Test func destinationLabelFallsBackToTheRepoName() {
        #expect(DestructivePushCopy.destinationLabel(targetURL: nil, fallback: "keychord") == "keychord")
        #expect(DestructivePushCopy.destinationLabel(targetURL: "  ", fallback: "keychord") == "keychord")
        #expect(DestructivePushCopy.destinationLabel(targetURL: "local-mirror", fallback: "keychord") == "local-mirror")
    }
}

// MARK: - Dry-run plan carrying the divergence count (#102)

struct DestructivePushPlanDivergenceTests {
    @Test func parsedPlansStartWithoutACount() {
        let plan = DestructivePushPlan.parse(gitOutput: """
        To github.com:user/mirror.git
         + abc1234...def5678 main -> main (forced update)
        """)

        #expect(plan.destinationOnlyCommits == nil)
        #expect(plan.isDestructive)
    }

    @Test func theCountAttachesWithoutDisturbingTheRefLists() {
        let plan = DestructivePushPlan(deletedRefs: ["old"], forcedUpdateRefs: ["main"])
        let counted = plan.withDestinationOnlyCommits(14)

        #expect(counted.destinationOnlyCommits == 14)
        #expect(counted.deletedRefs == plan.deletedRefs)
        #expect(counted.forcedUpdateRefs == plan.forcedUpdateRefs)
        #expect(counted.summary == plan.summary)
        #expect(counted.withDestinationOnlyCommits(nil) == plan)
    }

    @Test func destinationOnlyCountArgsAskGitForDestRefsMinusSourceRefs() {
        #expect(GitSyncArguments.destinationOnlyCommitCountArgs == [
            "rev-list", "--count", "--glob=refs/dst/heads", "--not", "--glob=refs/heads"
        ])
    }
}

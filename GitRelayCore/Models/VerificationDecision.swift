import Foundation

/// Pure decision for src/dst tip comparison used by integrity verification.
enum VerificationDecision: Equatable {
    case matched(reason: MatchReason)
    case diverged(Detail)
    case inconclusive(String)

    enum MatchReason: Equatable {
        case identicalCommitSHA
        case identicalTreeHash
    }

    struct Detail: Equatable {
        let branch: String
        let srcCommitSHA: String
        let dstCommitSHA: String
        let srcTreeHash: String
        let dstTreeHash: String
        var summaryOverride: String?

        var summary: String {
            summaryOverride ?? String(localized: "Content divergence on branch \(branch): src \(srcCommitSHA.truncatingSHA) / dst \(dstCommitSHA.truncatingSHA)")
        }
    }

    /// Decide after ls-remote (and optional tree-hash fetch).
    /// - When commit SHAs match → matched (no tree fetch needed).
    /// - When SHAs differ and both tree hashes are present → compare trees.
    /// - Missing refs or incomplete tree data → inconclusive.
    static func decide(
        branch: String,
        srcCommitSHA: String?,
        dstCommitSHA: String?,
        srcTreeHash: String? = nil,
        dstTreeHash: String? = nil
    ) -> VerificationDecision {
        guard let srcCommitSHA, !srcCommitSHA.isEmpty else {
            return .inconclusive(String(localized: "Source repository is missing branch \(branch)"))
        }
        guard let dstCommitSHA, !dstCommitSHA.isEmpty else {
            return .inconclusive(String(localized: "Target repository is missing branch \(branch)"))
        }

        if srcCommitSHA == dstCommitSHA {
            return .matched(reason: .identicalCommitSHA)
        }

        guard let srcTreeHash, !srcTreeHash.isEmpty,
              let dstTreeHash, !dstTreeHash.isEmpty else {
            return .inconclusive(String(localized: "Commit SHAs differ, but the tree hashes could not be obtained from both sides"))
        }

        if srcTreeHash == dstTreeHash {
            return .matched(reason: .identicalTreeHash)
        }

        return .diverged(
            Detail(
                branch: branch,
                srcCommitSHA: srcCommitSHA,
                dstCommitSHA: dstCommitSHA,
                srcTreeHash: srcTreeHash,
                dstTreeHash: dstTreeHash
            )
        )
    }
}

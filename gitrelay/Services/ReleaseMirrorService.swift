import Foundation

@MainActor
final class ReleaseMirrorService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func mirrorReleases(
        plan: MirrorPlan,
        destination: MirrorDestination,
        log: @escaping (String) -> Void
    ) async throws {
        guard plan.policy.content.mirrorsReleases else { return }
        guard case .git(let target) = destination.location else { return }

        guard let srcPath = GitRemoteRepoPath.parse(from: plan.source.url),
              let dstPath = GitRemoteRepoPath.parse(from: target.url) else {
            throw ReleaseMirrorError.invalidRemoteURL(plan.source.url)
        }

        let srcClient = try ReleaseProviderClientFactory.makeClient(
            remoteURL: plan.source.url,
            auth: plan.source.auth,
            side: "source"
        )
        let dstClient = try ReleaseProviderClientFactory.makeClient(
            remoteURL: target.url,
            auth: target.auth,
            side: "target"
        )

        var resume = ReleaseMirrorResumeStore.loadResume(
            repoID: plan.id,
            targetID: destination.id
        )
        updatePersistedStatus(
            mirrorID: plan.id,
            destinationID: destination.id,
            destinationURL: target.url,
            tags: [],
            isSyncing: true,
            lastError: nil
        )

        log("Listing source releases…")
        let sourceReleases = try await srcClient.listReleases(ownerRepo: srcPath.ownerRepoPath)
        var tagStatuses = buildInitialTagStatuses(source: sourceReleases)
        log("Listing target releases…")
        let targetReleases = try await dstClient.listReleases(ownerRepo: dstPath.ownerRepoPath)
        updatePersistedStatus(
            mirrorID: plan.id,
            destinationID: destination.id,
            destinationURL: target.url,
            tags: tagStatuses,
            isSyncing: true,
            lastError: nil
        )
        let plans = ReleaseMirrorDiff.plans(source: sourceReleases, target: targetReleases, resume: resume)

        if plans.isEmpty {
            log("All releases and assets are already mirrored.")
            markAllSynced(&tagStatuses)
            updatePersistedStatus(
                mirrorID: plan.id,
                destinationID: destination.id,
                destinationURL: target.url,
                tags: tagStatuses,
                isSyncing: false,
                lastError: nil,
                lastSyncedAt: .now
            )
            return
        }

        log("Mirroring \(plans.count) release(s) with pending assets…")
        let lastError: String? = nil

        for releasePlan in plans {
            updateTagStatus(
                &tagStatuses,
                tagName: releasePlan.release.tagName,
                state: .syncing,
                completed: Array(resume.completedAssets(for: releasePlan.release.tagName)),
                totalAssets: releasePlan.release.assets.count,
                error: nil
            )
            updatePersistedStatus(
                mirrorID: plan.id,
                destinationID: destination.id,
                destinationURL: target.url,
                tags: tagStatuses,
                isSyncing: true,
                lastError: nil
            )

            var uploadURL: String?
            let targetHasRelease = targetReleases.contains {
                $0.tagName == releasePlan.release.tagName
            }
            if releasePlan.needsCreate || !targetHasRelease {
                log("Creating release \(releasePlan.release.tagName) on target…")
                uploadURL = try await dstClient.createRelease(
                    ownerRepo: dstPath.ownerRepoPath,
                    release: releasePlan.release
                )
            } else if dstClient.provider == .github {
                uploadURL = try await dstClient.fetchReleaseUploadURL(
                    ownerRepo: dstPath.ownerRepoPath,
                    tagName: releasePlan.release.tagName
                )
            }

            for assetName in releasePlan.missingAssetNames {
                guard let asset = releasePlan.release.assets.first(where: { $0.name == assetName }) else {
                    continue
                }
                log("Downloading asset \(asset.name) (\(asset.size.map(String.init) ?? "?") bytes)…")
                let data = try await downloadAsset(
                    from: asset.downloadURL,
                    auth: plan.source.auth,
                    remoteURL: plan.source.url
                )

                log("Uploading asset \(asset.name) to target…")
                try await dstClient.uploadAsset(
                    ownerRepo: dstPath.ownerRepoPath,
                    tagName: releasePlan.release.tagName,
                    releaseUploadURL: uploadURL,
                    asset: asset,
                    data: data
                )

                resume.markAssetCompleted(tag: releasePlan.release.tagName, assetName: asset.name)
                try ReleaseMirrorResumeStore.saveResume(
                    resume,
                    repoID: plan.id,
                    targetID: destination.id
                )

                let completed = Array(resume.completedAssets(for: releasePlan.release.tagName))
                let state: ReleaseTagSyncState = completed.count >= releasePlan.release.assets.count
                    ? .synced
                    : .partial
                updateTagStatus(
                    &tagStatuses,
                    tagName: releasePlan.release.tagName,
                    state: state,
                    completed: completed,
                    totalAssets: releasePlan.release.assets.count,
                    error: nil
                )
                updatePersistedStatus(
                    mirrorID: plan.id,
                    destinationID: destination.id,
                    destinationURL: target.url,
                    tags: tagStatuses,
                    isSyncing: true,
                    lastError: nil
                )
            }
        }

        markAllSyncedWherePossible(&tagStatuses, source: sourceReleases, resume: resume)
        updatePersistedStatus(
            mirrorID: plan.id,
            destinationID: destination.id,
            destinationURL: target.url,
            tags: tagStatuses,
            isSyncing: false,
            lastError: lastError,
            lastSyncedAt: lastError == nil ? .now : nil
        )
        log("Release mirror finished.")
    }

    func loadStatus(plan: MirrorPlan) -> [ReleaseTargetMirrorStatus] {
        let stored = ReleaseMirrorResumeStore.loadStatus(repoID: plan.id)
        if stored.isEmpty {
            return plan.enabledDestinations.compactMap { destination in
                guard case .git(let endpoint) = destination.location else { return nil }
                return ReleaseTargetMirrorStatus(targetID: destination.id, targetURL: endpoint.url)
            }
        }
        return stored
    }

    // MARK: - Private

    private func downloadAsset(from url: URL, auth: AuthConfig, remoteURL: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("GitRelay", forHTTPHeaderField: "User-Agent")
        if let provider = GitRemoteHost.inferredProvider(fromRemoteURL: remoteURL),
           let token = ReleaseProviderAuth.resolveToken(for: auth, provider: provider) {
            switch provider {
            case .github:
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .gitlab:
                req.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            case .gitea:
                req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ProviderAPIError.http(status: status, message: "download failed")
        }
        return data
    }

    private func buildInitialTagStatuses(source: [ReleaseInfo]) -> [ReleaseTagStatus] {
        source.map {
            ReleaseTagStatus(
                tagName: $0.tagName,
                state: .pending,
                completedAssetNames: [],
                totalAssets: $0.assets.count,
                error: nil
            )
        }
    }

    private func updateTagStatus(
        _ tags: inout [ReleaseTagStatus],
        tagName: String,
        state: ReleaseTagSyncState,
        completed: [String],
        totalAssets: Int,
        error: String?
    ) {
        if let index = tags.firstIndex(where: { $0.tagName == tagName }) {
            tags[index].state = state
            tags[index].completedAssetNames = completed
            tags[index].totalAssets = totalAssets
            tags[index].error = error
        } else {
            tags.append(
                ReleaseTagStatus(
                    tagName: tagName,
                    state: state,
                    completedAssetNames: completed,
                    totalAssets: totalAssets,
                    error: error
                )
            )
        }
    }

    private func markAllSynced(_ tags: inout [ReleaseTagStatus]) {
        for index in tags.indices {
            tags[index].state = .synced
            tags[index].completedAssetNames = []
            tags[index].error = nil
        }
    }

    private func markAllSyncedWherePossible(
        _ tags: inout [ReleaseTagStatus],
        source: [ReleaseInfo],
        resume: ReleaseMirrorResumeState
    ) {
        for index in tags.indices {
            let tagName = tags[index].tagName
            guard let release = source.first(where: { $0.tagName == tagName }) else { continue }
            let completed = resume.completedAssets(for: tagName)
            if completed.count >= release.assets.count || release.assets.isEmpty {
                tags[index].state = .synced
                tags[index].completedAssetNames = release.assets.map(\.name)
            }
        }
    }

    private func updatePersistedStatus(
        mirrorID: UUID,
        destinationID: UUID,
        destinationURL: String,
        tags: [ReleaseTagStatus],
        isSyncing: Bool,
        lastError: String?,
        lastSyncedAt: Date? = nil
    ) {
        var statuses = ReleaseMirrorResumeStore.loadStatus(repoID: mirrorID)
        let entry = ReleaseTargetMirrorStatus(
            targetID: destinationID,
            targetURL: destinationURL,
            lastSyncedAt: lastSyncedAt
                ?? statuses.first(where: { $0.targetID == destinationID })?.lastSyncedAt,
            lastError: lastError,
            tags: tags,
            isSyncing: isSyncing
        )
        if let index = statuses.firstIndex(where: { $0.targetID == destinationID }) {
            statuses[index] = entry
        } else {
            statuses.append(entry)
        }
        try? ReleaseMirrorResumeStore.saveStatus(statuses, repoID: mirrorID)
    }
}

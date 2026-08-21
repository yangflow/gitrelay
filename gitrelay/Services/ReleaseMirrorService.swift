import Foundation

@MainActor
final class ReleaseMirrorService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func mirrorReleases(
        repo: RepoConfig,
        target: MirrorTarget,
        log: @escaping (String) -> Void
    ) async throws {
        guard repo.mirrorReleases else { return }
        guard target.kind == .gitRemote else { return }

        guard let srcPath = GitRemoteRepoPath.parse(from: repo.srcURL),
              let dstPath = GitRemoteRepoPath.parse(from: target.url) else {
            throw ReleaseMirrorError.invalidRemoteURL(repo.srcURL)
        }

        let srcClient = try ReleaseProviderClientFactory.makeClient(
            remoteURL: repo.srcURL,
            auth: repo.srcAuth,
            side: "source"
        )
        let dstClient = try ReleaseProviderClientFactory.makeClient(
            remoteURL: target.url,
            auth: target.auth,
            side: "target"
        )

        var resume = ReleaseMirrorResumeStore.loadResume(repoID: repo.id, targetID: target.id)
        updatePersistedStatus(
            repo: repo,
            target: target,
            tags: [],
            isSyncing: true,
            lastError: nil
        )

        log("Listing source releases…")
        let sourceReleases = try await srcClient.listReleases(ownerRepo: srcPath.ownerRepoPath)
        var tagStatuses = buildInitialTagStatuses(source: sourceReleases)
        log("Listing target releases…")
        let targetReleases = try await dstClient.listReleases(ownerRepo: dstPath.ownerRepoPath)
        updatePersistedStatus(repo: repo, target: target, tags: tagStatuses, isSyncing: true, lastError: nil)
        let plans = ReleaseMirrorDiff.plans(source: sourceReleases, target: targetReleases, resume: resume)

        if plans.isEmpty {
            log("All releases and assets are already mirrored.")
            markAllSynced(&tagStatuses)
            updatePersistedStatus(
                repo: repo,
                target: target,
                tags: tagStatuses,
                isSyncing: false,
                lastError: nil,
                lastSyncedAt: .now
            )
            return
        }

        log("Mirroring \(plans.count) release(s) with pending assets…")
        let lastError: String? = nil

        for plan in plans {
            updateTagStatus(
                &tagStatuses,
                tagName: plan.release.tagName,
                state: .syncing,
                completed: Array(resume.completedAssets(for: plan.release.tagName)),
                totalAssets: plan.release.assets.count,
                error: nil
            )
            updatePersistedStatus(repo: repo, target: target, tags: tagStatuses, isSyncing: true, lastError: nil)

            var uploadURL: String?
            let targetHasRelease = targetReleases.contains(where: { $0.tagName == plan.release.tagName })
            if plan.needsCreate || !targetHasRelease {
                log("Creating release \(plan.release.tagName) on target…")
                uploadURL = try await dstClient.createRelease(
                    ownerRepo: dstPath.ownerRepoPath,
                    release: plan.release
                )
            } else if dstClient.provider == .github {
                uploadURL = try await dstClient.fetchReleaseUploadURL(
                    ownerRepo: dstPath.ownerRepoPath,
                    tagName: plan.release.tagName
                )
            }

            for assetName in plan.missingAssetNames {
                guard let asset = plan.release.assets.first(where: { $0.name == assetName }) else { continue }
                log("Downloading asset \(asset.name) (\(asset.size.map(String.init) ?? "?") bytes)…")
                let data = try await downloadAsset(from: asset.downloadURL, auth: repo.srcAuth, remoteURL: repo.srcURL)

                log("Uploading asset \(asset.name) to target…")
                try await dstClient.uploadAsset(
                    ownerRepo: dstPath.ownerRepoPath,
                    tagName: plan.release.tagName,
                    releaseUploadURL: uploadURL,
                    asset: asset,
                    data: data
                )

                resume.markAssetCompleted(tag: plan.release.tagName, assetName: asset.name)
                try ReleaseMirrorResumeStore.saveResume(resume, repoID: repo.id, targetID: target.id)

                let completed = Array(resume.completedAssets(for: plan.release.tagName))
                let state: ReleaseTagSyncState = completed.count >= plan.release.assets.count ? .synced : .partial
                updateTagStatus(
                    &tagStatuses,
                    tagName: plan.release.tagName,
                    state: state,
                    completed: completed,
                    totalAssets: plan.release.assets.count,
                    error: nil
                )
                updatePersistedStatus(repo: repo, target: target, tags: tagStatuses, isSyncing: true, lastError: nil)
            }
        }

        markAllSyncedWherePossible(&tagStatuses, source: sourceReleases, resume: resume)
        updatePersistedStatus(
            repo: repo,
            target: target,
            tags: tagStatuses,
            isSyncing: false,
            lastError: lastError,
            lastSyncedAt: lastError == nil ? .now : nil
        )
        log("Release mirror finished.")
    }

    func loadStatus(repo: RepoConfig) -> [ReleaseTargetMirrorStatus] {
        let stored = ReleaseMirrorResumeStore.loadStatus(repoID: repo.id)
        if stored.isEmpty {
            return repo.enabledTargets
                .filter { $0.kind == .gitRemote }
                .map {
                ReleaseTargetMirrorStatus(targetID: $0.id, targetURL: $0.url)
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
        repo: RepoConfig,
        target: MirrorTarget,
        tags: [ReleaseTagStatus],
        isSyncing: Bool,
        lastError: String?,
        lastSyncedAt: Date? = nil
    ) {
        var statuses = ReleaseMirrorResumeStore.loadStatus(repoID: repo.id)
        let entry = ReleaseTargetMirrorStatus(
            targetID: target.id,
            targetURL: target.url,
            lastSyncedAt: lastSyncedAt ?? statuses.first(where: { $0.targetID == target.id })?.lastSyncedAt,
            lastError: lastError,
            tags: tags,
            isSyncing: isSyncing
        )
        if let index = statuses.firstIndex(where: { $0.targetID == target.id }) {
            statuses[index] = entry
        } else {
            statuses.append(entry)
        }
        try? ReleaseMirrorResumeStore.saveStatus(statuses, repoID: repo.id)
    }
}

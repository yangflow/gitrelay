import SwiftUI

struct RepoIdleRowView: View {
    let status: SyncStatus
    let lastSyncedAt: Date?
    let lastVerifiedAt: Date?
    let nextFireDate: Date?
    let isVerifying: Bool
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                RepoStatusLabel(status: status)
                if let lastSyncedAt {
                    Text("Last synced: \(lastSyncedAt.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastVerifiedAt {
                    Text("Last verified: \(lastVerifiedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let nextFireDate {
                    Text("Next sync: \(nextFireDate.formatted(.relative(presentation: .named))) (the app must remain running)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Button("Verify Now", action: onVerifyNow)
                    .buttonStyle(.bordered)
                    .disabled(isVerifying || status == .syncing)
                Button("Sync Now", action: onSyncNow)
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifying || status == .syncing)
            }
        }
    }
}

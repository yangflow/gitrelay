import SwiftUI
import AppKit

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("GitRelay")
                .font(.title.weight(.bold))
                .padding(.top, 12)

            Text("Version \(version) (\(build))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .textSelection(.enabled)

            Spacer().frame(height: 20)

            VStack(spacing: 6) {
                Text("© 2026 yangflow")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(height: 16)

            HStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/yangflow/gitrelay")!)
                } label: {
                    Label("GitHub", systemImage: "link")
                }

                Button {
                    UpdaterService.shared.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderless)

            Spacer().frame(height: 24)
        }
        .frame(width: 280)
        .fixedSize()
    }
}

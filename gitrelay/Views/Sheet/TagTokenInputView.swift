import SwiftUI

struct TagTokenInputView: View {
    @Binding var tags: [String]
    let suggestions: [String]

    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    private var filteredSuggestions: [String] {
        RepoTagGrouping.matchingSuggestions(
            prefix: draft,
            existing: suggestions,
            selected: tags
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !tags.isEmpty {
                FlowLayout(spacing: DesignTokens.Spacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }

            TextField("Enter a tag and press Return to add it", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit { commitDraft() }

            if isFieldFocused, !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSuggestions.prefix(8), id: \.self) { suggestion in
                        Button {
                            addTag(suggestion)
                        } label: {
                            HStack {
                                Image(systemName: "tag")
                                    .foregroundStyle(.secondary)
                                Text(suggestion)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .padding(.horizontal, DesignTokens.Spacing.sm)
                    }
                }
                .background(DesignTokens.Surface.suggestionFill, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.control, style: .continuous))
            }

            Text("Separate multiple tags with commas or Return. Existing tags are suggested as you type.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: draft) { _, newValue in
            if newValue.contains(",") {
                let parts = newValue.split(separator: ",", omittingEmptySubsequences: false)
                for part in parts.dropLast() {
                    addTag(String(part))
                }
                draft = String(parts.last ?? "")
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Text(tag)
                .font(.caption)
            Button {
                removeTag(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .help("Remove Tag")
        }
        .padding(.horizontal, DesignTokens.Spacing.chipHorizontal)
        .padding(.vertical, DesignTokens.Spacing.chipVertical)
        .background(DesignTokens.Surface.chipFill, in: Capsule())
    }

    private func commitDraft() {
        addTag(draft)
        draft = ""
    }

    private func addTag(_ raw: String) {
        guard let normalized = RepoTagGrouping.normalizeTag(raw) else { return }
        guard !tags.contains(normalized) else { return }
        tags.append(normalized)
        draft = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

/// Simple wrapping layout for tag chips on macOS 14.
private struct FlowLayout: Layout {
    var spacing: CGFloat = DesignTokens.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

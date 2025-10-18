// ShareOverlay.swift
// Provides a floating Share/Copy button with a full share sheet and rendering helpers.

import SwiftUI
import UIKit

@MainActor
struct ShareOverlayButton: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var isPresentingShareSheet = false
    @State private var appeared = false

    var body: some View {
        ZStack { Color.clear }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isPresentingShareSheet = true
                }) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share or copy WorthIt summary")
                .padding(.trailing, 22)
                .padding(.bottom, 12)
                .opacity(isPresentingShareSheet ? 0 : (appeared ? 1 : 0))
                .offset(y: appeared ? 0 : 10)
                .scaleEffect(isPresentingShareSheet ? 0.9 : 1)
                .allowsHitTesting(!isPresentingShareSheet)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isPresentingShareSheet)
                .animation(.interpolatingSpring(stiffness: 160, damping: 18), value: appeared)
                .onAppear { appeared = true }
                .sheet(isPresented: $isPresentingShareSheet) {
                    ShareExportSheet()
                        .environmentObject(viewModel)
                        .presentationDetents([.fraction(0.5), .large])
                        .presentationDragIndicator(.visible)
                }
            }
    }
}

private struct ShareSheetSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Font.headlineBold)
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
            VStack(spacing: 14) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShareSheetRow: View {
    let icon: String
    let title: String
    let detail: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.sectionBackground.opacity(0.75))
                        .overlay(
                            Circle().stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        .frame(width: 46, height: 46)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.Color.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.Font.subheadlineBold)
                        .foregroundColor(.white)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                }

                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.7))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.Color.accent.opacity(isEnabled ? 0.25 : 0.1), lineWidth: 1)
                    .shadow(color: Theme.Color.accent.opacity(0.15), radius: 6)
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityHint(detail ?? "")
    }
}

private struct SharePreviewCard: View {
    let title: String
    let score: Int?
    let sections: [ShareComposer.Section]
    let isPlaceholder: Bool
    let onCollapse: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                SharePreviewBadge()

                VStack(alignment: .leading, spacing: 6) {
                    Text("WorthIt")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)

                    Text(title)
                        .font(Theme.Font.headlineBold)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 12) {
                    if let onCollapse {
                        Button(action: onCollapse) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.Color.secondaryText)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.Color.sectionBackground.opacity(0.6))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse recap preview")
                    }

                    if let score {
                        ShareScorePill(score: score)
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            if isPlaceholder {
                Text("Analyze a video to unlock a polished WorthIt recap ready to share.")
                    .font(Theme.Font.body)
                    .foregroundColor(Theme.Color.secondaryText)
                    .lineSpacing(4)
            } else if sections.isEmpty {
                Text("No sections selected yet. Use “Choose sections” to add content.")
                    .font(Theme.Font.body)
                    .foregroundColor(Theme.Color.secondaryText)
                    .lineSpacing(4)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        SharePreviewSectionView(section: section)
                        if index != sections.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.04))
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.Color.accent.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 22, y: 18)
    }
}

private struct SharePreviewSectionView: View {
    let section: ShareComposer.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let headline = section.headline {
                Text(headline)
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    SharePreviewRowView(row: row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SharePreviewRowView: View {
    let row: ShareComposer.Row

    var body: some View {
        switch row.kind {
        case .bullet:
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 6, height: 6)
                    .padding(.top, 8)

                Text(row.text)
                    .font(Theme.Font.body)
                    .foregroundColor(.white)
                    .lineSpacing(4)
            }
        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Text("“")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.Color.accent)
                    .padding(.top, 2)

                Text("\(row.text)\u{201D}")
                    .font(Theme.Font.body)
                    .foregroundColor(.white.opacity(0.92))
                    .italic()
                    .lineSpacing(4)
            }
        case .link:
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Color.accent)
                Text(row.text)
                    .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.accent.opacity(0.9))
                    .underline()
                    .lineLimit(1)
            }
        case .paragraph:
            Text(row.text)
                .font(Theme.Font.body)
                .foregroundColor(.white)
                .lineSpacing(4)
        }
    }
}

private struct SharePreviewContainer: View {
    let title: String
    let score: Int?
    let sections: [ShareComposer.Section]
    let isPlaceholder: Bool
    @Binding var isExpanded: Bool
    let onExpand: () -> Void
    let onCollapse: () -> Void

    private var hasContent: Bool { !sections.isEmpty && !isPlaceholder }

    private var collapsedHeadline: String {
        if isPlaceholder { return "Recap preview" }
        return sections.first?.headline ?? "Recap preview"
    }

    private var collapsedSnippet: String {
        if isPlaceholder { return "Analyze a video to unlock the recap preview." }

        let flattened = sections
            .flatMap { $0.rows }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty else {
            return "Preview the recap before you share it."
        }

        let minCharacters = 100
        let maxCharacters = 220

        guard flattened.count > maxCharacters else { return flattened }

        var shortened = String(flattened.prefix(maxCharacters))

        if let lastSpace = shortened.lastIndex(of: " "),
           shortened.distance(from: shortened.startIndex, to: lastSpace) >= minCharacters {
            shortened = String(shortened[..<lastSpace])
        }

        if shortened.count < minCharacters {
            shortened = String(flattened.prefix(minCharacters))
        }

        return shortened.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isExpanded {
                SharePreviewCard(
                    title: title,
                    score: score,
                    sections: sections,
                    isPlaceholder: isPlaceholder,
                    onCollapse: hasContent ? onCollapse : nil
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                SharePreviewCollapsedPrompt(
                    headline: collapsedHeadline,
                    snippet: collapsedSnippet,
                    isDisabled: !hasContent,
                    onTap: hasContent ? onExpand : nil
                )
            }
        }
    }
}

private struct SharePreviewCollapsedPrompt: View {
    let headline: String
    let snippet: String
    let isDisabled: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        let content = HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.7))
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.Color.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(.white)
                Text(snippet)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.Color.secondaryText.opacity(isDisabled ? 0.3 : 0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.Color.accent.opacity(0.18), lineWidth: 1)
                )
        )
        .opacity(isDisabled ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headline)
        .accessibilityValue(snippet)
        .accessibilityHint(isDisabled ? "Analyze a video to unlock the preview" : "Double-tap to open the recap preview")

        if let onTap, !isDisabled {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

private struct SharePreviewBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Gradient.appBluePurple)
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 48, height: 48)
        .shadow(color: Theme.Color.accent.opacity(0.32), radius: 10, y: 6)
    }
}

private struct ShareScorePill: View {
    let score: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Worth-It score")
                .font(Theme.Font.caption)
                .foregroundColor(.white.opacity(0.7))

            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("\(score)")
                    .font(Theme.Font.subheadlineBold)
            }
            .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Gradient.appBluePurple)
        )
        .shadow(color: Theme.Color.accent.opacity(0.25), radius: 12, y: 8)
    }
}

private struct SharePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Gradient.appBluePurple)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundColor(.white)
            .shadow(color: Theme.Color.accent.opacity(configuration.isPressed ? 0.18 : 0.32),
                    radius: configuration.isPressed ? 8 : 16,
                    y: configuration.isPressed ? 4 : 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct ShareSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
            )
            .foregroundColor(Theme.Color.primaryText)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.18 : 0.25),
                    radius: configuration.isPressed ? 6 : 12,
                    y: configuration.isPressed ? 3 : 7)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private struct ShareTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.Color.secondaryText.opacity(0.35), lineWidth: 1)
            )
            .foregroundColor(Theme.Color.secondaryText)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.12 : 0.18),
                    radius: configuration.isPressed ? 4 : 8,
                    y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

private struct ShareFineTuneToggleList: View {
    @Binding var selection: ShareBuilderSelection
    let availability: ShareBuilderAvailability

    var body: some View {
        VStack(spacing: 12) {
            ShareBuilderToggleRow(
                icon: "star.square.fill",
                title: "Title & Worth-It score",
                detail: availability.hasScore ? "Headline with the Worth-It score" : "Include the headline only",
                isOn: $selection.includeTitleAndScore,
                enabled: true
            )

            ShareBuilderToggleRow(
                icon: "text.alignleft",
                title: "Summary paragraph",
                detail: "Concise description of the video",
                isOn: $selection.includeSummary,
                enabled: availability.hasSummary
            )

            ShareBuilderToggleRow(
                icon: "list.bullet.rectangle.fill",
                title: "Top takeaways",
                detail: "Up to three quick highlights",
                isOn: $selection.includeTakeaways,
                enabled: availability.hasTakeaways
            )

            ShareBuilderToggleRow(
                icon: "quote.bubble.fill",
                title: "Gems of wisdom",
                detail: "Memorable viewer quotes",
                isOn: $selection.includeGems,
                enabled: availability.hasGems
            )

            ShareBuilderToggleRow(
                icon: "link",
                title: "Video link",
                detail: "Direct link back to the YouTube video",
                isOn: $selection.includeYouTubeLink,
                enabled: availability.hasLink
            )

            ShareBuilderToggleRow(
                icon: "app.gift.fill",
                title: "WorthIt app link",
                detail: "Invite friends to the app",
                isOn: $selection.includeAppLink,
                enabled: true
            )

        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.Color.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct CustomizeContentSheet: View {
    @Binding var isPresented: Bool
    @Binding var builderSelection: ShareBuilderSelection
    let availability: ShareBuilderAvailability
    let onShare: () -> Void
    let onCopy: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ScrollView {
                    ShareFineTuneToggleList(selection: $builderSelection, availability: availability)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                }
                .scrollIndicators(.hidden)

                VStack(spacing: 12) {
                    Button(action: shareAndClose) {
                        Label("Share recap", systemImage: "paperplane")
                            .font(Theme.Font.subheadlineBold)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShareBuilderActionButtonStyle(tint: Theme.Color.accent.opacity(0.9), border: Theme.Color.accent.opacity(0.4), foreground: .black))

                    Button(action: copyAndClose) {
                        Label("Copy recap", systemImage: "doc.on.doc")
                            .font(Theme.Font.subheadlineBold)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShareBuilderActionButtonStyle(tint: Theme.Color.sectionBackground.opacity(0.95), border: Theme.Color.accent.opacity(0.3)))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Theme.Color.darkBackground.ignoresSafeArea())
            .toolbarBackground(Theme.Color.darkBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle("Customize recap")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { closeSheet() }
                        .tint(Theme.Color.secondaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func shareAndClose() {
        onShare()
        closeSheet()
    }

    private func copyAndClose() {
        onCopy()
        closeSheet()
    }

    private func closeSheet() {
        isPresented = false
        dismiss()
    }
}

private struct ShareBuilderSelection {
    var includeTitleAndScore: Bool = true
    var includeSummary: Bool = true
    var includeTakeaways: Bool = true
    var includeGems: Bool = false
    var includeYouTubeLink: Bool = true
    var includeAppLink: Bool = true

    mutating func clamp(to availability: ShareBuilderAvailability) {
        if !availability.hasSummary { includeSummary = false }
        if !availability.hasTakeaways { includeTakeaways = false }
        if !availability.hasGems { includeGems = false }
        if !availability.hasLink { includeYouTubeLink = false }
    }
}

extension ShareBuilderSelection: Equatable {}

private struct ShareBuilderAvailability: Equatable {
    let hasScore: Bool
    let hasSummary: Bool
    let hasTakeaways: Bool
    let hasGems: Bool
    let hasLink: Bool
}

private struct ShareBuilderActionButtonStyle: ButtonStyle {
    var tint: Color
    var border: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )
            )
            .foregroundColor(foreground)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ShareBuilderToggleRow: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    let enabled: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Font.subheadlineBold)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
            }
        }
        .toggleStyle(ShareChecklistToggleStyle(icon: icon))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

private struct ShareChecklistToggleStyle: ToggleStyle {
    let icon: String

    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.Color.accent)
                    .frame(width: 32, height: 32)

                configuration.label
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(configuration.isOn ? Theme.Color.accent : Theme.Color.secondaryText.opacity(0.8))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ShareFeedbackToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text(message)
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(.white)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Theme.Color.accent.opacity(0.25), radius: 16, y: 8)
        )
    }
}

@MainActor
private struct ShareExportSheet: View {
    @EnvironmentObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var presentingActivity = false
    @State private var activityItems: [Any] = []
    @State private var toastMessage: String?
    @State private var toastDismissTask: DispatchWorkItem?
    @State private var builderSelection = ShareBuilderSelection()
    @State private var hasInitializedBuilder = false
    @State private var showCustomizeSheet = false
    @State private var isPreviewExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Color.darkBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        SharePreviewContainer(
                            title: sharePreviewTitle,
                            score: sharePreviewScore,
                            sections: sharePreviewSections,
                            isPlaceholder: !hasSharableContent,
                            isExpanded: $isPreviewExpanded,
                            onExpand: { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { isPreviewExpanded = true } },
                            onCollapse: { withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { isPreviewExpanded = false } }
                        )

                        VStack(spacing: 12) {
                            Button(action: shareRecapQuickly) {
                                Label("Share recap", systemImage: "square.and.arrow.up.fill")
                                    .font(Theme.Font.subheadlineBold)
                            }
                            .buttonStyle(SharePrimaryButtonStyle())
                            .disabled(!hasSharableContent)
                            .opacity(hasSharableContent ? 1 : 0.45)

                            Button(action: copyRecapQuickly) {
                                Label("Copy recap", systemImage: "doc.on.doc")
                                    .font(Theme.Font.subheadlineBold)
                            }
                            .buttonStyle(ShareSecondaryButtonStyle())
                            .disabled(!hasSharableContent)
                            .opacity(hasSharableContent ? 1 : 0.45)

                            Button(action: copyLink) {
                                Label("Copy YouTube link", systemImage: "link")
                                    .font(Theme.Font.subheadlineBold)
                            }
                            .buttonStyle(ShareTertiaryButtonStyle())
                            .disabled(!hasShareLink)
                            .opacity(hasShareLink ? 1 : 0.4)
                        }

                        if hasSharableContent {
                            ShareSheetSection(
                                title: "Customize recap",
                                subtitle: "Fine-tune the sections that get shared"
                            ) {
                                ShareSheetRow(
                                    icon: "slider.horizontal.3",
                                    title: "Choose sections",
                                    detail: "Pick summary, takeaways, gems, links",
                                    action: { showCustomizeSheet = true }
                                )

                                ShareSheetRow(
                                    icon: "arrow.counterclockwise",
                                    title: "Reset to defaults",
                                    detail: "Restore WorthIt’s recommended mix",
                                    action: resetToDefaultSelection
                                )
                                .disabled(currentSelection == defaultSelection(for: builderAvailability))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .scrollIndicators(.hidden)

                if let message = toastMessage {
                    ShareFeedbackToast(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 16)
                        .padding(.horizontal, 20)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .navigationTitle("Share recap")
            .toolbarBackground(Theme.Color.darkBackground.opacity(0.98), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                    .tint(Theme.Color.secondaryText)
                }
            }
            .sheet(isPresented: $presentingActivity) {
                if !activityItems.isEmpty { ActivityView(activityItems: activityItems) }
            }
        }
        .interactiveDismissDisabled(false)
        .onAppear { initializeBuilderIfNeeded() }
        .onChange(of: builderAvailability) { _ in enforceSelectionAvailability() }
        .onChange(of: hasSharableContent) { available in
            if !available { isPreviewExpanded = false }
        }
        .onChange(of: sharePreviewSections) { sections in
            if sections.isEmpty { isPreviewExpanded = false }
        }
        .onDisappear {
            toastDismissTask?.cancel()
        }
        .sheet(isPresented: $showCustomizeSheet) {
            CustomizeContentSheet(
                isPresented: $showCustomizeSheet,
                builderSelection: $builderSelection,
                availability: builderAvailability,
                onShare: shareCustomSelection,
                onCopy: copyCustomSelection
            )
        }
    }

    // MARK: - Actions
    private var hasSharableContent: Bool { viewModel.analysisResult != nil }

    private var hasShareLink: Bool { shareURL() != nil }

    private var currentSelection: ShareBuilderSelection {
        hasInitializedBuilder ? builderSelection : defaultSelection(for: builderAvailability)
    }

    private var sharePreviewTitle: String {
        ShareComposer.shareTitle(from: viewModel)
    }

    private var sharePreviewScore: Int? {
        viewModel.worthItScore.map { Int($0) }
    }

    private var shareSections: [ShareComposer.Section] {
        guard hasSharableContent else { return [] }
        return ShareComposer.composeSections(from: viewModel, selection: currentSelection)
    }

    private var sharePreviewSections: [ShareComposer.Section] {
        ShareComposer.previewSections(from: shareSections)
    }

    private var shareText: String? {
        guard hasSharableContent else { return nil }
        let text = ShareComposer.composeText(from: shareSections)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var builderAvailability: ShareBuilderAvailability {
        let analysis = viewModel.analysisResult
        let hasSummary = !(analysis?.longSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasTakeaways = !(analysis?.takeaways?.isEmpty ?? true)
        let hasGems = !(analysis?.gemsOfWisdom?.isEmpty ?? true)
        let hasScore = viewModel.worthItScore != nil
        let hasLink = shareURL() != nil
        return ShareBuilderAvailability(hasScore: hasScore,
                                        hasSummary: hasSummary,
                                        hasTakeaways: hasTakeaways,
                                        hasGems: hasGems,
                                        hasLink: hasLink)
    }

    private func shareRecapQuickly() {
        ensureBuilderInitialized()
        ensureSummaryIncluded()
        shareCustomSelection()
    }

    private func copyRecapQuickly() {
        ensureBuilderInitialized()
        ensureSummaryIncluded()
        copyCustomSelection()
    }

    private func resetToDefaultSelection() {
        ensureBuilderInitialized()
        let defaults = defaultSelection(for: builderAvailability)
        guard builderSelection != defaults else { return }
        builderSelection = defaults
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast("Defaults restored")
    }

    private func copyLink() {
        guard let link = shareURL()?.absoluteString, !link.isEmpty else { return }
        UIPasteboard.general.string = link
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast("YouTube link copied")
    }

    private func copyCustomSelection() {
        ensureBuilderInitialized()
        guard hasSharableContent, let text = shareText else { return }
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast("Recap copied")
    }

    private func shareCustomSelection() {
        ensureBuilderInitialized()
        guard hasSharableContent, let text = shareText else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentActivity(items: [text])
    }

    private func initializeBuilderIfNeeded() {
        guard !hasInitializedBuilder else { return }
        builderSelection = defaultSelection(for: builderAvailability)
        hasInitializedBuilder = true
    }

    private func ensureBuilderInitialized() {
        if !hasInitializedBuilder { initializeBuilderIfNeeded() }
    }

    private func enforceSelectionAvailability() {
        builderSelection.clamp(to: builderAvailability)
    }

    private func defaultSelection(for availability: ShareBuilderAvailability) -> ShareBuilderSelection {
        var selection = ShareBuilderSelection()
        selection.includeSummary = availability.hasSummary
        selection.includeTakeaways = availability.hasTakeaways
        selection.includeGems = availability.hasGems
        selection.includeYouTubeLink = availability.hasLink
        return selection
    }

    private func ensureSummaryIncluded() {
        if builderAvailability.hasSummary {
            builderSelection.includeSummary = true
        }
    }

    private func shareURL() -> URL? {
        if let vid = viewModel.currentVideoID { return URL(string: "https://youtu.be/\(vid)") }
        return nil
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            toastMessage = message
        }
        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                toastMessage = nil
            }
        }
        toastDismissTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func presentActivity(items: [Any]) {
        guard !items.isEmpty else { return }
        activityItems = items
        if presentingActivity {
            presentingActivity = false
        }
        DispatchQueue.main.async {
            activityItems = items
            presentingActivity = true
        }
    }
}
// MARK: - Helpers
private enum ShareComposer {
    static let appStoreURL = "https://apps.apple.com/us/app/worthit-ai-video-summaries/id6749246821"

    struct Section: Equatable {
        var headline: String?
        var rows: [Row]
    }

    struct Row: Equatable {
        enum Kind: Equatable {
            case paragraph
            case bullet
            case quote
            case link
        }

        var kind: Kind
        var text: String
    }

    @MainActor static func shareTitle(from vm: MainViewModel) -> String {
        let candidates: [String?] = [vm.analysisResult?.videoTitle, vm.currentVideoTitle]
        for candidate in candidates {
            if let title = sanitizedTitleCandidate(candidate) {
                return title
            }
        }
        return "WorthIt recap"
    }

    @MainActor static func composeFullRecap(from vm: MainViewModel) -> String {
        var selection = ShareBuilderSelection()
        let analysis = vm.analysisResult
        selection.includeSummary = !(analysis?.longSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        selection.includeTakeaways = !(analysis?.takeaways?.isEmpty ?? true)
        selection.includeGems = !(analysis?.gemsOfWisdom?.isEmpty ?? true)
        selection.includeYouTubeLink = vm.currentVideoID != nil
        return composeCustom(from: vm, selection: selection)
    }

    @MainActor static func composeCustom(from vm: MainViewModel, selection: ShareBuilderSelection) -> String {
        let sections = composeSections(from: vm, selection: selection)
        return composeText(from: sections)
    }

    @MainActor static func composeSections(from vm: MainViewModel, selection: ShareBuilderSelection) -> [Section] {
        var output: [Section] = []
        let analysis = vm.analysisResult
        let score = vm.worthItScore.map { Int($0) }
        let title = shareTitle(from: vm)

        if selection.includeTitleAndScore {
            var titleLine = title
            if let score {
                titleLine += " · Worth-It Score: \(score)/100"
            }
            output.append(Section(headline: nil, rows: [Row(kind: .paragraph, text: titleLine)]))
        }

        if selection.includeSummary,
           let summary = analysis?.longSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            output.append(Section(headline: "Summary", rows: [Row(kind: .paragraph, text: summary)]))
        }

        if selection.includeTakeaways,
           let rawTakeaways = analysis?.takeaways {
            let cleaned = rawTakeaways
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(3)
            if !cleaned.isEmpty {
                let rows = cleaned.map { Row(kind: .bullet, text: $0) }
                output.append(Section(headline: "Top takeaways", rows: rows))
            }
        }

        if selection.includeGems,
           let rawGems = analysis?.gemsOfWisdom {
            let cleaned = rawGems
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(2)
            if !cleaned.isEmpty {
                let rows = cleaned.map { Row(kind: .quote, text: $0) }
                output.append(Section(headline: "Gems of wisdom", rows: rows))
            }
        }

        if selection.includeYouTubeLink,
           let link = vm.currentVideoID.flatMap({ URL(string: "https://youtu.be/\($0)") }) {
            output.append(Section(headline: "Watch", rows: [Row(kind: .link, text: link.absoluteString)]))
        }

        if selection.includeAppLink {
            output.append(Section(headline: "Get WorthIt", rows: [Row(kind: .link, text: appStoreURL)]))
        }

        return output
            .map { section in
                let rows = section.rows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                return Section(headline: section.headline, rows: rows)
            }
            .filter { !$0.rows.isEmpty }
    }

    static func composeText(from sections: [Section]) -> String {
        sections
            .map { section in
                var lines: [String] = []
                if let headline = section.headline {
                    lines.append("**\(headline)**")
                }
                for row in section.rows {
                    switch row.kind {
                    case .paragraph:
                        lines.append(row.text)
                    case .bullet:
                        lines.append("• \(row.text)")
                    case .quote:
                        lines.append("• \"\(row.text)\"")
                    case .link:
                        lines.append(row.text)
                    }
                }
                return lines
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func previewSections(from sections: [Section]) -> [Section] {
        guard let first = sections.first else { return [] }
        if first.headline == nil {
            return Array(sections.dropFirst())
        }
        return sections
    }

    private static func sanitizedTitleCandidate(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        if isLikelyVideoID(trimmed) { return nil }
        return trimmed
    }

    private static func isLikelyVideoID(_ value: String) -> Bool {
        guard (10...16).contains(value.count) else { return false }
        if value.contains(where: { $0.isWhitespace }) { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let set = CharacterSet(charactersIn: value)
        guard allowed.isSuperset(of: set) else { return false }
        let hasDigit = value.contains(where: { $0.isNumber })
        let hasSpecial = value.contains("-") || value.contains("_")
        return hasDigit || hasSpecial
    }
}

// MARK: - Activity VC
private struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        vc.excludedActivityTypes = [.assignToContact, .addToReadingList, .print]
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

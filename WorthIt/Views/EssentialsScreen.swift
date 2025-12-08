import SwiftUI
import UIKit

struct EssentialsScreen: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var isLongSummaryExpanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let analysis = viewModel.analysisResult {
                    summarySection(analysis: analysis)

                    if let takeaways = analysis.takeaways, !takeaways.isEmpty {
                        takeawaysSection(takeaways: takeaways)
                    }

                    if let gems = analysis.gemsOfWisdom, !gems.isEmpty {
                        gemsSection(gems: gems)
                    }

                    let tips = (analysis.viewerTips ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let openQuestions = (analysis.openQuestions ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let hasSummary = !(analysis.CommentssentimentSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    let hasThemes = !(analysis.topThemes?.isEmpty ?? true)
                    let hasCommentContent = hasSummary || !tips.isEmpty || !openQuestions.isEmpty || hasThemes
                    if hasCommentContent {
                        CommunityNarrativeView(analysis: analysis)
                    }
                } else {
                    // Show proper app sections with clear loading messages
                    loadingSection()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .frame(maxWidth: 700)
        }
        .background(Theme.Color.darkBackground.ignoresSafeArea())
        .overlay(Theme.Gradient.subtleGlow.opacity(0.5).ignoresSafeArea())
        .enableSwipeBack()
        .onChange(of: viewModel.currentVideoID) { _ in
            // Reset the expansion when switching videos in the session
            isLongSummaryExpanded = false
        }
        .onAppear {
            Logger.shared.debug("EssentialsScreen appeared.", category: .ui)
            // Pin navigation to Essentials so background tasks don't kick us away
            viewModel.currentScreenOverride = .showingEssentials
        }
        .onDisappear { if viewModel.currentScreenOverride == .showingEssentials { viewModel.currentScreenOverride = nil } }
    }

    // Comments-only UI removed per product decision

    @ViewBuilder
    private func loadingPlaceholder(text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().tint(Theme.Color.accent)
                .scaleEffect(1.2)
            Text(text)
                .font(Theme.Font.headline)
                .foregroundColor(Theme.Color.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func summarySection(analysis: ContentAnalysis) -> some View {
        SectionView(title: "Summary", icon: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                if let longSummary = analysis.longSummary, !longSummary.isEmpty {
                    let parsedSummary = parseLongSummary(longSummary)
                    let narrativeSections = buildNarrativeSections(from: parsedSummary.narrative)
                    let isCollapsed = !isLongSummaryExpanded

                    ZStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 14) {
                            if !parsedSummary.highlights.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .center, spacing: 8) {
                                        Image(systemName: "sparkle")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(Theme.Color.accent)
                                            .accessibilityHidden(true)
                                        Text("Highlights")
                                            .font(Theme.Font.subheadlineBold)
                                            .foregroundColor(Theme.Color.primaryText)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(parsedSummary.highlights, id: \.self) { highlight in
                                            HStack(alignment: .top, spacing: 8) {
                                                Circle()
                                                    .fill(Theme.Color.accent)
                                                    .frame(width: 6, height: 6)
                                                    .offset(y: 6)
                                                    .accessibilityHidden(true)
                                                Text(highlight)
                                                    .font(Theme.Font.body)
                                                    .foregroundColor(Theme.Color.primaryText.opacity(0.95))
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Theme.Color.primaryText.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Theme.Color.primaryText.opacity(0.12), lineWidth: 1)
                                )
                            }

                            if !narrativeSections.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(narrativeSections) { section in
                                        VStack(alignment: .leading, spacing: 12) {
                                            if let title = section.title {
                                                Text(title)
                                                    .font(Theme.Font.subheadlineBold)
                                                    .foregroundColor(Theme.Color.primaryText)
                                                    .accessibilityAddTraits(.isHeader)
                                                    .padding(.bottom, 4)
                                            }

                                            if !section.paragraphs.isEmpty {
                                                VStack(alignment: .leading, spacing: 14) {
                                                    ForEach(section.paragraphs, id: \.self) { paragraph in
                                                        Text(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))
                                                            .font(Theme.Font.body)
                                                            .foregroundColor(Theme.Color.primaryText.opacity(0.95))
                                                            .lineSpacing(6)
                                                            .lineLimit(isLongSummaryExpanded ? nil : 3)
                                                            .fixedSize(horizontal: false, vertical: true)
                                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                                    }
                                                }
                                            }

                                            if !section.bullets.isEmpty {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    ForEach(section.bullets, id: \.self) { bullet in
                                                        HStack(alignment: .top, spacing: 8) {
                                                            Circle()
                                                                .fill(Theme.Color.accent.opacity(0.9))
                                                                .frame(width: 6, height: 6)
                                                                .offset(y: 6)
                                                                .accessibilityHidden(true)
                                                            Text(bullet)
                                                                .font(Theme.Font.body)
                                                                .foregroundColor(Theme.Color.primaryText.opacity(0.92))
                                                                .lineSpacing(3)
                                                                .lineLimit(isLongSummaryExpanded ? nil : 3)
                                                                .transition(.opacity.combined(with: .move(edge: .top)))
                                                        }
                                                    }
                                                }
                                                .padding(.leading, section.title == nil ? 0 : 2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .animation(.interactiveSpring(response: 0.45, dampingFraction: 0.88, blendDuration: 0.15), value: isLongSummaryExpanded)

                        if isCollapsed {
                            LinearGradient(
                                gradient: Gradient(colors: [Color.clear, Theme.Color.sectionBackground.opacity(0.95)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 80)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        }
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .copyContext(longSummary)

                    Button {
                        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.85, blendDuration: 0.12)) {
                            isLongSummaryExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(isCollapsed ? "Read more" : "Show less")
                                .font(Theme.Font.subheadlineBold)
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.92))
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // If neither is available, show a small placeholder
                    Text("Summary unavailable.")
                        .font(Theme.Font.body)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func loadingSection() -> some View {
        VStack(alignment: .leading, spacing: 28) {
            // Summary section with loading message
            SectionView(title: "Summary", icon: "doc.text.magnifyingglass") {
                VStack(alignment: .leading, spacing: 14) {
                    loadingPlaceholder(text: "Generating transcript summary…")
                    summarySkeleton()
                }
            }

            // Takeaways section with loading message
            SectionView(title: "Key Takeaways", icon: "key.horizontal.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    loadingPlaceholder(text: "Extracting key takeaways…")
                    takeawaysSkeleton()
                }
            }

            // Gems section with loading message
            SectionView(title: "Gems of Wisdom", icon: "lightbulb.max.fill") {
                VStack(alignment: .leading, spacing: 14) {
                    loadingPlaceholder(text: "Looking for standout quotes…")
                    gemsSkeleton()
                }
            }
        }
    }

    // MARK: - Skeletons
    @ViewBuilder
    private func bar(width: CGFloat, height: CGFloat = 12, opacity: Double = 0.5) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Theme.Color.primaryText.opacity(opacity))
            .frame(width: width, height: height)
    }

    @ViewBuilder
    private func summarySkeleton() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            bar(width: 260)
            bar(width: 280)
            bar(width: 220)
            bar(width: 180)
        }
        .redacted(reason: .placeholder)
        .modifier(Shimmer())
    }

    @ViewBuilder
    private func takeawaysSkeleton() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            bar(width: 220)
            bar(width: 240)
            bar(width: 200)
        }
        .redacted(reason: .placeholder)
        .modifier(Shimmer())
    }

    @ViewBuilder
    private func gemsSkeleton() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            bar(width: 200)
            bar(width: 180)
        }
        .redacted(reason: .placeholder)
        .modifier(Shimmer())
    }

    // MARK: - Shimmer Effect
    private struct Shimmer: ViewModifier {
        @State private var pos: CGFloat = -0.6
        func body(content: Content) -> some View {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                .white.opacity(0.0),
                                .white.opacity(0.22),
                                .white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: max(80, geo.size.width * 0.35))
                        .offset(x: pos * (geo.size.width + 120) - 60)
                        .blur(radius: 0.5)
                        .allowsHitTesting(false)
                    }
                    .mask(content)
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        pos = 1.6
                    }
                }
        }
    }

    @ViewBuilder
    private func takeawaysSection(takeaways: [String]) -> some View {
        SectionView(title: "Key Takeaways", icon: "key.horizontal.fill") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(takeaways, id: \.self) { takeaway in
                    Label(takeaway, systemImage: "checkmark.seal.fill")
                        .font(Theme.Font.body)
                        .foregroundColor(Theme.Color.primaryText)
                        .copyContext(takeaway)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func gemsSection(gems: [String]) -> some View {
        SectionView(title: "Gems of Wisdom", icon: "lightbulb.max.fill") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(gems, id: \.self) { gem in
                    Label("\"\(gem)\"", systemImage: "lightbulb.fill")
                        .font(Theme.Font.body.italic())
                        .foregroundColor(Theme.Color.primaryText)
                        .copyContext(gem)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

private func parseLongSummary(_ text: String) -> (highlights: [String], narrative: String) {
    var highlights: [String] = []
    var narrativeLines: [String] = []

    // Normalize escaped/newline variants before splitting
    let normalized = text
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")

    let lines = normalized.components(separatedBy: .newlines)
    var index = 0

    func trimmedLine(at idx: Int) -> String {
        lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Parse optional "Highlights:" header + bullet list
    if !lines.isEmpty, trimmedLine(at: 0).lowercased() == "highlights:" {
        index = 1
        while index < lines.count {
            let line = trimmedLine(at: index)
            if line.isEmpty { break }

            // Handle both "• " and "•" formats, plus other bullet types
            if line.hasPrefix("• ") || line.hasPrefix("- ") || line.hasPrefix("∙ ") || line.hasPrefix("* ") {
                // Bullet with space - drop 2 characters
                let bulletBody = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !bulletBody.isEmpty { highlights.append(String(bulletBody)) }
                index += 1
            } else if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("∙") || line.hasPrefix("*") {
                // Bullet without space - drop 1 character and trim
                let bulletBody = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !bulletBody.isEmpty { highlights.append(String(bulletBody)) }
                index += 1
            } else {
                // Tolerate bullets without a marker
                highlights.append(line)
                index += 1
            }
        }

        // Skip blank separator lines
        while index < lines.count, trimmedLine(at: index).isEmpty {
            index += 1
        }

        if index < lines.count {
            narrativeLines = Array(lines[index...])
        }
    } else {
        narrativeLines = lines
    }

    // Build narrative text
    var narrative = narrativeLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

    // Clean up instruction text that might be included
    narrative = narrative
        .replacingOccurrences(of: "Two lines of natural prose:", with: "")
        .replacingOccurrences(of: "Then 2–4 natural sentences, each on its own line", with: "")
        .replacingOccurrences(of: "Do not write the literal characters \"\\n\" or \"/n\"; just separate lines", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // If the narrative is one long line, add breaks after sentence enders to create paragraphs
    if !narrative.contains("\n") {
        // Split into sentences and group them into paragraphs
        let sentences = narrative
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }

        // Group sentences into paragraphs (2-3 sentences each)
        var paragraphs: [String] = []
        var currentParagraph = ""
        var sentenceCount = 0

        for sentence in sentences {
            if sentenceCount > 0 {
                currentParagraph += " "
            }
            currentParagraph += sentence
            sentenceCount += 1

            // Create a new paragraph after 2-3 sentences
            if sentenceCount >= 2 && (currentParagraph.count > 200 || sentenceCount >= 3) {
                paragraphs.append(currentParagraph)
                currentParagraph = ""
                sentenceCount = 0
            }
        }

        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph)
        }

        narrative = paragraphs.joined(separator: "\n\n")
    }

    // Collapse triple+ blank lines (just in case)
    while narrative.contains("\n\n\n") {
        narrative = narrative.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    return (highlights, narrative)
}
}

// MARK: - Narrative Formatting Helpers

private struct SummaryNarrativeSection: Identifiable, Equatable {
    let id = UUID()
    let title: String?
    let paragraphs: [String]
    let bullets: [String]
}

private func splitIntoParagraphs(_ text: String) -> [String] {
    var paragraphs: [String] = []
    var currentLines: [String] = []

    for rawLine in text.components(separatedBy: .newlines) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if !currentLines.isEmpty {
                let paragraph = currentLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraph.isEmpty {
                    paragraphs.append(paragraph)
                }
                currentLines.removeAll()
            }
        } else {
            currentLines.append(trimmed)
        }
    }

    if !currentLines.isEmpty {
        let paragraph = currentLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !paragraph.isEmpty {
            paragraphs.append(paragraph)
        }
    }

    return paragraphs
}

private func buildNarrativeSections(from narrative: String) -> [SummaryNarrativeSection] {
    let rawLines = narrative
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    var sections: [SummaryNarrativeSection] = []

    var currentTitle: String? = nil
    var currentParagraphLines: [String] = []
    var currentBullets: [String] = []

    func commitSection() {
        guard !currentParagraphLines.isEmpty || !currentBullets.isEmpty || currentTitle != nil else { return }
        let paragraphs = splitIntoParagraphs(currentParagraphLines.joined(separator: "\n"))

        sections.append(SummaryNarrativeSection(
            title: currentTitle,
            paragraphs: paragraphs,
            bullets: currentBullets
        ))
    }

    func resetSection() {
        currentTitle = nil
        currentParagraphLines = []
        currentBullets = []
    }

    for line in rawLines {
        if line.isEmpty {
            commitSection()
            resetSection()
            continue
        }

        let lowercased = line.lowercased()
        let isHeading = line.last == ":" && line.count <= 60
        if isHeading {
            commitSection()
            resetSection()
            currentTitle = String(line.dropLast())
            continue
        }

        // Handle both "• " and "•" formats, plus other bullet types
        if lowercased.hasPrefix("• ") || lowercased.hasPrefix("- ") || lowercased.hasPrefix("∙ ") {
            // Bullet with space - drop 2 characters
            let bulletText = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !bulletText.isEmpty { currentBullets.append(bulletText) }
            continue
        } else if lowercased.hasPrefix("•") || lowercased.hasPrefix("-") || lowercased.hasPrefix("∙") {
            // Bullet without space - drop 1 character and trim
            let bulletText = line.dropFirst().trimmingCharacters(in: .whitespaces)
            if !bulletText.isEmpty { currentBullets.append(bulletText) }
            continue
        }

        currentParagraphLines.append(line)
    }

    commitSection()

    if sections.isEmpty, !narrative.isEmpty {
        let cleaned = splitIntoParagraphs(narrative)
        return [SummaryNarrativeSection(title: nil, paragraphs: cleaned, bullets: [])]
    }

    return sections
}

// MARK: - Helper Views & Types

struct SectionView<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(Theme.Color.accent)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(Theme.Font.title3.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
            }
            .padding(.bottom, 4)

            content
        }
        .padding(16)
        .background(Theme.Color.sectionBackground)
        .cornerRadius(16)
        .shadow(color: Theme.Color.primaryText.opacity(0.12), radius: 5, y: 3)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Copy helper
private struct CopyContext: ViewModifier {
    let text: String
    @State private var showCopied: Bool = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    UIPasteboard.general.string = text
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .overlay(
                GeometryReader { geo in
                    Text("Copied")
                        .font(Theme.Font.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .position(x: geo.size.width / 2, y: -6)
                        .opacity(showCopied ? 1 : 0)
                        .allowsHitTesting(false)
                }
            )
    }
}

private extension View {
    func copyContext(_ text: String) -> some View {
        modifier(CopyContext(text: text))
    }
}

struct CommunityNarrativeView: View {
    let analysis: ContentAnalysis
    @State private var showAllThemes: Bool = false

    var body: some View {
        SectionView(title: "What Viewers Are Saying", icon: "quote.bubble.fill") {
            VStack(alignment: .leading, spacing: 20) {
                if let CommentssentimentSummary = analysis.CommentssentimentSummary, !CommentssentimentSummary.isEmpty {
                    Text(CommentssentimentSummary)
                        .font(Theme.Font.body)
                        .foregroundColor(Theme.Color.primaryText)
                        .lineSpacing(5)
                        .copyContext(CommentssentimentSummary)
                        .padding(.bottom, 6)
                }

                // Scope / trust context
                if let spamRatio = analysis.spamRatio {
                    CommunityHealthRow(spamRatio: spamRatio)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                let tips = (analysis.viewerTips ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let openQuestions = (analysis.openQuestions ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !tips.isEmpty {
                    ChipRow(title: "What viewers suggest", items: Array(tips.prefix(2)), style: .accent, icon: "lightbulb")
                }
                if !openQuestions.isEmpty {
                    ChipRow(title: "Open questions", items: Array(openQuestions.prefix(2)), style: .secondary, icon: "questionmark.circle")
                }

                if let themes = analysis.topThemes, !themes.isEmpty {
                    let hasMultipleStances = Set(themes.map { $0.sentiment.lowercased() }).count > 1
                    Text("Themes from comments")
                        .font(Theme.Font.subheadlineBold)
                        .foregroundColor(Theme.Color.secondaryText)
                        .padding(.top, 12)
                    let renderedThemes = showAllThemes ? themes : Array(themes.prefix(3))
                    VStack(spacing: 16) {
                        ForEach(renderedThemes, id: \.theme) { theme in
                            CommentThemeRow(theme: theme, showStance: hasMultipleStances)
                        }
                    }
                    if themes.count > 3 {
                        Button(action: { showAllThemes.toggle() }) {
                            HStack(spacing: 6) {
                                Text(showAllThemes ? "Show fewer themes" : "View more themes")
                                    .font(Theme.Font.captionBold)
                                Image(systemName: showAllThemes ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(Theme.Color.secondaryText)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                Capsule().fill(Theme.Color.sectionBackground.opacity(0.75))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Not enough distinct themes yet.")
                        .font(Theme.Font.body)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
        }
    }

    private struct CommunityHealthRow: View {
        let spamRatio: Double

        private var display: (text: String, color: Color, icon: String) {
            if spamRatio <= 0.1 { return ("Low spam", Theme.Color.success, "checkmark.shield.fill") }
            if spamRatio <= 0.25 { return ("Some spam present", Theme.Color.warning, "exclamationmark.triangle.fill") }
            return ("Spam-heavy - caution", Theme.Color.error, "xmark.shield.fill")
        }

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: display.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(display.color.opacity(0.9))
                Text(display.text)
                    .font(Theme.Font.captionBold)
                    .foregroundColor(display.color.opacity(0.9))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(display.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(display.color.opacity(0.16), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum ChipRowStyle {
        case accent
        case secondary
    }

    private struct ChipRow: View {
        let title: String
        let items: [String]
        let style: ChipRowStyle
        let icon: String

        private var tint: Color {
            switch style {
            case .accent: return Theme.Color.accent
            case .secondary: return Theme.Color.secondaryText
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(Theme.Color.secondaryText)
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 6) {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(tint)
                            Text(item)
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.Color.primaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(tint.opacity(0.08))
                        )
                        .overlay(
                            Capsule().stroke(tint.opacity(0.14), lineWidth: 1)
                        )
                        .copyContext(item)
                    }
                }
            }
        }
    }

}

// Elegant theme list row
private struct CommentThemeRow: View {
    let theme: CommentTheme
    let showStance: Bool

    private var sentimentInfo: (String, Color) {
        let s = theme.sentiment.lowercased()
        if s.contains("positive") { return ("hand.thumbsup.fill", Theme.Color.success) }
        if s.contains("negative") { return ("hand.thumbsdown.fill", Theme.Color.error) }
        if s.contains("mixed") { return ("circle.lefthalf.filled", Theme.Color.warning) }
        return ("circle", Theme.Color.secondaryText)
    }

    private var stanceTag: (String, Color) {
        let s = theme.sentiment.lowercased()
        if s.contains("positive") { return ("Praise", Theme.Color.success) }
        if s.contains("negative") { return ("Concern", Theme.Color.error) }
        if s.contains("mixed") { return ("Mixed", Theme.Color.warning) }
        return ("Neutral", Theme.Color.secondaryText)
    }

    @State private var showCopyConfirmation: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: sentimentInfo.0)
                .foregroundColor(sentimentInfo.1)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(theme.theme.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(Theme.Font.body.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
                HStack(spacing: 6) {
                    if showStance {
                        Text(stanceTag.0)
                            .font(Theme.Font.captionBold)
                            .foregroundColor(stanceTag.1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(stanceTag.1.opacity(0.1))
                            )
                            .overlay(
                                Capsule().stroke(stanceTag.1.opacity(0.16), lineWidth: 1)
                            )
                    }
                }
                if let example = theme.exampleComment, !example.isEmpty {
                    Text(example)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                        .onTapGesture {
                            UIPasteboard.general.string = example
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.easeInOut(duration: 0.2)) { showCopyConfirmation = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                withAnimation(.easeInOut(duration: 0.2)) { showCopyConfirmation = false }
                            }
                        }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.Color.accent.opacity(0.12), lineWidth: 1)
                )
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = theme.theme.replacingOccurrences(of: "_", with: " ")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.2)) { showCopyConfirmation = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeInOut(duration: 0.2)) { showCopyConfirmation = false }
                }
            } label: {
                Label("Copy Theme", systemImage: "doc.on.doc")
            }
            if let example = theme.exampleComment, !example.isEmpty {
                Button {
                    UIPasteboard.general.string = example
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.2)) { showCopyConfirmation = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeInOut(duration: 0.2)) { showCopyConfirmation = false }
                    }
                } label: {
                    Label("Copy Example", systemImage: "quote.bubble")
                }
            }
        }
        .overlay(
            GeometryReader { geo in
                Text("Copied")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .position(x: geo.size.width / 2, y: -6)
                    .opacity(showCopyConfirmation ? 1 : 0)
                    .allowsHitTesting(false)
            }
        )
    }
}

#if DEBUG
struct EssentialsScreen_Previews: PreviewProvider {
    static var previews: some View {
        let apiManager = APIManager()
        let cacheManager = CacheManager.shared
        let subscriptionManager = SubscriptionManager()
        let usageTracker = UsageTracker()
        let viewModelWithData = MainViewModel(
            apiManager: apiManager,
            cacheManager: cacheManager,
            subscriptionManager: subscriptionManager,
            usageTracker: usageTracker
        )
        viewModelWithData.analysisResult = ContentAnalysis(
            longSummary: "A detailed exploration into how artificial intelligence is revolutionizing art, music, and design.",
            takeaways: ["AI is evolving at an unprecedented pace.", "Ethical frameworks are vital.", "AI can augment human creativity."],
            gemsOfWisdom: ["The best way to predict the future is to invent it."],
            videoId: "preview123",
            videoTitle: "The Astonishing Rise of AI",
            videoDurationSeconds: 1200,
            videoThumbnailUrl: "",
            CommentssentimentSummary: "The community is generally excited and optimistic.",
            topThemes: [CommentTheme(theme: "Great Editing", sentiment: "Positive", sentimentScore: 0.9, exampleComment: "The editing was top-notch!")],
            spamRatio: 0.08,
            viewerTips: ["Watch at 1.25x to keep pacing tight."],
            openQuestions: ["Will there be a follow-up covering hands-on examples?"]
        )
        
        return EssentialsScreen()
            .environmentObject(viewModelWithData)
            .environmentObject(subscriptionManager)
            .preferredColorScheme(.dark)
    }
}
#endif

private func sentimentColor(for theme: CommentTheme) -> Color {
    switch theme.sentiment.lowercased() {
    case "positive": return .green
    case "negative": return .red
    case "mixed": return .yellow
    case "neutral": return .gray
    default: return .gray
    }
}

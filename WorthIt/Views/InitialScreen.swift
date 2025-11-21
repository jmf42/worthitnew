//
//  InitialScreen.swift
//  WorthIt
//
import SwiftUI

struct InitialScreen: View {
    @EnvironmentObject var viewModel: MainViewModel
    @State private var showScoreBreakdownSheet = false
    @State private var isGaugeAnimating: Bool = false
    @State private var isGaugeAnimationCompleted: Bool = false

    private func thumbnailSize(for availableWidth: CGFloat) -> CGSize {
        let horizontalInset: CGFloat = 32
        let width = min(max(availableWidth - horizontalInset, 160), 520)
        let resolvedWidth = min(width, availableWidth)
        return CGSize(width: resolvedWidth, height: resolvedWidth * (9.0 / 16.0))
    }

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let contentWidth = min(availableWidth, 640)
            let thumbSize = thumbnailSize(for: contentWidth)

            ZStack {
                // Backgrounds at the back
                Theme.Color.darkBackground.ignoresSafeArea()
                Theme.Gradient.subtleGlow
                    .opacity(0.3)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 1.0), value: viewModel.viewState)
                    .ignoresSafeArea()

                // Main content
                ScrollView {
                    VStack(spacing: 20) {
                        videoThumbnailView(size: thumbSize)
                            .padding(.top, 20)

                        Text("Worth-It Score")
                            .font(Theme.Font.title3.weight(.bold))
                            .foregroundColor(Theme.Color.primaryText)

                        scoreGaugeContainer

                        actionButtons
                            .padding(.top, 10)

                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: contentWidth)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 48)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .overlay(
            Group {
                if showScoreBreakdownSheet, let breakdown = viewModel.scoreBreakdownDetails {
                    ScoreBreakdownCardView(breakdown: breakdown, isPresented: $showScoreBreakdownSheet)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(100)
                }
            }
        )
        .onAppear {
            // Initialize gauge animation state without triggering confetti
            if viewModel.analysisResult != nil {
                isGaugeAnimationCompleted = true
            } else {
                isGaugeAnimationCompleted = false
            }
        }
        .onChange(of: viewModel.shouldPresentScoreBreakdown) { shouldPresent in
            if shouldPresent, viewModel.scoreBreakdownDetails != nil {
                showScoreBreakdownSheet = true
            }
            viewModel.consumeScoreBreakdownRequest()
        }
    }

    @ViewBuilder
    private func videoPlaceholder(icon: String, text: String, size: CGSize, isLoading: Bool = false) -> some View {
        ZStack {
            Theme.Color.sectionBackground
            VStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(Theme.Color.accent)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 50))
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.7))
                }
                Text(text)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 5)
            }
        }
        .frame(width: size.width, height: size.height)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Color.accent.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func videoThumbnailView(size: CGSize) -> some View {
        // High-quality by default with graceful fallback to prior working URL
        if let urls = buildThumbnailURLFallbackChain(), !urls.isEmpty {
            FallbackAsyncThumbnail(urls: urls,
                                   placeholder: { videoPlaceholder(icon: "film.fill", text: "Loading thumbnail...", size: size, isLoading: true) },
                                   content: { image in
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.6
                            )
                    )
                    .shadow(color: .white.opacity(0.05), radius: 5, x: 0, y: 3)
            },
                                   failure: {
                // Final failure: show a simple fallback icon card
                fallbackThumbnail(Image(systemName: "video.slash.fill"), size: size)
            })
        } else if let title = viewModel.currentVideoTitle, !title.isEmpty {
            videoPlaceholder(icon: "film.fill", text: title, size: size)
        } else {
            videoPlaceholder(icon: "questionmark.video.fill", text: "Video Information", size: size)
        }
    }

    // Build a best->worst list of thumbnail URLs using current state
    private func buildThumbnailURLFallbackChain() -> [URL]? {
        var list: [URL] = []
        if let vid = viewModel.currentVideoID {
            // Prefer higher quality first, then fall back to the prior working default (hqdefault)
            let candidates = [
                "https://i.ytimg.com/vi/\(vid)/maxresdefault.jpg",
                "https://i.ytimg.com/vi/\(vid)/hq720.jpg",
                "https://i.ytimg.com/vi/\(vid)/sddefault.jpg",
                "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg" // prior working default
            ]
            for c in candidates {
                if let u = URL(string: c), !list.contains(u) {
                    list.append(u)
                }
            }
        }
        // Include any provided backend thumbnail URL at the end as an additional candidate
        if let provided = viewModel.currentVideoThumbnailURL, !list.contains(provided) {
            list.append(provided)
        }
        return list.isEmpty ? nil : list
    }

    // A tiny helper view that tries multiple URLs in order until one succeeds
    private struct FallbackAsyncThumbnail<Placeholder: View, Content: View, Failure: View>: View {
        let urls: [URL]
        let placeholder: () -> Placeholder
        let content: (Image) -> Content
        let failure: () -> Failure

        @State private var index: Int = 0

        var body: some View {
            AsyncImage(url: urls[index]) { phase in
                switch phase {
                case .empty:
                    placeholder()
                case .success(let image):
                    content(image)
                case .failure:
                    if index + 1 < urls.count {
                        // Try next URL
                        Color.clear
                            .onAppear { index += 1 }
                    } else {
                        failure()
                    }
                @unknown default:
                    failure()
                }
            }
        }
    }

    @ViewBuilder
    private var scoreGaugeContainer: some View {
        ZStack {
            if let score = viewModel.worthItScore {
                ScoreGaugeView(
                    score: score,
                    isLoading: false,
                    showBreakdown: $showScoreBreakdownSheet,
                    isAnimationCompleted: $isGaugeAnimationCompleted
                )
                .onTapGesture {
                    if viewModel.scoreBreakdownDetails != nil {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showScoreBreakdownSheet.toggle()
                    }
                }
                .overlay(
                    Button(action: {
                        if viewModel.scoreBreakdownDetails != nil {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showScoreBreakdownSheet.toggle()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Show score breakdown")
                    .accessibilityHint("Opens detailed score metrics")
                    .offset(x: 18, y: -18),
                    alignment: .topTrailing
                )
            } else {
                ZStack {
                    ScoreGaugeView(
                        score: 0,
                        isLoading: true,
                        showBreakdown: .constant(false),
                        isAnimationCompleted: $isGaugeAnimationCompleted
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(isGaugeAnimating ? 360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: isGaugeAnimating)
                    .onAppear { isGaugeAnimating = true }

                    LoadingDotsView()
                        .font(.title2.weight(.semibold))
                }
            }
        }
        .frame(width: 100, height: 100)
        .padding(.vertical, 8)
    }

    private var actionButtons: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.Gradient.accent)
                    .blur(radius: 30)
                    .opacity(0.1)

                // Essentials becomes clickable as soon as score gauge appears (worthItScore),
                // or when full analysis is available.
                let canOpenEssentials = (viewModel.worthItScore != nil) || (viewModel.analysisResult != nil)
                StyledOptionButton(
                    title: "Essentials",
                    subtitle: "Get key points quickly",
                    icon: "sparkles",
                    iconColor: .white,
                    gradient: LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    isLoading: !canOpenEssentials,
                    action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.requestEssentials()
                    }
                )
                .disabled(!canOpenEssentials)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.orange, Color.green]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.6
                        )
                )
                .shadow(color: .white.opacity(0.05), radius: 5, x: 0, y: 3)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Theme.Gradient.accent)
                    .blur(radius: 30)
                    .opacity(0.1)

                StyledOptionButton(
                    title: "Ask Anything",
                    subtitle: "Interact with the content",
                    icon: "bubble.left.and.bubble.right.fill",
                    iconColor: .white,
                    gradient: LinearGradient(
                        gradient: Gradient(colors: [Color.pink, Color.teal]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    isLoading: viewModel.rawTranscript == nil,
                    action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.requestAskAnything()
                    }
                )
                .disabled(viewModel.rawTranscript == nil ||
                          viewModel.viewState == .processing ||
                          viewModel.rawTranscript?.isEmpty == true
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.6
                        )
                )
                .shadow(color: .white.opacity(0.05), radius: 5, x: 0, y: 3)
                .padding(.vertical, 4)
            }
        }
    }
}

extension InitialScreen {
    @ViewBuilder
    fileprivate func fallbackThumbnail(_ fallbackImage: Image, size: CGSize) -> some View {
        fallbackImage
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .foregroundColor(Theme.Color.secondaryText.opacity(0.7))
            .background(Theme.Color.sectionBackground)
            .clipped()
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.6
                    )
                    .shadow(color: .white.opacity(0.05), radius: 5, x: 0, y: 3)
            )
    }
}

struct ScoreBreakdownCardView: View {
    let breakdown: ScoreBreakdown
    @Binding var isPresented: Bool
    @State private var animateDepth: Double = 0
    @State private var animateSentiment: Double = 0
    
    private var scrollMaxHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.65, 520)
    }

    var body: some View {
        ZStack {
            // Dimmed, blurred background
            Theme.Color.darkBackground.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }
                .blur(radius: 0.5)

            // Floating card
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { withAnimation { isPresented = false } }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.Font.title3.weight(.bold))
                            .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                            .shadow(radius: 2)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        // Header + score badge
                        HStack(alignment: .lastTextBaseline) {
                            Text("Score Breakdown")
                            .font(Theme.Font.title3.weight(.bold))
                            .foregroundStyle(Theme.Gradient.appBluePurple)
                            Spacer()
                            Text("\(Int(breakdown.finalScore))%")
                                .font(Theme.Font.title3.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Theme.Color.sectionBackground.opacity(0.6))
                                        .overlay(Capsule().stroke(Theme.Color.accent.opacity(0.2), lineWidth: 1))
                                )
                                .foregroundStyle(Theme.Gradient.appBluePurple)
                                .lineLimit(1)
                                .minimumScaleFactor(0.95)
                        }
                        .padding(.top, 2)

                        // Subtle gradient divider under header for structure
                        Rectangle()
                            .fill(Theme.Gradient.appBluePurple.opacity(0.25))
                            .frame(height: 1)
                            .cornerRadius(0.5)

                        // Animated progress bars for each score
                        ScoreBreakdownBar(
                            label: "Content Depth",
                            value: breakdown.contentDepthScore,
                            icon: "doc.text.magnifyingglass",
                            color: Theme.Color.orange,
                            animatedValue: $animateDepth
                        )
                        
                        BreakdownReasonSection(
                            title: "Why this depth score",
                            positives: breakdown.contentHighlights,
                            negatives: breakdown.contentWatchouts,
                            positiveIcon: "plus.circle.fill",
                            negativeIcon: "exclamationmark.triangle.fill",
                            positiveColor: Theme.Color.orange,
                            negativeColor: Theme.Color.warning,
                            maxItems: 1
                        )
                        
                        if breakdown.hasComments {
                            ScoreBreakdownBar(
                                label: "Comment Sentiment",
                                value: breakdown.commentSentimentScore,
                                icon: "hand.thumbsup.circle.fill",
                                color: Theme.Color.success,
                                animatedValue: $animateSentiment
                            )
                            
                            if let spamRatio = breakdown.spamRatio, spamRatio >= 0.4 {
                                ScoreWarningCapsule(
                                    text: "Score tempered: \(Int(spamRatio * 100))% of comments look like spam or low-signal.",
                                    icon: "exclamationmark.triangle.fill"
                                )
                            }
                            
                            BreakdownReasonSection(
                                title: "What viewers are saying",
                                positives: breakdown.commentHighlights,
                                negatives: breakdown.commentWatchouts,
                                positiveIcon: "hand.thumbsup.fill",
                                negativeIcon: "xmark.octagon.fill",
                                positiveColor: Theme.Color.success,
                                negativeColor: Theme.Color.error,
                                maxItems: 1
                            )
                            
                            if let analyzed = breakdown.commentsAnalyzed, analyzed > 0 {
                                Text("Based on \(analyzed) recent comments")
                                    .font(Theme.Font.caption)
                                    .foregroundColor(Theme.Color.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            HStack {
                                Image(systemName: "text.bubble.fill")
                                    .foregroundColor(Theme.Color.secondaryText)
                                Text("No comments available for analysis.")
                                    .font(Theme.Font.subheadline)
                                    .foregroundColor(Theme.Color.secondaryText)
                            }
                            .padding(.vertical, 8)
                        }

                        // (Removed theme chips to ensure consistent look before/after cache)

                        // Clear conclusion phrased as a verdict
                        let worthItMessage: String = {
                            if breakdown.finalScore >= 80 {
                                return "Conclusion: Highly worth your time"
                            } else if breakdown.finalScore >= 60 {
                                return "Conclusion: Worth your time"
                            } else if breakdown.finalScore >= 40 {
                                return "Conclusion: Borderline — depends on your interest"
                            } else {
                                return "Conclusion: Not worth your time"
                            }
                        }()
                        HStack(spacing: 8) {
                            let iconName: String = {
                                if breakdown.finalScore >= 80 { return "checkmark.seal.fill" }
                                if breakdown.finalScore >= 60 { return "hand.thumbsup.fill" }
                                if breakdown.finalScore >= 40 { return "exclamationmark.triangle.fill" }
                                return "xmark.octagon.fill"
                            }()
                            Image(systemName: iconName)
                                .foregroundStyle(Theme.Color.secondaryText)
                            Text(worthItMessage)
                                .font(Theme.Font.headline)
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Theme.Color.sectionBackground.opacity(0.6))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Theme.Color.accent.opacity(0.12), lineWidth: 1)
                                )
                        )
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .frame(maxHeight: scrollMaxHeight)
                .background(
                    // Clean inner card (no inner border) for a subtler look
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.35))
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.98))
                    .background(
                        Theme.Gradient.subtleGlow
                            .opacity(0.18)
                            .blur(radius: 12)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Theme.Gradient.appBluePurple, lineWidth: 2.0)
                    .shadow(color: Theme.Color.accent.opacity(0.08), radius: 12, y: 4)
            )
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
            .shadow(color: .black.opacity(0.25), radius: 30, y: 8)
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    animateDepth = breakdown.contentDepthScore
                    animateSentiment = breakdown.commentSentimentScore
                }
            }
        }
    }
}

struct ScoreBreakdownBar: View {
    let label: String
    let value: Double
    let icon: String
    let color: Color
    @Binding var animatedValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(label)
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(Theme.Color.primaryText)
                Spacer()
                Text("\(Int(animatedValue * 100))%")
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(color)
            }
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.7))
                    .frame(height: 10)
                GeometryReader { geo in
                    Capsule(style: .continuous)
                        .fill(LinearGradient(gradient: Gradient(colors: [color.opacity(0.95), color.opacity(0.65)]), startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, CGFloat(max(0, min(animatedValue, 1))) * geo.size.width), height: 10)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                }
                .frame(height: 10)
            }
            .clipShape(Capsule())
            .shadow(color: color.opacity(0.12), radius: 2, y: 1)
        }
        .padding(.vertical, 2)
    }
}

struct BreakdownReasonSection: View {
    let title: String
    let positives: [String]
    let negatives: [String]
    let positiveIcon: String
    let negativeIcon: String
    let positiveColor: Color
    let negativeColor: Color
    var maxItems: Int = 2

    private var hasContent: Bool {
        !(positives.isEmpty && negatives.isEmpty)
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.secondaryText)
                    .kerning(0.4)
                VStack(spacing: 8) {
                    ForEach(positives.prefix(maxItems), id: \.self) { reason in
                        ReasonRow(icon: positiveIcon, text: reason, color: positiveColor)
                    }
                    ForEach(negatives.prefix(maxItems), id: \.self) { reason in
                        ReasonRow(icon: negativeIcon, text: reason, color: negativeColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }
}

struct ReasonRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .padding(6)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            Text(text)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.4))
        )
    }
}

struct ScoreWarningCapsule: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(Theme.Font.captionBold)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(Theme.Color.warning)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.55))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Theme.Color.warning.opacity(0.25), lineWidth: 0.8)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ThemePillsView: View {
    let title: String
    let themes: [String]
    let color: SwiftUI.Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(color)
            WrapHStack(spacing: 8, lineSpacing: 8) {
                ForEach(themes, id: \.self) { theme in
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(theme)
                            .font(Theme.Font.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Theme.Color.sectionBackground.opacity(0.65))
                            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
                    )
                    .foregroundColor(Theme.Color.primaryText)
                }
            }
        }
    }
}

// Simple wrapping HStack for pills
struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    var body: some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                content
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > geo.size.width) {
                            width = 0
                            height -= d.height + lineSpacing
                        }
                        let result = width
                        if d[.trailing] > geo.size.width { width = 0 }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        return result
                    }
                    .background(SizeReader())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 10)
    }
}

// Helper to force layout updates
struct SizeReader: View {
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}

#if DEBUG
struct InitialScreen_Previews: PreviewProvider {
    static var previews: some View {
        let apiManager = APIManager()
        let cacheManager = CacheManager.shared
        let subscriptionManager = SubscriptionManager()
        let usageTracker = UsageTracker()
        let viewModel = MainViewModel(
            apiManager: apiManager,
            cacheManager: cacheManager,
            subscriptionManager: subscriptionManager,
            usageTracker: usageTracker
        )

        viewModel.currentVideoTitle = "Preview: The Mind-Blowing Future of AI & Creativity"
        // Use higher-res thumbnail for preview
        viewModel.currentVideoThumbnailURL = URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        viewModel.worthItScore = 88
        viewModel.analysisResult = ContentAnalysis(
            longSummary: "A detailed exploration into how artificial intelligence is revolutionizing art, music, writing, and design, featuring expert interviews and stunning demonstrations of AI-generated content. The video discusses both the exciting possibilities and the ethical considerations.",
            takeaways: ["AI tools are becoming more accessible.", "Ethical discussions are crucial.", "Human-AI collaboration is the future."],
            gemsOfWisdom: ["Creativity is intelligence having fun, even if that intelligence is artificial."],
            videoId: "dQw4w9WgXcQ",
            videoTitle: "Preview: The Mind-Blowing Future of AI & Creativity",
            videoDurationSeconds: 200,
            videoThumbnailUrl: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg",
            CommentssentimentSummary: "",
            topThemes: []
        )
        viewModel.rawTranscript = "This is a sample transcript..."
        viewModel.scoreBreakdownDetails = ScoreBreakdown(
            contentDepthScore: 0.85,
            commentSentimentScore: 0.92,
            hasComments: true,
            contentDepthRaw: 0.87,
            commentSentimentRaw: 0.55,
            finalScore: 88,
            videoTitle: "Preview: The Mind-Blowing Future of AI & Creativity",
            positiveCommentThemes: ["Incredibly insightful!", "Loved the examples.", "Great production quality."],
            negativeCommentThemes: ["A bit too long."],
            contentHighlights: ["Turns 90 minutes into a tight 3-step creativity workout.", "Names concrete AI tools plus usage guardrails."],
            contentWatchouts: ["Skips hardware requirements and pricing details."],
            commentHighlights: ["42% rave about the live prompt demos.", "Viewers say it finally shows practical workflows."],
            commentWatchouts: ["Some think the sponsor plug drags on."],
            spamRatio: 0.08,
            commentsAnalyzed: 42
        )

        return InitialScreen()
            .environmentObject(viewModel)
            .environmentObject(subscriptionManager)
            .preferredColorScheme(.dark)
    }
}
#endif

struct LoadingDotsView: View {
    @State private var dotCount: Int = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(repeating: ".", count: dotCount + 1))
            .font(.caption)
            .foregroundColor(Theme.Color.secondaryText)
            .onReceive(timer) { _ in
                dotCount = (dotCount + 1) % 3
            }
    }
}

struct AboutView: View {
    static var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let join = build.isEmpty ? version : "\(version) (\(build))"
        return "WorthIt.AI v\(join)"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header card
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Theme.Color.sectionBackground.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue.opacity(0.45), Color.purple.opacity(0.45)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)

                        HStack(spacing: 16) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("WorthIt.AI")
                                    .font(Theme.Font.title2.weight(.bold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                Text("AI‑Powered YouTube Video Analysis")
                                    .font(Theme.Font.subheadline)
                                    .foregroundColor(Theme.Color.secondaryText)

                                // Removed small chips for a cleaner header
                            }
                            Spacer()
                        }
                        .padding(18)
                    }
                    .padding(.top, 6)

                    // Feature grid
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What it does")
                            .font(Theme.Font.headline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            FeatureCard(icon: "sparkles", title: "AI Summaries", detail: "Key ideas in seconds")
                                .frame(maxWidth: .infinity, minHeight: 96)
                            FeatureCard(icon: "gauge.high", title: "Worth‑It Score", detail: "Quick value signal")
                                .frame(maxWidth: .infinity, minHeight: 96)
                            FeatureCard(icon: "list.bullet.rectangle.portrait.fill", title: "Takeaways", detail: "Actionable highlights")
                                .frame(maxWidth: .infinity, minHeight: 96)
                            FeatureCard(icon: "person.2.wave.2.fill", title: "Comment Insights", detail: "Audience sentiment")
                                .frame(maxWidth: .infinity, minHeight: 96)
                            FeatureCard(icon: "questionmark.circle.fill", title: "Ask Anything", detail: "Interactive Q&A")
                                .frame(maxWidth: .infinity, minHeight: 96)
                            FeatureCard(icon: "doc.text.magnifyingglass", title: "Transcript", detail: "Grounded answers")
                                .frame(maxWidth: .infinity, minHeight: 96)
                        }
                    }

                    // How it works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How it works")
                            .font(Theme.Font.headline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        Text("WorthIt.AI uses publicly available YouTube transcripts and comments to provide AI‑powered analysis. We send that public content to our AI provider to generate structured insights, summaries, and interactive Q&A. We do not require an account or collect personal information.")
                            .font(Theme.Font.body)
                            .foregroundColor(Theme.Color.secondaryText)
                            .lineSpacing(4)
                    }

                    // Quick links
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Links")
                            .font(Theme.Font.headline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        HStack(spacing: 10) {
                            SmallLinkButton(title: "Privacy", url: AppConstants.privacyPolicyURL)
                            SmallLinkButton(title: "Terms", url: AppConstants.termsOfUseURL)
                            SmallLinkButton(title: "Support", url: AppConstants.supportURL)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Subscription")
                            .font(Theme.Font.headline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        HStack(spacing: 10) {
                            SmallLinkButton(title: "Manage Subscription", url: AppConstants.manageSubscriptionsURL)
                        }
                    }

                    // Report an Issue (email)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Support")
                            .font(Theme.Font.headline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        HStack(spacing: 10) {
                            SmallLinkButton(
                                title: "Report an Issue",
                                url: URL(string: "mailto:worthit.tuliai@gmail.com?subject=WorthIt.AI%20Support&body=Please%20describe%20the%20issue.%20If%20possible%2C%20include%20the%20YouTube%20URL.%0A")!
                            )
                        }
                    }

                    // Backend info section removed to reduce clutter

                    // Data handling & privacy (aligned with policy)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Data & Privacy")
                            .font(Theme.Font.headline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        VStack(alignment: .leading, spacing: 8) {
                            DisclaimerRow(icon: "person.crop.circle.badge.xmark", text: "No accounts or personal data collected")
                            DisclaimerRow(icon: "doc.text", text: "Analyzes public transcripts and some comments only")
                            DisclaimerRow(icon: "clock.fill", text: "Temporary caching for speed; limited diagnostics kept briefly")
                            DisclaimerRow(icon: "exclamationmark.triangle.fill", text: "Not affiliated with YouTube or Google")
                        }
                    }

                    // Version (from bundle)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Version")
                            .font(Theme.Font.headline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        Text("WorthIt.AI v1.01")
                            .font(Theme.Font.body)
                            .foregroundColor(Theme.Color.secondaryText)
                    }

                    Spacer(minLength: 36)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(Theme.Color.darkBackground)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Color.accent)
                Text(title)
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
            }
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

private struct SmallLinkButton: View {
    let title: String
    let url: URL
    var body: some View {
        Link(destination: url) {
            Text(title)
                .font(Theme.Font.caption.weight(.semibold))
                .foregroundColor(Theme.Color.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.7))
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.5)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
        }
    }
}

private struct MiniTagChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(Theme.Font.caption)
        }
        .foregroundColor(Theme.Color.primaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.35))
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                        .blur(radius: 4)
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.7)
                )
                .overlay(
                    Capsule().stroke(Theme.Color.accent.opacity(0.2), lineWidth: 0.8)
                        .blendMode(.overlay)
                )
        )
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.Color.accent)
                .frame(width: 20)
            
            Text(text)
                .font(Theme.Font.body)
                .foregroundColor(Theme.Color.secondaryText)
            
            Spacer()
        }
    }
}

struct DisclaimerRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.Color.warning)
                .frame(width: 16)
            
            Text(text)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
            
            Spacer()
        }
    }
}

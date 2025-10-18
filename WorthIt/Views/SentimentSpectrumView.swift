

//
//  SentimentSpectrumView.swift
//  WorthIt
//
//  Created by Gemini
//

import SwiftUI

struct SentimentSpectrumView: View {
    let themes: [CommentTheme]
    @State private var selectedThemeID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeatmapView(themes: themes, selectedThemeID: $selectedThemeID)

            ThemeTrayView(themes: themes, selectedThemeID: $selectedThemeID)

            if let selectedTheme = themes.first(where: { $0.id == selectedThemeID }) {
                InspectorPanelView(theme: selectedTheme)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    .padding(.top, 5)
            }
        }
        .padding(.vertical)
        .onAppear {
            if selectedThemeID == nil {
                selectedThemeID = themes.max(by: { ($0.sentimentScore ?? -1) < ($1.sentimentScore ?? -1) })?.id
            }
        }
    }
}

// MARK: - HeatmapView (The Visual Fingerprint)
struct HeatmapView: View {
    let themes: [CommentTheme]
    @Binding var selectedThemeID: UUID?

    let spectrumGradient = LinearGradient(
        gradient: Gradient(colors: [Theme.Color.error, Theme.Color.warning, Theme.Color.success]),
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // The resonant bar
                    Capsule()
                        .fill(spectrumGradient)
                        .frame(height: 10)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))

                    // Staggered theme bubbles
                    let staggeredThemes = staggerThemes(themes: themes, in: geometry.size.width)
                    ForEach(staggeredThemes, id: \.theme.id) { item in
                        let isSelected = selectedThemeID == item.theme.id
                        Button(action: {
                            withAnimation(.spring()) { selectedThemeID = item.theme.id }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(sentimentColor(for: item.theme.sentimentScore ?? 0))
                                    .frame(width: isSelected ? 28 : 22, height: isSelected ? 28 : 22)
                                    .overlay(Circle().stroke(Theme.Color.darkBackground, lineWidth: 2))
                                    .shadow(color: .white.opacity(isSelected ? 0.5 : 0.2), radius: isSelected ? 8 : 4)

                                Image(systemName: Theme.Font.icon(for: item.theme.sentimentScore ?? 0))
                                    .font(isSelected ? .system(size: 14, weight: .bold) : .system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .offset(x: item.xOffset, y: item.yOffset)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .animation(.spring(response: 0.4, dampingFraction: 0.5), value: isSelected)
                    }
                }
            }
            .frame(height: 50) // Increased height for staggering

            // Legend
            HStack {
                Text("Negative").font(Theme.Font.caption).foregroundColor(Theme.Color.secondaryText)
                Spacer()
                Text("Positive").font(Theme.Font.caption).foregroundColor(Theme.Color.secondaryText)
            }
            .padding(.horizontal, 5)
            .padding(.top, 8)
        }
    }

    private func sentimentColor(for score: Double) -> Color {
        if score > 0.15 { return Theme.Color.success }
        if score < -0.15 { return Theme.Color.error }
        return Theme.Color.warning
    }

    private func staggerThemes(themes: [CommentTheme], in width: CGFloat) -> [(theme: CommentTheme, xOffset: CGFloat, yOffset: CGFloat)] {
        let sortedThemes = themes.sorted { ($0.sentimentScore ?? 0) < ($1.sentimentScore ?? 0) }
        var positions: [(theme: CommentTheme, xOffset: CGFloat, yOffset: CGFloat)] = []
        let bubbleWidth: CGFloat = 16

        for theme in sortedThemes {
            let score = theme.sentimentScore ?? 0
            let normalizedScore = (score + 1.0) / 2.0
            let xOffset = CGFloat(normalizedScore) * (width - bubbleWidth)

            var yOffset: CGFloat = 0
            if let lastPos = positions.last, (xOffset - lastPos.xOffset) < (bubbleWidth * 1.8) {
                yOffset = (lastPos.yOffset == 0) ? -18 : (lastPos.yOffset == -18) ? 18 : 0
            }
            positions.append((theme, xOffset, yOffset))
        }
        return positions
    }
}

// MARK: - ThemeTrayView (Interactive Chips with Live Sync)
struct ThemeTrayView: View {
    let themes: [CommentTheme]
    @Binding var selectedThemeID: UUID?

    var body: some View {
        ScrollViewReader {
            proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(themes) { theme in
                        ThemeChip(theme: theme, isSelected: selectedThemeID == theme.id) {
                            withAnimation(.spring()) { selectedThemeID = theme.id }
                        }
                        .id(theme.id)
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 40)
            .onChange(of: selectedThemeID) { newID in
                if let newID = newID {
                    withAnimation(.easeInOut) { proxy.scrollTo(newID, anchor: .center) }
                }
            }
        }
    }
}

struct ThemeChip: View {
    let theme: CommentTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: Theme.Font.icon(for: theme.sentimentScore ?? 0))
                Text(theme.theme)
            }
            .font(Theme.Font.captionBold)
            .foregroundColor(isSelected ? .white.opacity(0.9) : Theme.Color.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        Theme.Gradient.primaryButton
                    } else {
                        Theme.Color.sectionBackground.opacity(0.8)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Theme.Color.purple.opacity(0.8) : Theme.Color.accent.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: isSelected ? Theme.Color.purple.opacity(0.6) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - InspectorPanelView (The Details)
struct InspectorPanelView: View {
    let theme: CommentTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(theme.theme)
                    .font(Theme.Font.headlineBold)
                    .foregroundColor(Theme.Color.primaryText)
                Spacer()
                Text(String(format: "Score: %.2f", theme.sentimentScore ?? 0))
                    .font(Theme.Font.subheadlineBold)
                    .foregroundStyle(Theme.Gradient.accent)
            }

            if let example = theme.exampleComment, !example.isEmpty {
                Text("\"\(example)\"")
                    .font(Theme.Font.body.italic())
                    .foregroundColor(Theme.Color.secondaryText)
                    .lineSpacing(4)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Theme.Color.darkBackground.opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Color.sectionBackground, lineWidth: 2))
    }
}

#if DEBUG
struct SentimentSpectrumView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleThemes = [
            CommentTheme(theme: "Amazing Cinematography", sentiment: "Positive", sentimentScore: 0.9, exampleComment: "The shots in this video are absolutely breathtaking! I could watch this all day."),
            CommentTheme(theme: "Sound Quality", sentiment: "Negative", sentimentScore: -0.7, exampleComment: "Great content, but the audio is really muffled and hard to hear at times."),
            CommentTheme(theme: "Pacing", sentiment: "Mixed", sentimentScore: 0.1, exampleComment: "The beginning was a bit slow, but it really picked up in the second half."),
            CommentTheme(theme: "Creator's Argument", sentiment: "Positive", sentimentScore: 0.6, exampleComment: "I completely agree with the points made. Very well-reasoned and convincing."),
            CommentTheme(theme: "Clickbait Title", sentiment: "Negative", sentimentScore: -0.4, exampleComment: "The title is a bit misleading, the content didn't really match what was promised.")
        ]

        return ZStack {
            Theme.Color.darkBackground.ignoresSafeArea()
            ScrollView {
                SentimentSpectrumView(themes: sampleThemes)
                    .padding()
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif

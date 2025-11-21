import SwiftUI

// MARK: - Decision Card
struct DecisionCardView: View {
    let model: DecisionCardModel
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onClose: () -> Void

    @State private var animateIn = false
    @State private var showGaugeBreakdown = false
    @State private var gaugeAnimationCompleted = false

    private var brandGradient: LinearGradient { Theme.Gradient.appLogoText() }
    private let mediaHeight: CGFloat = 68

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 10)

            Divider()
                .overlay(Color.white.opacity(0.12))
                .padding(.horizontal, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    snapshotSection
                    learningsSection
                    dataGrid
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)

            footerButtons
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 18)
        }
        .background(cardBackground)
        .overlay(closeButton, alignment: .topTrailing)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
        .padding(.horizontal, 12)
        .padding(.vertical, 28)
        .scaleEffect(animateIn ? 1 : 0.94)
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                animateIn = true
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            brandMark

            HStack(alignment: .center, spacing: 14) {
                thumbnail(size: CGSize(width: 112, height: mediaHeight))

                Spacer()

                gaugeView
                    .frame(width: mediaHeight, height: mediaHeight)
            }
        }
    }

    private var brandMark: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.75))
                .frame(width: 36, height: 36)
                .overlay(
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(brandGradient, lineWidth: 1)
                )
                .shadow(color: Theme.Color.accent.opacity(0.22), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text("WorthIt verdict")
                    .font(Theme.Font.captionBold)
                    .foregroundStyle(brandGradient)
                verdictBadge
            }
        }
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Snapshot: What is the prompt that defines it?")

            Text(model.reason)
                .font(Theme.Font.body)
                .foregroundColor(Theme.Color.primaryText)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let skip = model.skipNote, !skip.isEmpty {
                Text(skip)
                    .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var learningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.learnings.isEmpty {
                sectionHeader("What you'll learn")
            }

            ForEach(model.learnings.prefix(3), id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(brandGradient)
                        .padding(.top, 1)

                    Text(item)
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.94))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var dataGrid: some View {
        VStack(spacing: 0) {
            gridRow(icon: model.depthChip.iconName, title: model.depthChip.title, value: model.depthChip.detail)
            Divider().background(Color.white.opacity(0.08)).padding(.leading, 46)
            gridRow(icon: model.commentsChip.iconName, title: model.commentsChip.title, value: model.commentsChip.detail)

            if let bestText = bestMomentText {
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 46)
                gridRow(icon: "forward.end.alt.fill", title: "Best moment", value: bestText)
            }
        }
        .background(Theme.Color.sectionBackground.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(brandGradient.opacity(0.35), lineWidth: 0.8)
                .blendMode(.overlay)
        )
    }

    private func gridRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.Color.secondaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.primaryText.opacity(0.78))
                Text(value)
                    .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var footerButtons: some View {
        VStack(spacing: 12) {
            primaryButton
            secondaryButton
        }
    }

    // MARK: - Elements

    private var gaugeView: some View {
        ScoreGaugeView(
            score: model.score ?? 0,
            isLoading: false,
            showBreakdown: $showGaugeBreakdown,
            isAnimationCompleted: $gaugeAnimationCompleted
        )
        .frame(width: 64, height: 64)
    }

    private var verdictBadge: some View {
        let (label, tone): (String, Color) = {
            let resolvedScore = model.score ?? 0
            switch model.verdict {
            case .worthIt: return (verdictLabel, Theme.Color.success)
            case .skip: return (verdictLabel, Theme.Color.error)
            case .maybe: return (verdictLabel, resolvedScore >= 50 ? Theme.Color.warning : Theme.Color.secondaryText)
            @unknown default: return ("Verdict", Theme.Color.secondaryText)
            }
        }()

        return Text(label)
            .font(Theme.Font.captionBold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.opacity(0.12))
            )
            .foregroundColor(tone)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tone.opacity(0.35), lineWidth: 0.9)
            )
    }

    private var verdictLabel: String {
        switch model.verdict {
        case .worthIt: return "Worth it"
        case .skip: return "Skip it"
        case .maybe: return "Borderline"
        @unknown default: return "Verdict"
        }
    }

    private var primaryButton: some View {
        Button(action: onPrimaryAction) {
            HStack {
                Image(systemName: "sparkles")
                Text("Open Essentials")
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .font(Theme.Font.headlineBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Theme.Color.brandCyan, Theme.Color.brandPurple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(brandGradient.opacity(0.5), lineWidth: 0.8)
                    .blur(radius: 2)
            )
            .shadow(color: Theme.Color.accent.opacity(0.45), radius: 14, y: 8)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var secondaryButton: some View {
        Button(action: onSecondaryAction) {
            HStack {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                Text(model.topQuestion.map { "Ask: \($0)" } ?? "Ask WorthIt AI")
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .font(Theme.Font.subheadlineBold)
            .foregroundStyle(brandGradient)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(brandGradient, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.Color.secondaryText)
                .padding(10)
                .background(
                    Circle()
                        .fill(Theme.Color.sectionBackground.opacity(0.7))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                )
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(brandGradient)
                .frame(width: 18, height: 3)
                .cornerRadius(2)
            Text(text.uppercased())
                .font(Theme.Font.captionBold)
                .foregroundColor(Theme.Color.secondaryText)
        }
    }

    private func thumbnail(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.Color.sectionBackground.opacity(0.7))
            .frame(width: size.width, height: size.height)
            .overlay(
                AsyncImage(url: model.thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "play.rectangle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .foregroundColor(Theme.Color.secondaryText)
                    @unknown default:
                        EmptyView()
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
    }

    private var bestMomentText: String? {
        if let seconds = model.bestStartSeconds, seconds > 0 {
            return "Highlights start near \(formattedBestStart)"
        }
        let detail = cleanedDetail(model.jumpChip.detail)
        return detail.isEmpty ? nil : detail
    }

    private func cleanedDetail(_ text: String) -> String {
        if let range = text.range(of: "http") {
            let trimmed = text[..<range.lowerBound]
            return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var formattedBestStart: String {
        guard let seconds = model.bestStartSeconds else { return "" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Theme.Color.sectionBackground.opacity(0.95))
            .background(
                Theme.Gradient.brandSheen()
                    .opacity(0.18)
                    .blur(radius: 50)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(brandGradient.opacity(0.4), lineWidth: 0.9)
                    .blendMode(.overlay)
            )
    }
}

// Animation Helper
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

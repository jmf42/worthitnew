import SwiftUI

struct DecisionCardView: View {
    let model: DecisionCardModel
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onClose: () -> Void

    @State private var animateChips: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Text(model.reason)
                .font(Theme.Font.subheadline.weight(.semibold))
                .foregroundColor(Theme.Color.primaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.95)

            chipStack

            actionRow

            badgeRow
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.92))
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .blur(radius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.Gradient.appBluePurple, lineWidth: 1.2)
                        .opacity(0.6)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                animateChips = true
            }
        }
    }

    // MARK: - Sections
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    miniScoreGauge
                    verdictPill

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                if shouldShowTitle {
                    Text(model.title)
                        .font(Theme.Font.title3.weight(.bold))
                        .foregroundColor(Theme.Color.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            }
        }
    }

    private var chipStack: some View {
        VStack(spacing: 10) {
            DecisionChipView(
                chip: model.depthChip,
                animate: animateChips,
                delay: 0.0
            )
            DecisionChipView(
                chip: model.commentsChip,
                animate: animateChips,
                delay: 0.05
            )
            DecisionChipView(
                chip: model.jumpChip,
                animate: animateChips,
                delay: 0.1
            )
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Jump to best part")
                        .font(Theme.Font.subheadline.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Theme.Gradient.appBluePurple)
                .cornerRadius(14)
                .shadow(color: Theme.Color.purple.opacity(0.35), radius: 12, y: 6)
            }

            Button(action: onSecondaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Full breakdown")
                        .font(Theme.Font.captionBold)
                }
                .foregroundColor(Theme.Color.primaryText)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
            }
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            confidenceBadge

            if let timeValue = model.timeValue {
                badge(icon: "clock.fill", text: timeValue)
            }

            Spacer()
        }
    }

    // MARK: - Components
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.6))

            if let url = model.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(Theme.Color.accent)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 64)
                            .clipped()
                    case .failure:
                        Image(systemName: "film.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Theme.Color.secondaryText)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "film.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.Color.secondaryText)
            }
        }
        .frame(width: 96, height: 64)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var verdictPill: some View {
        Text(verdictText)
            .font(Theme.Font.captionBold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(verdictColor.opacity(0.9))
            .cornerRadius(10)
    }

    private func scorePill(score: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            Text("\(Int(score))")
        }
        .font(Theme.Font.captionBold)
        .foregroundColor(Theme.Color.primaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    private var confidenceBadge: some View {
        let color: Color = {
            switch model.confidence.level {
            case .high: return Theme.Color.success
            case .medium: return Theme.Color.warning
            case .low: return Theme.Color.orange
            }
        }()

        return badge(icon: "checkmark.seal.fill", text: model.confidence.label, foreground: color)
    }

    private func badge(icon: String, text: String, foreground: Color = Theme.Color.primaryText) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(Theme.Font.captionBold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundColor(foreground)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
        )
    }

    private var verdictText: String {
        switch model.verdict {
        case .worthIt: return "Worth It"
        case .skip: return "Skip It"
        case .maybe: return "Maybe"
        }
    }

    private var verdictColor: Color {
        switch model.verdict {
        case .worthIt: return Theme.Color.success
        case .skip: return Theme.Color.orange
        case .maybe: return Theme.Color.accent
        }
    }

    private var shouldShowTitle: Bool {
        let trimmed = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 0 else { return false }
        let likelyVideoId = trimmed.count == 11 && trimmed.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
        return !likelyVideoId
    }

    private var miniScoreGauge: some View {
        let score = model.score ?? 0
        return ZStack {
            Circle()
                .stroke(Theme.Color.sectionBackground.opacity(0.5), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(score / 100.0, 1.0)))
                .stroke(
                    Theme.Gradient.appBluePurple,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.Color.accent.opacity(0.3), radius: 3, y: 2)
            Text("\(Int(score))")
                .font(Theme.Font.captionBold)
                .foregroundColor(Theme.Color.primaryText)
        }
        .frame(width: 38, height: 38)
    }
}

private struct DecisionChipView: View {
    let chip: DecisionProofChip
    let animate: Bool
    let delay: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: chip.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.Color.accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Theme.Color.sectionBackground.opacity(0.65))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(chip.title)
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
                Text(chip.detail)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .offset(y: animate ? 0 : 12)
        .opacity(animate ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.9).delay(delay), value: animate)
    }
}

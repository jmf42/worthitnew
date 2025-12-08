import SwiftUI

/// Lightweight share guide shown from onboarding and the main Share from YouTube entry.
struct ShareExplanationModal: View {
    let onDismiss: () -> Void
    let borderGradient: LinearGradient

    private let steps: [ShareGuideStep] = [
        ShareGuideStep(icon: "play.rectangle.fill", title: "Open a YouTube video", detail: "Pick any video you want to analyze."),
        ShareGuideStep(icon: "square.and.arrow.up", title: "Tap Share → WorthIt", detail: "Tap Share, then More (…) if needed, and pick WorthIt."),
        ShareGuideStep(icon: "sparkles", title: "WorthIt responds instantly", detail: "We pull the transcript and return the recap, score, and Q&A.")
    ]

    var body: some View {
        ZStack {
            Theme.Color.darkBackground.opacity(0.9)
                .ignoresSafeArea()
                .overlay(Theme.Gradient.vignette)
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 14) {
                        intro
                        stepsSection
                        missingSection
                    }
                    .padding(16)
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.72)

                doneButton
            }
            .frame(maxWidth: 600)
            .background(Theme.Color.sectionBackground.opacity(0.96))
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderGradient.opacity(0.8), lineWidth: 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
            .padding(22)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(Theme.Font.subheadline.weight(.semibold))
                }
                .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(borderGradient.opacity(0.7), lineWidth: 0.9)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss Share Explanation")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Share from YouTube")
                .font(Theme.Font.title3.weight(.bold))
                .foregroundColor(Theme.Color.primaryText)
            Text("Fastest way to send a video to WorthIt and get the recap, score, and Q&A.")
                .font(Theme.Font.subheadline)
                .foregroundColor(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
        )
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to share")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)

            VStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    ShareGuideStepRow(index: index + 1, step: step)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
        )
    }

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Don't see WorthIt?")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)
            Text("Add it to Favorites once in the Share Sheet and it will stick.")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)

            VStack(spacing: 6) {
                MissingActionRow(number: 1, text: "Swipe up on the Share Sheet and tap More (…).")
                MissingActionRow(number: 2, text: "Tap \"Edit Actions…\" then the green + next to WorthIt, tap Done.")
                MissingActionRow(number: 3, text: "Optional: drag WorthIt to the top of Favorites.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
        )
    }

    private var doneButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onDismiss()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Got it")
                    .font(Theme.Font.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Gradient.appBluePurple.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
            )
            .shadow(color: Theme.Color.accent.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 6)
    }
}

private struct ShareGuideStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

private struct ShareGuideStepRow: View {
    let index: Int
    let step: ShareGuideStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index).")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Theme.Color.sectionBackground.opacity(0.8))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.6)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: step.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.Color.accent)
                    Text(step.title)
                        .font(Theme.Font.subheadline.weight(.semibold))
                        .foregroundColor(Theme.Color.primaryText)
                }
                Text(step.detail)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }
}

private struct MissingActionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(Theme.Font.captionBold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Theme.Color.sectionBackground.opacity(0.75))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                )

            Text(text)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

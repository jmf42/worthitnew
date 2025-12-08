import SwiftUI
import UIKit

// MARK: - Decision Card
struct DecisionCardView: View {
    let model: DecisionCardModel
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onScoreBreakdown: () -> Void
    let onClose: () -> Void
    let onBestMoment: (() -> Void)?

    @State private var animateIn = false
    @State private var gaugeAnimationCompleted = false
    @State private var highlightPulse = false

    // Standard border gradient used throughout the app – match app icon cyan → blue → purple
    private var standardBorderGradient: LinearGradient {
        Theme.Gradient.brand(startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    // Verdict-based theme colors
    private var verdictColor: Color {
        switch model.verdict {
        case .worthIt: return Theme.Color.success
        case .skip: return Theme.Color.error
        case .maybe: return Theme.Color.warning
        @unknown default: return Theme.Color.secondaryText
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Hero Section: Verdict Badge, Score & Reason (compact)
            heroSection
                .padding(.horizontal, 22) // Slightly wider text area
                .padding(.top, 24) // Increased spacing from top border
                .padding(.bottom, 6)
            
            // 3. Insights: Compact Learnings
            if !model.learnings.isEmpty {
                learningsSection
                    .padding(.horizontal, 20) // Align with hero
                    .padding(.top, 12) // Tighter spacing
            }

            // 4. Actions: Buttons
            footerButtons
                .padding(.horizontal, 20) // Align with rest
                .padding(.top, 20) // Balanced separation
                .padding(.bottom, 24) // Increased bottom spacing
        }
        .frame(maxWidth: 500) // Constrain width on iPad
        .background(liquidGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(edgeHighlightOverlay)
        .overlay(
            // Inner subtle highlight for 3D depth
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                .padding(0.5)
        )
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
        // 4. Balanced Shadow (Depth + Glow)
        .shadow(color: .black.opacity(0.5), radius: 35, y: 18)
        .shadow(color: verdictColor.opacity(0.12), radius: 25, y: 0) // Refined color glow
        .offset(y: -4) // Slight lift for better shadow breathing room
        .scaleEffect(animateIn ? 1 : 0.96)
        .opacity(animateIn ? 1 : 0)
        .onAppear {
            // Subtle breathing specular highlight
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                highlightPulse = true
            }
            // Smooth reveal animation when card appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                    animateIn = true
                }
            }
        }
    }

    // MARK: - Liquid Glass Background & Lighting
    private var liquidGlassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        
        return ZStack {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.black.opacity(0.45)))
            
            verdictColor
                .opacity(0.08)
                .blur(radius: 110)
            
            Theme.Gradient.brandSheen()
                .opacity(0.06)
            
            breathingHighlight
            
            NoiseOverlay()
                .blendMode(.softLight)
                .clipShape(shape)
        }
    }
    
    private var breathingHighlight: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(highlightPulse ? 0.18 : 0.05),
                        Color.white.opacity(0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blur(radius: 35)
            .blendMode(.screen)
    }
    
    private var edgeHighlightOverlay: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.6),
                        Color.white.opacity(0.2),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .blendMode(.screen)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.35), lineWidth: 1)
                    .blur(radius: 1.2)
                    .offset(x: 0.4, y: 0.9)
                    .mask(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
            )
    }
    
    private struct NoiseOverlay: View {
        var body: some View {
            Canvas { context, size in
                let density = Int((size.width * size.height) / 700)
                for _ in 0..<density {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let rect = CGRect(x: x, y: y, width: 1, height: 1)
                    let opacity = Double.random(in: 0.02...0.06)
                    context.fill(Path(rect), with: .color(.white.opacity(opacity)))
                }
            }
            .allowsHitTesting(false)
            .opacity(0.12)
        }
    }

    // MARK: - Close Button
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(Theme.Font.captionBold)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(.white.opacity(0.15))
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 2. Hero Section (Compact)
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) { // Balanced breathing room
            // Verdict Badge - Centered, proper spacing
            HStack(spacing: 6) {
                Text("VERDICT:")
                    .font(Theme.Font.captionBold)
                    .foregroundStyle(verdictColor.opacity(0.9))
                
                HStack(spacing: 4) {
                    Image(systemName: verdictIcon)
                        .font(Theme.Font.caption2.weight(.black))
                    Text(verdictLabel.uppercased())
                        .font(Theme.Font.captionBold)
                        .tracking(0.8)
                }
                .foregroundStyle(verdictColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(verdictColor.opacity(0.08))
                    .overlay(
                        Capsule()
                            .strokeBorder(verdictColor.opacity(0.18), lineWidth: 1)
                    )
            )
            .shadow(color: verdictColor.opacity(0.15), radius: 4, x: 0, y: 2)
            .frame(maxWidth: .infinity) // Center the badge horizontally
            .padding(.top, 0) // No extra padding (hero section handles it)
            .padding(.bottom, 10) // Uniform spacing: verdict-to-content

            HStack(alignment: .center, spacing: 16) {
                gaugeSection
                    .frame(width: 98)

                reasonBox
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Hero Reason - Stable, properly aligned formatting (placed below gauge + why)
            Text(model.reason)
                .font(Theme.Font.title3.weight(.bold))
                .foregroundColor(.white.opacity(0.95))
                .multilineTextAlignment(.leading)
                .lineSpacing(5)
                .kerning(0.1)
                .lineLimit(nil)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why")
                .font(Theme.Font.captionBold)
                .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                .textCase(.uppercase)
                .tracking(0.8)

            if let scoreReasonLine = model.scoreReasonLine, !scoreReasonLine.isEmpty {
                Text(scoreReasonLine)
                    .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.95))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        )
    }

    private var gaugeSection: some View {
        ZStack {
            // Subtle glow behind gauge
            Circle()
                .fill(verdictColor)
                .frame(width: 46, height: 46)
                .blur(radius: 28)
                .opacity(0.22)
            
            ScoreGaugeView(
                score: model.score ?? 0,
                isLoading: false,
                showBreakdown: .constant(false),
                isAnimationCompleted: $gaugeAnimationCompleted
            )
                .frame(width: 76, height: 76)
            .accessibilityHint("Worth-It score display")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            triggerScoreBreakdown()
        }
        .overlay(alignment: .topTrailing) {
            Button(action: triggerScoreBreakdown) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Show score breakdown")
            .accessibilityHint("Opens detailed score metrics")
            .offset(x: 18, y: -18)
        }
    }

    // MARK: - 3. Learnings (Always fits)
    private var learningsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subtitle
            Text("You'll learn:")
                .font(Theme.Font.subheadline.weight(.semibold))
                .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                .padding(.bottom, 2)
            
            // Learning items (without "You'll learn" prefix)
            ForEach(model.learnings.prefix(2), id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(Theme.Font.captionBold)
                        .foregroundStyle(Theme.Gradient.appBluePurple)
                        .padding(.top, 2)
                        .shadow(color: Theme.Color.brandBlue.opacity(0.4), radius: 3)

                    Text(capitalizeFirst(item))
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText)
                        .lineLimit(nil) // Allow full text
                        .fixedSize(horizontal: false, vertical: true) // Expand to fit
                        .minimumScaleFactor(0.9) // Slight scale if needed
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 4. Footer Actions
    private var footerButtons: some View {
        HStack(spacing: 12) {
            // Primary: View Details (Prominent, filled gradient)
            Button(action: onPrimaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(Theme.Font.subheadlineBold)
                    Text("View Details")
                        .font(Theme.Font.subheadlineBold)
                }
            }
            .buttonStyle(GlassButtonStyle(kind: .primary, tint: Theme.Gradient.appBluePurple))

            // Secondary: Ask Question (Outlined style for clear hierarchy)
            Button(action: onSecondaryAction) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(Theme.Font.subheadlineBold)
                    Text("Ask Question")
                        .font(Theme.Font.subheadlineBold)
                }
            }
            .buttonStyle(GlassButtonStyle(kind: .secondary, tint: Theme.Gradient.appBluePurple))
        }
    }

    private func capitalizeFirst(_ str: String) -> String {
        return str.prefix(1).capitalized + str.dropFirst()
    }

    private func triggerScoreBreakdown() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onScoreBreakdown()
    }

    // MARK: - Helpers
    private var verdictLabel: String {
        switch model.verdict {
        case .worthIt: return "Worth It"
        case .skip: return "Skip It"
        case .maybe: return "Borderline"
        @unknown default: return "Verdict"
        }
    }

    private var verdictIcon: String {
        switch model.verdict {
        case .worthIt: return "checkmark.seal.fill"
        case .skip: return "hand.thumbsdown.fill"
        case .maybe: return "exclamationmark.triangle.fill"
        @unknown default: return "circle"
        }
    }
}

// MARK: - Glass Button Style
struct GlassButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }
    
    var kind: Kind
    var tint: LinearGradient
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(kind == .primary ? Color.white : Theme.Color.primaryText.opacity(0.95))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(buttonBackground(configuration: configuration))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: configuration.isPressed)
    }
    
    @ViewBuilder
    private func buttonBackground(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(alignment: .center) {
                if kind == .primary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint)
                        .opacity(0.65)
                        .blendMode(.screen)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(kind == .primary ? 0.8 : 0.35)
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(kind == .primary ? 0.4 : 0.25), lineWidth: 1)
                    .blendMode(.screen)
            )
            .shadow(color: shadowColor(configuration: configuration), radius: configuration.isPressed ? 2 : 8, y: 4)
    }
    
    private func shadowColor(configuration: Configuration) -> Color {
        guard !configuration.isPressed else { return .clear }
        return kind == .primary ? Theme.Color.brandPurple.opacity(0.35) : Theme.Color.brandBlue.opacity(0.2)
    }
}

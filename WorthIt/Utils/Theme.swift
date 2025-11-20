//
//  Theme.swift
//  WorthIt
//
//  Legacy-dark design system (single, definitive version)
//

import SwiftUI

// MARK: - Root namespace
struct Theme {

    // MARK: Colours
    struct Color {
        static let darkBackground    = SwiftUI.Color(white: 0.12)  // Darker for more depth
        static let sectionBackground = SwiftUI.Color(white: 0.18)  // Slightly lighter section
        static let primaryText       = SwiftUI.Color.white
        static let secondaryText     = SwiftUI.Color(white: 0.75)  // Brighter secondary text

        static let accent = SwiftUI.Color("AccentColor") // Ensure this is defined in Assets

        static let success           = SwiftUI.Color.green
        static let warning           = SwiftUI.Color.yellow
        static let orange            = SwiftUI.Color.orange
        static let error             = SwiftUI.Color.red

        static let purple            = SwiftUI.Color.purple
    }

    // MARK: Typography
    struct Font {
        static let largeTitleNumeric = SwiftUI.Font.system(size: 48, weight: .bold,  design: .rounded)

        static let largeTitle  = SwiftUI.Font.system(size: 34, weight: .bold,  design: .rounded)
        static let title       = SwiftUI.Font.system(size: 28, weight: .bold,  design: .rounded) // Slightly larger
        static let title2      = SwiftUI.Font.system(size: 24, weight: .bold,  design: .rounded) // Slightly larger
        static let title3      = SwiftUI.Font.system(size: 20, weight: .semibold, design: .rounded)

        static let headline    = SwiftUI.Font.system(size: 18, weight: .semibold, design: .rounded)
        static let headlineBold = SwiftUI.Font.system(size: 18, weight: .bold, design: .rounded)

        static let body        = SwiftUI.Font.system(size: 17, weight: .regular, design: .rounded)
        static let bodyBold    = SwiftUI.Font.system(size: 17, weight: .bold,    design: .rounded)

        static let subheadline       = SwiftUI.Font.system(size: 15, weight: .regular, design: .rounded)
        static let subheadlineBold   = SwiftUI.Font.system(size: 15, weight: .semibold,design: .rounded)

        static let caption     = SwiftUI.Font.system(size: 13, weight: .regular, design: .rounded)
        static let captionBold = SwiftUI.Font.system(size: 13, weight: .bold,    design: .rounded)
        static let captionItalic = SwiftUI.Font.system(size: 13, weight: .regular, design: .rounded).italic()
        static let caption2    = SwiftUI.Font.system(size: 12, weight: .regular, design: .rounded)

        static let toolbarTitle = SwiftUI.Font.system(size: 20, weight: .bold, design: .rounded)

        static func icon(for score: Double) -> String {
            if score > 0.5 { return "hand.thumbsup.fill" }
            if score > 0.15 { return "hand.thumbsup" }
            if score < -0.5 { return "hand.thumbsdown.fill" }
            if score < -0.15 { return "hand.thumbsdown" }
            return "exclamationmark.triangle.fill"
        }
    }

    // MARK: Gradients
    struct Gradient {
        static let accent = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [Theme.Color.accent, Theme.Color.purple]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing)

        static let bluePurple = accent // Alias

        // App/logo primary gradient (system blue → purple)
        static let appBluePurple = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [SwiftUI.Color.blue, SwiftUI.Color.purple]),
            startPoint: .leading,
            endPoint: .trailing
        )

        

        // Kept your tealGreen, but ensure hex colors are what you intend
        static let tealGreen = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [SwiftUI.Color(UIColor(hex: "30CFD0")),
                                                SwiftUI.Color(UIColor(hex: "330867"))]),
            startPoint: .leading,
            endPoint: .trailing)

        static let primaryButton = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [Theme.Color.accent.opacity(0.9), Theme.Color.purple.opacity(0.7)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing)

        // Soft pink ↔ purple used sparingly for onboarding accents
        static let pinkPurple = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [SwiftUI.Color.pink, Theme.Color.purple]),
            startPoint: .leading,
            endPoint: .trailing
        )

        static let secondaryButton = LinearGradient(
            gradient: SwiftUI.Gradient(colors: [Theme.Color.sectionBackground, Theme.Color.sectionBackground.opacity(0.8)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing)

        static let neonGlow = RadialGradient(
            gradient: SwiftUI.Gradient(colors: [
                Theme.Color.accent.opacity(0.5), // Slightly stronger inner glow
                Theme.Color.purple.opacity(0.3),
                SwiftUI.Color.clear
            ]),
            center: .center,
            startRadius: 0, // Start from center for a more focused glow
            endRadius: UIScreen.main.bounds.width / 1.5 // Adjust as needed
        )

        static let subtleGlow = RadialGradient(
            gradient: SwiftUI.Gradient(colors: [
                Theme.Color.accent.opacity(0.2),
                Theme.Color.darkBackground.opacity(0.0)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: UIScreen.main.bounds.width / 2
        )
    }

    // MARK: Metrics
    /// Central place for layout constants so the whole app stays visually consistent
    struct Metrics {
        static let cardCornerRadius: CGFloat = 16
        static let cardShadowRadius: CGFloat = 5
        static let cardPadding:      CGFloat = 16
    }

    // MARK: Button styles
    enum ButtonStyle {
        struct Primary: SwiftUI.ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .font(Theme.Font.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.Gradient.primaryButton)
                    .cornerRadius(12) // Consistent corner radius
                    .shadow(color: Theme.Color.purple.opacity(0.4), // Adjusted shadow
                            radius: configuration.isPressed ? 3 : 6,
                            y: configuration.isPressed ? 2 : 4)
                    .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6),
                               value: configuration.isPressed)
            }
        }

        struct Secondary: SwiftUI.ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .font(Theme.Font.captionBold) // Good for smaller suggestion buttons
                    .foregroundColor(Theme.Color.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.Color.sectionBackground.opacity(0.35))
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(SwiftUI.Color.white.opacity(0.04))
                                    .blur(radius: 4)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SwiftUI.Color.white.opacity(0.1), lineWidth: 0.7)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.Color.accent.opacity(0.2), lineWidth: 0.8)
                            .blendMode(.overlay)
                    )
                    .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6),
                               value: configuration.isPressed)
            }
        }
    }
}

// MARK: - Styled Option Button (Inspired by V1 SimpleOptionButton)
struct StyledOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: SwiftUI.Color
    let gradient: LinearGradient
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: {
            guard !isLoading || title == "Ask Anything" else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle().stroke(iconColor.opacity(0.3), lineWidth: 1)
                        )

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: iconColor))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(iconColor)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.Color.primaryText)
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Theme.Color.secondaryText.opacity(isLoading ? 0.3 : 0.7))
            }
            .padding()
            .background(
                Theme.Color.sectionBackground
                    .overlay(gradient.opacity(isPressed ? 0.2 : 0.1)) // Subtle gradient overlay
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        gradient.opacity(0.6), // Use the button's gradient for border
                        lineWidth: 1
                    )
            )
            .shadow(color: iconColor.opacity(0.2), radius: 5, y: 2)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading && title != "Ask Anything")
        .opacity(isLoading ? 0.7 : 1.0)
        .simultaneousGesture(
             DragGesture(minimumDistance: 0)
                 .onChanged { _ in if !isPressed { isPressed = true } }
                 .onEnded { _ in if isPressed { isPressed = false } }
         )
    }
}

// MARK: - Global card container style
private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Metrics.cardPadding)
            .background(Theme.Color.sectionBackground)
            .cornerRadius(Theme.Metrics.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.20),
                    radius: Theme.Metrics.cardShadowRadius,
                    y: 3)
    }
}

/// Apply a uniform elevated-card style that matches the design system
extension View {
    /// Wraps the view in the default WorthIt card container
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
}

// MARK: - Hex colour convenience
private extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (0, 0, 0, 0)
        }

        self.init(.sRGB,
                  red:   Double(r) / 255,
                  green: Double(g) / 255,
                  blue:  Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

import UIKit

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (0, 0, 0, 0)
        }

        self.init(red: CGFloat(r) / 255,
                  green: CGFloat(g) / 255,
                  blue: CGFloat(b) / 255,
                  alpha: CGFloat(a) / 255)
    }
}

// You still have this from V2, it seems fine.
// If you replace the action buttons with StyledOptionButton, this might not be needed directly in InitialScreen.
struct CapsuleGradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    let isSelected: Bool // Kept for potential future use or other contexts

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.headlineBold)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity) // Ensure it takes full width
            .background(
                gradient
                    .opacity(isSelected ? 1.0 : (configuration.isPressed ? 0.9 : 0.75))
                    .clipShape(Capsule())
            )
            .foregroundColor(.white)
            .shadow(color: Theme.Color.purple.opacity(isSelected ? 0.3 : 0.15), radius: isSelected ? 8 : 4, y: isSelected ? 4 : 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

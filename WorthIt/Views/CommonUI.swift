//
//  CommonUI.swift
//  WorthIt
//
import SwiftUI
import UIKit

// Helper modifier to conditionally run setup code in onAppear
private struct GroupModifier: ViewModifier {
    let isLoading: Bool
    let setup: () -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            if !isLoading {
                setup()
            }
        }
    }
}

// MARK: - Score Gauge
struct ScoreGaugeView: View {
    let score: Double // 0-100
    let isLoading: Bool // Indicates loading state to show spinner
    @Binding var showBreakdown: Bool // To trigger the sheet
    @Binding var isAnimationCompleted: Bool // To notify parent when animation finishes
    @State private var animatedScore: Double = 0
    @State private var pulsate = false
    @State private var spinnerRotating = false

    private var scoreGradient: Gradient {
        Gradient(colors: [Theme.Color.error, Theme.Color.orange, Theme.Color.warning, Theme.Color.success])
    }

    private var accessibilityScoreDescription: String {
        switch score {
        case 80...: return "Excellent."
        case 60..<80: return "Good."
        case 40..<60: return "Fair."
        default: return "Needs Improvement."
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                if isLoading {
                    // Spinner using same style as final gauge
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(gradient: scoreGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(Angle(degrees: spinnerRotating ? 360 : 0))
                        .frame(width: 72, height: 72)
                        .onAppear {
                            withAnimation(Animation.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                                spinnerRotating = true
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Loading score")
                } else {
                    ZStack {
                        ZStack {
                            // Background pulsating circle
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .scaleEffect(pulsate ? 1.2 : 0.8)
                                .opacity(pulsate ? 0.7 : 0.3)
                                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulsate)

                            Circle()
                                .stroke(Theme.Color.sectionBackground.opacity(0.4), lineWidth: 12)

                            Circle()
                                .trim(from: 0, to: CGFloat(animatedScore / 100))
                                .stroke(
                                    LinearGradient(gradient: scoreGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .rotationEffect(Angle(degrees: -90))
                                .shadow(color: Theme.Color.accent.opacity(0.4), radius: 6, x: 0, y: 3)
                                .scaleEffect(pulsate ? 1.05 : 1.0)
                        }

                        GeometryReader { geo in
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text("\(Int(animatedScore))")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Theme.Color.primaryText)
                                Text("%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.Color.secondaryText)
                                    .baselineOffset(1)
                            }
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        }
                    }
                }
            }
            .frame(width: 72, height: 72)
        }
        // Apply gauge-specific animations only when not loading
        .modifier(
            GroupModifier(isLoading: isLoading) {
                withAnimation(.easeInOut(duration: 1.5)) {
                    animatedScore = score
                }
                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsate = true
                }
            }
        )
        .onChange(of: score) { newScore in
            if !isLoading {
                withAnimation(.easeInOut(duration: 1.0)) {
                    animatedScore = newScore
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLoading ? "Loading score" : "Worth-It Score")
        .accessibilityValue(isLoading ? "" : "\(Int(score)) percent. \(accessibilityScoreDescription)")
        .accessibilityHint(isLoading ? "" : (showBreakdown ? "Tap to close score breakdown." : "Tap to view score breakdown."))
        .onAppear {
            if !isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !self.isLoading {
                        self.isAnimationCompleted = true
                        // Gentle success haptic when the score gauge finishes animating in
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                }
            }
        }
    }
}

// MARK: - Universal left-to-right swipe-back support
private struct SwipeBackModifier: ViewModifier {
    @EnvironmentObject var viewModel: MainViewModel
    let previousScreen: AnyView
    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            previousScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: -UIScreen.main.bounds.width / 2 + dragOffset / 2)

            content
                .offset(x: dragOffset)
                .opacity(Double(1.0 - min(dragOffset / 300, 1.0)))
                .scaleEffect(1.0 - min(dragOffset / 1000, 0.02))
        }
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onChanged { value in
                    if value.translation.width > 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width > 80 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)) {
                            viewModel.currentScreenOverride = nil
                            viewModel.viewState = .showingInitialOptions
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9, blendDuration: 0)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

extension View {
    /// Enables a left-to-right swipe gesture that returns the user to the initial screen.
    func enableSwipeBack(to previousScreen: AnyView) -> some View {
        self.modifier(SwipeBackModifier(previousScreen: previousScreen))
    }

    /// Enables a left-to-right swipe gesture that returns the user to the initial screen (default).
    /// Use this version to avoid rendering InitialScreen behind the current screen.
    func enableSwipeBack() -> some View {
        // Provide an empty view behind to avoid layout conflicts
        self.modifier(SwipeBackModifier(previousScreen: AnyView(EmptyView())))
    }
}

#if DEBUG
struct CommonUI_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Theme.Color.darkBackground.ignoresSafeArea()
            VStack(spacing: 50) {
                ScoreGaugeView(score: 88, isLoading: false, showBreakdown: .constant(false), isAnimationCompleted: .constant(false))
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
#endif

//
//  RootView.swift
//  WorthIt
//

import SwiftUI
import UIKit // For ceustomizing UINavigationBarAppearance
import UniformTypeIdentifiers
import StoreKit
import Combine

// Ensure these notifications are available in both app and share extension targets
extension Notification.Name {
    static let shareExtensionShouldDismissGlobal = Notification.Name("com.worthitai.shareExtensionShouldDismiss")
    static let shareExtensionOpenMainApp = Notification.Name("com.worthitai.shareExtensionOpenMainApp")
    static let shareExtensionOpenMainAppFailed = Notification.Name("com.worthitai.shareExtensionOpenMainAppFailed")
}



struct RootView: View {
    @State private var showAboutSheet = false
    @State private var showRecentSheet = false
    @State private var showShareExplanation = false // New state variable
    @AppStorage("hasOnboarded") var hasOnboarded: Bool = false // New AppStorage for onboarding
    private let onboardingDemoVideoURL = URL(string: "https://www.youtube.com/watch?v=5MgBikgcWnY")!
    @AppStorage("subscribe_banner_dismissed") private var subscribeBannerDismissed = false
    @State private var showDecisionCard: Bool = false

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        // Match the app's dark background
        appearance.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        
        // Provide a fully transparent bar-button appearance so SwiftUI buttons
        // inside the toolbar don't inherit the default gray capsule background.
        let clearButtonAppearance = UIBarButtonItemAppearance(style: .plain)
        let clearImage = UIImage()
        
        func stripBackground(_ state: UIBarButtonItemStateAppearance) {
            state.backgroundImage = clearImage
            state.backgroundImagePositionAdjustment = .zero
            // Critical: Set backgroundColor to clear to remove the grey capsule
            state.titleTextAttributes[.backgroundColor] = UIColor.clear
        }
        
        stripBackground(clearButtonAppearance.normal)
        stripBackground(clearButtonAppearance.highlighted)
        stripBackground(clearButtonAppearance.disabled)
        stripBackground(clearButtonAppearance.focused)
        
        appearance.buttonAppearance = clearButtonAppearance
        appearance.doneButtonAppearance = clearButtonAppearance
        appearance.backButtonAppearance = clearButtonAppearance
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    @EnvironmentObject var viewModel: MainViewModel
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    // Detect if running inside a Share Extension (.appex bundle)
    private var isRunningInExtension: Bool {
        let path = Bundle.main.bundlePath.lowercased()
        return path.contains(".appex")
    }

    // MARK: - Paste & Analyze state
    @StateObject private var startOptionsViewModel = StartOptionsViewModel()
    @FocusState private var isPasteFieldFocused: Bool
    
    // Wider, responsive content width: near edge on phones, capped on tablets
    private var mainContentMaxWidth: CGFloat { min(UIScreen.main.bounds.width - 24, 560) }

    // Sticky CTA removed per design; rely on the in-content Analyze button
    private var shouldShowStickyCTA: Bool { false }

    private func dismissKeyboard() {
        // Keep it extension‑safe: rely on FocusState to resign first responder
        isPasteFieldFocused = false
    }

    // Show Share button on RootView as soon as gauge/buttons are interactive
    private var shouldShowShareOverlay: Bool {
        viewModel.viewState == .showingInitialOptions &&
        (viewModel.scoreBreakdownDetails != nil || viewModel.worthItScore != nil)
    }

    @ViewBuilder
    private var shareOverlay: some View {
        if shouldShowShareOverlay {
            ShareOverlayButton()
                .environmentObject(viewModel)
                .zIndex(500)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var decisionCardOverlay: some View {
        if showDecisionCard,
           let card = viewModel.decisionCardModel,
           viewModel.activePaywall == nil {
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            showDecisionCard = false
                        }
                    }

                DecisionCardView(
                    model: card,
                    onPrimaryAction: {
                        viewModel.requestEssentials()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            showDecisionCard = false
                        }
                    },
                    onSecondaryAction: {
                        if let question = card.topQuestion {
                            viewModel.askTopQuestionIfAvailable(question)
                        } else {
                            viewModel.requestAskAnything()
                        }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            showDecisionCard = false
                        }
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            showDecisionCard = false
                        }
                    },
                    onBestMoment: {
                        openBestPart(for: card)
                    }
                )
                .frame(maxWidth: 540)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.keyboard)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(1200)
        }
    }

    // Reserved for future: handle direct URL pastes if needed

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if hasOnboarded || isRunningInExtension {
                    mainNavigationView
                } else {
                    OnboardingView(
                        callbacks: OnboardingCallbacks(
                            onSkip: handleOnboardingSkip,
                            onFocusPaste: handleOnboardingFocusPaste,
                            onShareSetup: handleOnboardingShareSetup,
                            onDemoPlayback: handleOnboardingDemoPlayback
                        )
                    )
                    .transition(.opacity)
                }
            }
        }
        .onReceive(viewModel.$shouldOpenManageSubscriptions) { shouldOpen in
            guard shouldOpen else { return }
            openURL(subscriptionManager.manageSubscriptionsURL())
            viewModel.consumeManageSubscriptionsDeepLinkRequest()
        }
    }

    private func handleOnboardingSkip() {
        hasOnboarded = true
    }

    private func handleOnboardingFocusPaste() {
        hasOnboarded = true
        DispatchQueue.main.async {
            isPasteFieldFocused = true
        }
    }

    private func handleOnboardingShareSetup() {
        hasOnboarded = true
        DispatchQueue.main.async {
            showShareExplanation = true
        }
    }

    private func handleOnboardingDemoPlayback() {
        hasOnboarded = true
        viewModel.processSharedURL(onboardingDemoVideoURL)
    }

    private var mainNavigationView: some View {
        NavigationView {
            ZStack {
                backgroundLayer
                activeScreen
                errorOverlay
                shareOverlay
                decisionCardOverlay
                paywallOverlay
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent() }
            .navigationBarBackButtonHidden(true)
            .preferredColorScheme(.dark)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showRecentSheet) {
            RecentVideosCenterModal(
                onDismiss: { showRecentSheet = false },
                onSelect: { item in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { @MainActor in
                        await viewModel.restoreFromCache(videoId: item.videoId)
                    }
                    showRecentSheet = false
                },
                borderGradient: standardBorderGradient
            )
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showShareExplanation) {
            ShareExplanationModal(onDismiss: { showShareExplanation = false }, borderGradient: standardBorderGradient)
        }
        .onAppear {
            Logger.shared.info("RootView appeared. Current ViewModel state: \(viewModel.viewState)", category: .ui)
        }
        .onReceive(subscriptionManager.$status) { status in
            if case .subscribed = status {
                subscribeBannerDismissed = false
            }
        }
        .onReceive(viewModel.$shouldPromptDecisionCard) { prompt in
            guard prompt,
                  viewModel.decisionCardModel != nil,
                  !viewModel.hasShownDecisionCardForCurrentVideo else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                showDecisionCard = true
            }
            viewModel.markDecisionCardShownIfNeeded()
            viewModel.consumeDecisionCardPrompt()
        }
        .onChange(of: viewModel.viewState) { newValue in
            if newValue == .processing { showDecisionCard = false }
            if newValue != .processing,
               viewModel.decisionCardModel != nil,
               !showDecisionCard,
               viewModel.activePaywall == nil,
               !viewModel.hasShownDecisionCardForCurrentVideo {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    showDecisionCard = true
                }
                viewModel.markDecisionCardShownIfNeeded()
            }
        }
        .onReceive(viewModel.$activePaywall) { paywall in
            if paywall != nil { showDecisionCard = false }
        }
        .onReceive(viewModel.$decisionCardModel) { model in
            if model == nil {
                showDecisionCard = false
            } else if !showDecisionCard,
                      viewModel.activePaywall == nil,
                      viewModel.viewState != .processing,
                      !viewModel.hasShownDecisionCardForCurrentVideo {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    showDecisionCard = true
                }
                viewModel.markDecisionCardShownIfNeeded()
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Theme.Color.darkBackground
            Rectangle()
                .fill(Theme.Gradient.neonGlow)
                .opacity(viewModel.viewState == .processing || viewModel.viewState == .idle ? 0.3 : 0.15)
                .animation(.easeInOut, value: viewModel.viewState)
            Theme.Gradient.vignette
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
    }

    private var activeScreen: some View {
        let content = currentViewForState(viewModel.viewState)
        return content
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .center)),
                    removal: .opacity.combined(with: .scale(scale: 1.05, anchor: .center))
                )
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.viewState)
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if let _ = viewModel.userFriendlyError {
            FocusErrorModalView(
                title: "We Couldn't Pull This Transcript",
                message: "YouTube isn't sharing a transcript for this video right now. Try a different video or check back in a bit.",
                primaryActionTitle: "Try Another Video",
                primaryAction: {
                    viewModel.clearCurrentError()
                    if isRunningInExtension {
                        Logger.shared.info("Error modal primary action inside Share Extension. Dismissing.", category: .ui)
                        NotificationCenter.default.post(name: .shareExtensionShouldDismissGlobal, object: nil)
                    } else {
                        viewModel.goToHome()
                    }
                },
                dismissAction: {
                    viewModel.clearCurrentError()
                    if isRunningInExtension {
                        Logger.shared.info("Error modal dismissed inside Share Extension. Posting dismiss notification.", category: .ui)
                        NotificationCenter.default.post(name: .shareExtensionShouldDismissGlobal, object: nil)
                    } else {
                        Logger.shared.info("Error modal dismissed in main app. Returning to home.", category: .ui)
                        viewModel.goToHome()
                    }
                }
            )
            .zIndex(2000)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var paywallOverlay: some View {
        if let paywallContext = viewModel.activePaywall {
            PaywallView(context: paywallContext, isInExtension: isRunningInExtension)
                .environmentObject(subscriptionManager)
                .environmentObject(viewModel)
                .transition(.opacity)
                .zIndex(2500)
        }
    }

    @ViewBuilder
    private func currentViewForState(_ state: ViewState) -> some View {
        switch state {
        case .idle:
            idleHomeView()
        case .processing:
            ProcessingView().environmentObject(viewModel)
        case .showingInitialOptions:
            InitialScreen().environmentObject(viewModel)
        case .showingEssentials:
            EssentialsScreen().environmentObject(viewModel)
        case .showingAskAnything:
            AskAnythingScreen().environmentObject(viewModel)
        case .error:
            // Show initial options behind the gentle banner if we have a user-facing error
            if viewModel.userFriendlyError != nil {
                InitialScreen().environmentObject(viewModel)
            } else {
                VStack(spacing: 15) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(Theme.Color.warning)
                    Text("An Unexpected Error Occurred")
                        .font(Theme.Font.headline)
                        .foregroundColor(Theme.Color.primaryText)
                    Text("Please try sharing the video again.")
                        .font(Theme.Font.body)
                        .foregroundColor(Theme.Color.secondaryText)
                }
                .padding()
            }
        }
    }

    // MARK: - Standard box style helpers
    /// Use the same cyan → blue → purple gradient as the app icon for borders.
    private var standardBorderGradient: LinearGradient {
        Theme.Gradient.brand(startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private func standardBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .blur(radius: 6)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(standardBorderGradient.opacity(0.55), lineWidth: 0.75)
                .blendMode(.overlay)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    // MARK: - Outer frame wrapper (surrounds all boxes subtly)
    @ViewBuilder
    private func outerFrameBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            // Removed .padding(18) from here; padding is now applied to the internal VStack to keep standardBox flexible
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.25))
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .blur(radius: 10)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(standardBorderGradient.opacity(0.45), lineWidth: 0.8)
                    .blendMode(.overlay)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 12, y: 5)
    }

    // Split idle home view to reduce type-checking complexity
    @ViewBuilder
    private func idleHomeView() -> some View {
        ScrollView {
            VStack(spacing: 14) {
                identityBox()
                    .onTapGesture { if isPasteFieldFocused { dismissKeyboard() } }
                    .frame(maxWidth: mainContentMaxWidth) // Apply max width
                
                outerFrameBox {
                    howItWorksBox()
                        .padding(18)
                }
                .frame(maxWidth: mainContentMaxWidth)

                outerFrameBox {
                    recentBox()
                        .padding(18)
                        .onTapGesture { if isPasteFieldFocused { dismissKeyboard() } }
                }
                .frame(maxWidth: mainContentMaxWidth)
                Spacer(minLength: 24)

                if shouldShowSubscribeBanner {
                    subscribeButton()
                        .frame(maxWidth: mainContentMaxWidth)
                } else if subscriptionManager.currentStatus == .inactive {
                    subscribeLinkButton()
                        .frame(maxWidth: mainContentMaxWidth)
                }

                // About lives at the end of content (no overlay)
                aboutButton()
                    .frame(maxWidth: mainContentMaxWidth)
            }
            .padding(.horizontal, 12) // Bring borders closer to edges for wider tap targets
            .padding(.top, 16)        // Tighter spacing from header to content
            .padding(.bottom, 26)     // Standard bottom padding (no sticky overlay)
        }
        // Allow drag-to-dismiss within the scroll content (does not interfere with text selection)
        .scrollDismissesKeyboard(.interactively)
        .environmentObject(viewModel)
        // Removed sticky CTA/overlay inset — About appears at end of scroll
    }

    // MARK: - Identity Box (Box 1)
    private var shouldShowSubscribeBanner: Bool {
        guard subscribeBannerDismissed == false else { return false }
        switch subscriptionManager.currentStatus {
        case .inactive:
            return true
        case .unknown, .subscribed:
            return false
        }
    }

    @ViewBuilder
    private func identityBox() -> some View {
        standardBox {
            HStack(alignment: .top, spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("WorthIt")
                        .font(Theme.Font.title3.weight(.bold))
                        .foregroundStyle(Theme.Gradient.appLogoText())
                    Text("AI‑powered insights, summaries, and Q&A for YouTube videos")
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.isUserSubscribed {
                        Text("Premium active")
                            .font(Theme.Font.captionBold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Theme.Gradient.appBluePurple.opacity(0.85))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                                    )
                            )
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - How It Works Box (Box 2)
    @ViewBuilder
    private func howItWorksBox() -> some View {
        standardBox {
            StartOptionsView(
                viewModel: startOptionsViewModel,
                borderGradient: standardBorderGradient,
                isRunningInExtension: isRunningInExtension,
                pasteFieldFocus: $isPasteFieldFocused,
                dismissKeyboard: dismissKeyboard
            )
        }
    }

    // MARK: - Recent Videos Box (Box 3)
    @ViewBuilder
    private func recentBox() -> some View {
        standardBox {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showRecentSheet = true } }) {
                    HStack(alignment: .center, spacing: 12) {
                        RecentVideosHeaderLabel()
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Color.secondaryText.opacity(0.88))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

            }
        }
    }

    private func openBestPart(for card: DecisionCardModel) {
        guard let videoId = viewModel.currentVideoID ?? viewModel.analysisResult?.videoId else { return }
        guard let start = card.bestStartSeconds, start > 0 else { return }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        var items = [URLQueryItem(name: "v", value: videoId)]
        items.append(URLQueryItem(name: "t", value: "\(start)s"))
        components.queryItems = items
        if let url = components.url {
            openURL(url)
        }
    }
    @ViewBuilder
    private func valueChipsSection() -> some View {
        HStack(spacing: 10) {
            TagChip(icon: "bolt.fill", text: "Smart Summaries")
            TagChip(icon: "gauge.with.dots.needle.bottom.50percent", text: "Worth‑It Score")
            TagChip(icon: "bubble.left.and.bubble.right.fill", text: "Ask Anything")
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func aboutButton() -> some View {
        Button {
            if isPasteFieldFocused { dismissKeyboard() }
            showAboutSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                Text("About WorthIt")
                    .font(Theme.Font.subheadline.weight(.medium))
            }
            .foregroundColor(Theme.Color.secondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Color.sectionBackground.opacity(0.45))
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.05))
                            .blur(radius: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.7)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(standardBorderGradient.opacity(0.55), lineWidth: 0.7)
                            .blendMode(.overlay)
                    )
            )
        }
        .padding(.top, 6)
    }

    private func subscribeButton() -> some View {
        SubscribePromoCard(onSubscribe: {
            if isPasteFieldFocused { dismissKeyboard() }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.requestManualPaywallPresentation()
        }, onDismiss: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            subscribeBannerDismissed = true
        })
        .padding(.top, 4)
    }

    private func subscribeLinkButton() -> some View {
        Button {
            if isPasteFieldFocused { dismissKeyboard() }
            viewModel.requestManualPaywallPresentation()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                Text("Unlock Premium")
                    .font(Theme.Font.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Gradient.appBluePurple.opacity(0.9))
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .blur(radius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.Gradient.appBluePurple.opacity(0.6), lineWidth: 0.9)
                            .blendMode(.overlay)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private struct SubscribePromoCard: View {
        let onSubscribe: () -> Void
        let onDismiss: () -> Void

        var body: some View {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unlock Premium")
                            .font(Theme.Font.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("Unlimited analyses")
                            .font(Theme.Font.caption2)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.Gradient.appBluePurple.opacity(0.85))
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .blur(radius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                        )
                )
                .shadow(color: Theme.Color.accent.opacity(0.12), radius: 6, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture(perform: onSubscribe)

                Button(role: .cancel, action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.9))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            WorthItToolbarTitle(
                opacity: viewModel.viewState == .idle ? 0.0 : (viewModel.viewState == .processing ? 0.7 : 1.0)
            )
            .animation(.easeInOut, value: viewModel.viewState)
        }
        // Hide Back on initial options when running inside the Share Extension
        if viewModel.viewState == .showingEssentials || viewModel.viewState == .showingAskAnything || (viewModel.viewState == .showingInitialOptions && !isRunningInExtension) {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if viewModel.viewState == .showingInitialOptions {
                        viewModel.goToHome()
                    } else {
                        viewModel.returnToInitialOptions()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(Theme.Font.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        // Show the close button only when running inside the Share Extension
        if isRunningInExtension {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Logger.shared.info("Close button tapped. Posting dismiss notification.", category: .ui)
                    // Use the globally defined notification name
                    NotificationCenter.default.post(name: .shareExtensionShouldDismissGlobal, object: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                }
            }
        }

    }
}

// Inline GentleBannerView to ensure inclusion in the main target
struct GentleBannerView: View {
    let title: String
    let message: String
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let dismissAction: () -> Void

    @State private var isVisible: Bool = true

    var body: some View {
        VStack {
            if isVisible {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Theme.Color.warning)
                        .font(.system(size: 22, weight: .semibold))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(Theme.Font.subheadline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        Text(message)
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Button(action: {
                                primaryAction()
                                isVisible = false
                            }) {
                                Text(primaryActionTitle)
                                    .font(Theme.Font.captionBold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.Color.accent)
                                    .cornerRadius(8)
                                    .accessibilityLabel(primaryActionTitle)
                            }

                            Button(action: {
                                isVisible = false
                                dismissAction()
                            }) {
                                Text("Dismiss")
                                    .font(Theme.Font.captionBold)
                                    .foregroundColor(Theme.Color.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.Color.sectionBackground.opacity(0.6))
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.top, 2)
                    }

                    Button(action: {
                        isVisible = false
                        dismissAction()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityLabel("Close banner")
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .background(Theme.Color.sectionBackground.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
                )
                .cornerRadius(14)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                .padding(.horizontal, 16)
                .transition(AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
            }
            Spacer(minLength: 0)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isVisible)
        .onAppear { isVisible = true }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Color.sectionBackground.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.Gradient.appBluePurple, lineWidth: 1)
                        .opacity(0.25)
                )
        )
    }
}

// RecentVideosCenterModal lives in a dedicated file for clarity.

// Centered modal error with blurred background and improved contrast
struct FocusErrorModalView: View {
    let title: String
    let message: String
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let dismissAction: () -> Void

    @State private var showContent: Bool = false

    var body: some View {
        ZStack {
            // Backdrop: subtle blur + dim to focus attention
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())
                .transition(.opacity)
                .onTapGesture {
                    // Tap outside to dismiss
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        showContent = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        dismissAction()
                    }
                }

            // Card
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Theme.Gradient.appBluePurple)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: Theme.Color.purple.opacity(0.35), radius: 16, y: 10)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(Theme.Font.title3.weight(.bold))
                        .foregroundColor(Theme.Color.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }

                VStack(spacing: 12) {
                    Button(action: primaryAction) {
                        Text(primaryActionTitle)
                            .font(Theme.Font.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.Gradient.appBluePurple)
                            )
                            .contentShape(Rectangle())
                    }

                    Button(action: dismissAction) {
                        Text("Dismiss")
                            .font(Theme.Font.subheadline.weight(.medium))
                            .foregroundColor(Theme.Color.primaryText)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.Color.sectionBackground.opacity(0.95))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 20) // Larger corner radius for the card
                    .fill(Theme.Color.sectionBackground.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20) // Match corner radius
                            .stroke(Theme.Color.accent.opacity(0.18), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 12) // Slightly larger, more pronounced shadow
            .padding(.horizontal, 24) // Increased horizontal padding
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.98)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showContent)
        }
        .onAppear {
            withAnimation { showContent = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

// Transparent paste overlay that uses PasteButton without showing UI
private struct InvisiblePasteOverlay: View {
    let isEnabled: Bool
    let onPaste: (String) -> Void
    let onFallbackTap: () -> Void

    @State private var didHandleTap = false

    var body: some View {
        Group {
            if isEnabled {
                // Full-area overlay that tries to paste URL or String; focuses field only if nothing pastes
                ZStack {
                    // Handle URL payloads (some apps copy as URL only)
                    PasteButton(payloadType: URL.self) { urls in
                        guard !didHandleTap, let url = urls.first else { return }
                        didHandleTap = true
                        onPaste(url.absoluteString)
                    }
                    .labelStyle(.iconOnly)
                    .tint(.clear)
                    .background(Color.clear)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    // Handle String payloads
                    PasteButton(payloadType: String.self) { items in
                        guard !didHandleTap, let raw = items.first else { return }
                        didHandleTap = true
                        onPaste(raw)
                    }
                    .labelStyle(.iconOnly)
                    .tint(.clear)
                    .background(Color.clear)
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.01) // fully invisible but keeps hit-testing
                .accessibilityHidden(true)
                .simultaneousGesture(TapGesture().onEnded {
                    // If neither PasteButton produced content, focus the field
                    if !didHandleTap { onFallbackTap() }
                })
            }
        }
    }
}

// MARK: - Decorative Chips
private struct TagChip: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(Theme.Font.caption)
        }
        .foregroundColor(Theme.Color.primaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

struct ErrorOverlayView: View {
    let title: String // Keep non-optional, provide default in RootView
    let message: String
    let canRetry: Bool
    var retryAction: (() -> Void)? = nil
    var dismissAction: (() -> Void)? = nil
    var videoIdForRetry: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea().onTapGesture { dismissAction?() }

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundColor(Theme.Color.orange)

                Text(title)
                    .font(Theme.Font.title2.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)

                Text(message)
        .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .lineSpacing(4)

                HStack(spacing: 15) {
                    if let da = dismissAction {
                         Button(canRetry && retryAction != nil ? "Cancel" : "Dismiss") {
                             da()
                         }
                         .buttonStyle(Theme.ButtonStyle.Secondary())
                         .frame(minWidth: 100)
                    }

                    if canRetry, let ra = retryAction {
                        Button("Try Again") {
                            ra()
                        }
                        .buttonStyle(Theme.ButtonStyle.Primary())
                        .frame(minWidth: 100)
                    }
                }
                .padding(.top, 10)
            }
            .padding(EdgeInsets(top: 30, leading: 25, bottom: 30, trailing: 25))
            .background(Theme.Color.sectionBackground.opacity(0.95))
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.4), radius: 15, y: 5)
            .padding(30)
        }
    }
}

// MARK: - Glow modifier for CTA when ready
private struct AnalyzeReadyGlow: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? Theme.Color.accent.opacity(0.25) : .clear, radius: isActive ? 10 : 0, y: 0)
            .shadow(color: isActive ? SwiftUI.Color.purple.opacity(0.18) : .clear, radius: isActive ? 12 : 0, y: 0)
            .animation(.easeInOut(duration: 0.25), value: isActive)
    }
}

struct ShareExplanationModal: View {
    let onDismiss: () -> Void
    let borderGradient: LinearGradient

    var body: some View {
        ZStack {
            // Dimmed backdrop with subtle blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())
                .onTapGesture { onDismiss() }

            // Card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(Theme.Font.subheadline.weight(.semibold))
                        }
                        .foregroundColor(Theme.Color.accent)
                    }
                    .accessibilityLabel("Dismiss Share Explanation")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(Theme.Color.accent)
                            Text("How to Share Videos")
                                .font(Theme.Font.title3.weight(.bold))
                                .foregroundStyle(Theme.Gradient.appLogoText())
                        }
                        Text("Get instant insights by sharing from YouTube")
                            .font(Theme.Font.subheadline)
                            .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                Divider().background(Theme.Color.accent.opacity(0.15)).padding(.horizontal, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        StepByStepGuide(steps: [
                        StepData(icon: "play.rectangle.fill", title: "Open a YouTube Video", description: "Pick any video you want to analyze."),
                        StepData(icon: "square.and.arrow.up", title: "Tap the Share Button", description: "Tap the Share arrow under the video. If YouTube shows its vertical overlay first, tap Share again to open the iOS Share Sheet, then tap More (…) if you still don't see WorthIt."),
                        StepData(icon: "sparkles", title: "Choose WorthIt", description: "Select WorthIt from the Share Sheet to send the link into WorthIt.")
                    ])

                        AddToFavoritesSection()
                    }
                    .padding(12) // Standardized padding
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.7)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 620)
            .background(Theme.Color.sectionBackground.opacity(0.95))
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(borderGradient, lineWidth: 1.0)
            )
            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
            .padding(24)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .preferredColorScheme(.dark)
    }
}

struct StepData: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

struct StepByStepGuide: View {
    let steps: [StepData]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("How to Use")
                .font(Theme.Font.headline.weight(.semibold))
                .foregroundColor(Theme.Color.primaryText)
                .padding(.bottom, 5)
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Theme.Color.accent)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(Theme.Font.subheadline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                        Text(step.description)
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

struct AddToFavoritesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If you don't see WorthIt")
                .font(Theme.Font.headline.weight(.semibold))
                .foregroundColor(Theme.Color.primaryText)
                .padding(.top, 10)
            Text("Add it to your Share Sheet once — then it will always appear.")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color.yellow)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Here’s how:")
                        .font(Theme.Font.subheadline.weight(.bold))
                        .foregroundColor(Theme.Color.primaryText)
                    Text("1. Swipe up on the Share Sheet and tap More (…) at the end of the horizontal row.")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                    Text("2. Tap \"Edit Actions…\", then tap the green + next to WorthIt to move it into Favorites and tap Done.")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                    Text("3. Optional: drag WorthIt to the top of Favorites so it always appears first.")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
        }
    }
}

struct OnboardingCallbacks {
    let onSkip: () -> Void
    let onFocusPaste: () -> Void
    let onShareSetup: () -> Void
    let onDemoPlayback: () -> Void
}

struct OnboardingView: View {
    let callbacks: OnboardingCallbacks

    @State private var currentPage = 0
    @State private var animateGlow = false

    private var deviceHeight: CGFloat { UIScreen.main.bounds.height }
    private var isCompactVertical: Bool { deviceHeight <= 736 }
    private var baseStackSpacing: CGFloat { isCompactVertical ? 16 : 20 }
    private var slideStackSpacing: CGFloat { isCompactVertical ? 22 : 28 }
    private var headerStackSpacing: CGFloat { isCompactVertical ? 8 : 12 }
    private var cardStackSpacing: CGFloat { isCompactVertical ? 10 : 12 }
    private var cardMinimumHeight: CGFloat { (isCompactVertical ? 96 : 104) * 0.8 }

    private func tabViewHeight(for availableHeight: CGFloat) -> CGFloat {
        let preferred = availableHeight * 0.68
        let base: CGFloat = isCompactVertical ? 540 : 620
        return max(min(base, preferred), 460)
    }

    private var slides: [OnboardingSlide] {
        [
                OnboardingSlide(
                id: 0,
                eyebrow: "Watch less, learn more",
                title: "Welcome to WorthIt",
                detail: "Skip the fluff—WorthIt surfaces the signal fast.",
                caption: nil,
                cards: [
                    OnboardingCard(icon: "bolt.fill", title: "Instant TL;DR", description: "Full summary in seconds.", action: .none),
                    OnboardingCard(icon: "sparkles", title: "Jump to the gems", description: "Highlights take you to key moments.", action: .none),
                    OnboardingCard(icon: "questionmark.circle", title: "Ask sharper questions", description: "Chat with the transcript and get instant answers.", action: .none)
                ]
            ),
            OnboardingSlide(
                id: 1,
                eyebrow: "Score · Essentials · Sentiment",
                title: "Value first, video later",
                detail: "Score, essentials, and sentiment show what to watch.",
                caption: nil,
                cards: [
                    OnboardingCard(icon: "gauge.medium", title: "WorthIt score decoded", description: "Instant 0–100 depth read.", action: .none),
                    OnboardingCard(icon: "list.bullet.rectangle", title: "Essentials on autopilot", description: "Storyline, highlights, and chapters for you.", action: .none),
                    OnboardingCard(icon: "bubble.left.and.bubble.right.fill", title: "Community vibe check", description: "Comment sentiment in one glance.", action: .none)
                ]
            ),
            OnboardingSlide(
                id: 2,
                eyebrow: "Start in seconds",
                title: "Start now",
                detail: "Fire up a demo, paste a link, or share from YouTube.",
                caption: nil,
                cards: [
                    OnboardingCard(icon: "play.rectangle.on.rectangle.fill", title: "Watch the instant demo", description: "See a real video compressed into the WorthIt experience.", action: .demoPlayback),
                    OnboardingCard(icon: "link.circle.fill", title: "Paste a YouTube link", description: "Drop any URL and WorthIt handles the rest.", action: .focusPaste),
                    OnboardingCard(icon: "square.and.arrow.up", title: "Share from the YouTube app", description: "Tap the Share arrow, then More (…) if you need to reveal WorthIt and pin it in Favorites.", action: .shareSetup)
                ]
            )
        ]
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaInsets = geometry.safeAreaInsets
            let availableHeight = max(geometry.size.height - (safeAreaInsets.top + safeAreaInsets.bottom), 520)
            let tabHeight = tabViewHeight(for: availableHeight)
            let contentWidth = min(geometry.size.width - 56, 620)

            ZStack {
                Theme.Color.darkBackground.ignoresSafeArea()
                Theme.Gradient.appBluePurple
                    .opacity(animateGlow ? 0.46 : 0.2)
                    .blur(radius: animateGlow ? 36 : 18)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: animateGlow)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: baseStackSpacing) {
                        HStack {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
                                .padding(.leading, 8)
                            Spacer()
                            Button(action: callbacks.onSkip) {
                                Text("Skip")
                                    .font(Theme.Font.subheadlineBold)
                                    .foregroundColor(Theme.Color.secondaryText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Theme.Color.sectionBackground.opacity(0.55))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Skip onboarding")
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, max(safeAreaInsets.top, 8))

                        if #available(iOS 17, *) {
                            TabView(selection: $currentPage) {
                                ForEach(slides) { slide in
                                    slideView(for: slide, contentWidth: contentWidth)
                                        .tag(slide.id)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .never))
                            .indexViewStyle(.page(backgroundDisplayMode: .never))
                            .frame(height: tabHeight)
                        } else {
                            TabView(selection: $currentPage) {
                                ForEach(slides) { slide in
                                    slideView(for: slide, contentWidth: contentWidth)
                                        .tag(slide.id)
                                }
                            }
                            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
                            .frame(height: tabHeight)
                        }

                        PageIndicator(total: slides.count, current: currentPage)
                            .padding(.top, 8)

                        VStack(spacing: isCompactVertical ? 10 : 12) {
                            Button(action: primaryButtonAction) {
                                HStack(spacing: 10) {
                                    Text(primaryButtonTitle)
                                    Image(systemName: currentPage == slides.count - 1 ? "arrow.right.circle.fill" : "arrow.right")
                                }
                                .font(Theme.Font.headlineBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(Theme.Gradient.appBluePurple)
                                .cornerRadius(16)
                                .shadow(color: Theme.Color.purple.opacity(0.35), radius: 14, y: 6)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 28)

                            Color.clear
                                .frame(height: 24)
                                .accessibilityHidden(true)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, max(safeAreaInsets.bottom, 16))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            animateGlow = true
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func slideView(for slide: OnboardingSlide, contentWidth: CGFloat) -> some View {
        VStack(spacing: slideStackSpacing) {
            VStack(spacing: headerStackSpacing) {
                if let eyebrow = slide.eyebrow {
                    Text(eyebrow.uppercased())
                        .font(Theme.Font.captionBold)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                        .tracking(1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(slide.title)
                    .font(Theme.Font.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = slide.detail {
                        Text(detail)
                            .font(Theme.Font.body)
                        .foregroundColor(Theme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let caption = slide.caption {
                    Text(caption)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                }
            }
            .padding(.top, isCompactVertical ? 4 : 8)

            VStack(spacing: cardStackSpacing) {
                ForEach(slide.cards) { card in
                OnboardingCardView(
                    card: card,
                    minHeight: cardMinimumHeight,
                    actionHandler: {
                        handleCardAction(card.action)
                    }
                )
            }
        }
        }
        .frame(maxWidth: contentWidth, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
    }

    private var primaryButtonTitle: String {
        currentPage == slides.count - 1 ? "Get started" : "Continue"
    }

    private func primaryButtonAction() {
        if currentPage == slides.count - 1 {
            callbacks.onFocusPaste()
        } else {
            withAnimation(.easeInOut(duration: 0.45)) {
                currentPage = min(currentPage + 1, slides.count - 1)
            }
        }
    }

    private func handleCardAction(_ action: OnboardingCard.Action) {
        switch action {
        case .none:
            break
        case .focusPaste:
            callbacks.onFocusPaste()
        case .shareSetup:
            callbacks.onShareSetup()
        case .demoPlayback:
            callbacks.onDemoPlayback()
        }
    }
}

private struct OnboardingSlide: Identifiable {
    let id: Int
    let eyebrow: String?
    let title: String
    let detail: String?
    let caption: String?
    let cards: [OnboardingCard]
}

private struct OnboardingCard: Identifiable {
    enum Action {
        case none
        case focusPaste
        case shareSetup
        case demoPlayback
    }

    let id = UUID()
    let icon: String
    let title: String
    let description: String?
    let action: Action
}

private struct OnboardingCardView: View {
    let card: OnboardingCard
    let minHeight: CGFloat
    let actionHandler: () -> Void

    private var cardBase: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: card.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Gradient.appBluePurple)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )

        VStack(alignment: .center, spacing: card.description == nil ? 0 : 4) {
            Text(card.title)
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let description = card.description {
                Text(description)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)

            Spacer()

            if card.action != .none {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.58))
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .blur(radius: 10)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.Gradient.appBluePurple.opacity(0.55), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
    }

    var body: some View {
        if card.action == .none {
            cardBase
        } else {
            Button(action: actionHandler) {
                cardBase
            }
            .buttonStyle(.plain)
        }
    }
}

struct PageIndicator: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                let isActive = index == current
                IndicatorDot(isActive: isActive)
                    .animation(.easeInOut(duration: 0.2), value: isActive)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Theme.Color.sectionBackground.opacity(0.6))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
}

private struct IndicatorDot: View {
    let isActive: Bool

    var body: some View {
        Capsule(style: .continuous)
            .fill(fillStyle)
            .frame(width: isActive ? 30 : 10, height: 6)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Theme.Gradient.appBluePurple, lineWidth: strokeWidth)
                    .opacity(strokeOpacity)
            )
    }

    private var fillStyle: AnyShapeStyle {
        if isActive {
            let gradient = LinearGradient(
                gradient: Gradient(colors: [Theme.Color.accent, Theme.Color.purple]),
                startPoint: .leading,
                endPoint: .trailing
            )
            return AnyShapeStyle(gradient)
        }
        return AnyShapeStyle(Theme.Color.sectionBackground.opacity(0.75))
    }

    private var strokeWidth: CGFloat { isActive ? 1.4 : 0.6 }
    private var strokeOpacity: Double { isActive ? 0.55 : 0.18 }
}

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static let previewSubscriptionManager = SubscriptionManager()

    static func createViewModel(state: ViewState, error: UserFriendlyError? = nil) -> MainViewModel {
        let apiManager = APIManager()
        let cacheManager = CacheManager.shared
        let vm = MainViewModel(
            apiManager: apiManager,
            cacheManager: cacheManager,
            subscriptionManager: previewSubscriptionManager,
            usageTracker: UsageTracker.shared
        )
        vm.viewState = state
        vm.userFriendlyError = error

        if state == .showingInitialOptions || state == .showingEssentials || state == .showingAskAnything {
            vm.currentVideoTitle = "AI Unveiled: A Deep Dive"
            // Assuming MainViewModel.currentVideoThumbnailURL is URL?
            vm.currentVideoThumbnailURL = URL(string: "https://i.ytimg.com/vi/TestId/sddefault.jpg")
            vm.worthItScore = 78
            vm.scoreBreakdownDetails = ScoreBreakdown(
                contentDepthScore: 0.75,
                commentSentimentScore: 0.82,
                hasComments: true,
                contentDepthRaw: 0.77,
                commentSentimentRaw: 0.40,
                finalScore: 78,
                videoTitle: "AI Unveiled",
                positiveCommentThemes: ["Very informative"],
                negativeCommentThemes: [],
                contentHighlights: ["Explains the 4-phase AI adoption ladder."],
                contentWatchouts: ["Glosses over implementation pitfalls."],
                commentHighlights: ["Fans love the clear metrics section."],
                commentWatchouts: ["Some say it repeats earlier content."],
                spamRatio: 0.12,
                commentsAnalyzed: 24
            )
// If a production fallback is needed, use the following:
// vm.analysisResult = ContentAnalysis(
//     summary: "",
//     longSummary: "",
//     contentDepthScore: 0.0,
//     timestamps: [],
//     takeaways: [],
//     gemsOfWisdom: [],
//     videoId: "TestId",
//     videoTitle: "AI Unveiled",
//     videoDurationSeconds: 0,
//     videoThumbnailUrl: "https://i.ytimg.com/vi/TestId/sddefault.jpg",
//     topThemes: [],
//     sentimentSummary: ""
// )
            vm.rawTranscript = "Sample transcript..."
        }
        if state == .showingEssentials {
            vm.essentialsCommentAnalysis = CommentInsights(
                videoId: "TestId",
                viewerTips: ["Keep captions on for faster skim."],
                overallCommentSentimentScore: 0.6,
                contentDepthScore: 0.7,
                suggestedQuestions: ["Best first step?", "Tools needed?", "Pitfalls to avoid?"]
            )
        }
        if state == .showingAskAnything {
            vm.qaMessages = [ChatMessage(content: "Ask me!", isUser: false)]
        }
        return vm
    }

    static var previews: some View {
        Group {
            AnyView(RootView()
                .environmentObject(createViewModel(state: .idle))
                .environmentObject(previewSubscriptionManager))
                .previewDisplayName("Idle State") // This should now compile

            AnyView(RootView()
                .environmentObject(createViewModel(state: .processing))
                .environmentObject(previewSubscriptionManager))
                .previewDisplayName("Processing State")

            AnyView(RootView()
                .environmentObject(createViewModel(state: .showingInitialOptions))
                .environmentObject(previewSubscriptionManager))
                .previewDisplayName("Initial Options")

            AnyView(RootView()
                .environmentObject(createViewModel(state: .showingEssentials))
                .environmentObject(previewSubscriptionManager))
                .previewDisplayName("Essentials Screen")

            AnyView(RootView()
                .environmentObject(createViewModel(state: .showingAskAnything))
                .environmentObject(previewSubscriptionManager))
                .previewDisplayName("Ask Anything Screen")

            AnyView(
                ErrorOverlayView(
                    title: "Error Occurred",
                    message: "The video analysis failed due to a network issue. Please check your connection.",
                    canRetry: true,
                    retryAction: nil,
                    dismissAction: nil,
                    videoIdForRetry: nil
                )
            )
                .previewDisplayName("Error State (Retry)")

            AnyView(
                ErrorOverlayView(
                    title: "Error Occurred",
                    message: "This video format is not supported.",
                    canRetry: false,
                    retryAction: nil,
                    dismissAction: nil,
                    videoIdForRetry: nil
                )
            )
                .previewDisplayName("Error State (No Retry)")
        }
    }
}
#endif

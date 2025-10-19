//
//  RootView.swift
//  WorthIt
//

import SwiftUI
import UIKit // For ceustomizing UINavigationBarAppearance
import LinkPresentation
import UniformTypeIdentifiers
import StoreKit
import Combine

// Ensure this is at the top level (outside any struct/class)
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
    @AppStorage("subscribe_banner_dismissed") private var subscribeBannerDismissed = false
    @State private var timeSavedDismissWorkItem: DispatchWorkItem?
    @State private var timeSavedDisplayDuration: Double = 0

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        // Match the app's dark background
        appearance.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
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
    @State private var inputURLText: String = ""
    @State private var inputError: String? = nil
    @FocusState private var isPasteFieldFocused: Bool
    @State private var isURLValid: Bool = false
    @State private var validationHint: String? = nil
    @State private var previewData: TinyPreviewData? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var showHowItWorksDetails: Bool = false

    // Unified control sizing and animated CTA border
    private let controlHeight: CGFloat = 44
    @State private var ctaPulse: Bool = false
    
    // Wider, responsive content width: near edge on phones, capped on tablets
    private var mainContentMaxWidth: CGFloat { min(UIScreen.main.bounds.width - 24, 560) }

    // Sticky CTA removed per design; rely on the in-content Analyze button
    private var shouldShowStickyCTA: Bool { false }

    private func dismissKeyboard() {
        // Keep it extension‑safe: rely on FocusState to resign first responder
        isPasteFieldFocused = false
    }

    private func isValidVideoId(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 11 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return trimmed.rangeOfCharacter(from: allowed.inverted) == nil
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
    private var timeSavedToastOverlay: some View {
        if let event = viewModel.latestTimeSavedEvent {
            GeometryReader { proxy in
                TimeSavedBannerView(
                    event: event,
                    safeAreaInsets: proxy.safeAreaInsets,
                    minutesFormatter: formattedSingleMinutes,
                    totalFormatter: formattedCumulativeMinutes,
                    displayDuration: timeSavedDisplayDuration
                ) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        viewModel.clearTimeSavedEvent()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
            }
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
            .zIndex(750)
        }
    }

    private func resolveVideoURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let urlFromText = URLParser.firstSupportedVideoURL(in: trimmed) {
            return urlFromText
        }
        if isValidVideoId(trimmed) {
            return URL(string: "https://www.youtube.com/watch?v=\(trimmed)")
        }
        return nil
    }

    private var isAnalyzeEnabled: Bool {
        resolveVideoURL(from: inputURLText) != nil && viewModel.viewState != .processing
    }

    private func analyzePastedInput() {
        // Avoid starting a new analysis while one is in progress
        guard viewModel.viewState != .processing else { return }
        guard let url = resolveVideoURL(from: inputURLText) else {
            inputError = "Please paste a valid YouTube link or 11‑character video ID."
            return
        }
        inputError = nil
        isPasteFieldFocused = false
        Logger.shared.info("Manual analyze triggered from main app UI: \(url.absoluteString)", category: .ui)
        AnalyticsService.shared.logEvent("manual_paste_analyze", parameters: ["source": "main_app", "url": url.absoluteString])
        viewModel.processSharedURL(url)
    }

    private func handlePastedText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URLParser.firstSupportedVideoURL(in: trimmed) ?? (
            isValidVideoId(trimmed) ? URL(string: "https://www.youtube.com/watch?v=\(trimmed)") : nil
        ) {
            inputURLText = url.absoluteString
            inputError = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            analyzePastedInput()
        } else {
            // Not a valid YouTube link or ID — focus field for manual edit
            isPasteFieldFocused = true
        }
    }

    // Reserved for future: handle direct URL pastes if needed

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if hasOnboarded || isRunningInExtension {
                    mainNavigationView
                } else {
                    OnboardingView(hasOnboarded: $hasOnboarded)
                        .transition(.opacity)
                }
            }

            timeSavedToastOverlay
        }
        .onReceive(viewModel.$shouldOpenManageSubscriptions) { shouldOpen in
            guard shouldOpen else { return }
            openURL(subscriptionManager.manageSubscriptionsURL())
            viewModel.consumeManageSubscriptionsDeepLinkRequest()
        }
    }

    private var mainNavigationView: some View {
        NavigationView {
            ZStack {
                backgroundLayer
                activeScreen
                errorOverlay
                recentModal
                shareOverlay
                paywallOverlay
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent() }
            .toolbarBackground(Theme.Color.darkBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showShareExplanation) {
            ShareExplanationModal(onDismiss: { showShareExplanation = false }, borderGradient: standardBorderGradient)
        }
        .onAppear {
            Logger.shared.info("RootView appeared. Current ViewModel state: \(viewModel.viewState)", category: .ui)
            if !isRunningInExtension {
                viewModel.syncTimeSavedMetricsFromSharedDefaults()
            }
            scheduleTimeSavedToastDismissal()
        }
        .onReceive(subscriptionManager.$status) { status in
            if case .subscribed = status {
                subscribeBannerDismissed = false
            }
        }
        .onChange(of: viewModel.latestTimeSavedEvent?.id) { _ in
            scheduleTimeSavedToastDismissal()
        }
        .onDisappear {
            timeSavedDismissWorkItem?.cancel()
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Theme.Color.darkBackground
            Rectangle()
                .fill(Theme.Gradient.neonGlow)
                .opacity(viewModel.viewState == .processing || viewModel.viewState == .idle ? 0.3 : 0.15)
                .animation(.easeInOut, value: viewModel.viewState)
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
    private var recentModal: some View {
        if showRecentSheet {
            RecentVideosCenterModal(
                onDismiss: { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showRecentSheet = false } },
                onSelect: { item in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { @MainActor in
                        await viewModel.restoreFromCache(videoId: item.videoId)
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showRecentSheet = false }
                },
                borderGradient: standardBorderGradient
            )
            .zIndex(1500)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var paywallOverlay: some View {
        if let paywallContext = viewModel.activePaywall {
            InlinePaywallView(context: paywallContext, isInExtension: isRunningInExtension)
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
    private var standardBorderGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func standardBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.55))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .blur(radius: 6)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(standardBorderGradient.opacity(0.55), lineWidth: 0.8)
                .blendMode(.overlay)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    // MARK: - Outer frame wrapper (surrounds all boxes subtly)
    @ViewBuilder
    private func outerFrameBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            // Removed .padding(18) from here; padding is now applied to the internal VStack to keep standardBox flexible
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.25))
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .blur(radius: 10)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(standardBorderGradient.opacity(0.45), lineWidth: 0.9)
                    .blendMode(.overlay)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 14, y: 6)
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
                    Text("WorthIt.AI")
                        .font(Theme.Font.title3.weight(.bold))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.Color.accent)
                Text("Start here")
                    .font(Theme.Font.title3.weight(.bold))
                    .foregroundColor(Theme.Color.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Primary actions reordered: Paste first, then Share (per request)
            if !isRunningInExtension {
                pasteAnalyzeSection(borderGradient: standardBorderGradient)
            }
            // Centered "or" separator between Paste and Share
            HStack {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                Text("or")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            }
            .padding(.vertical, 6)
            sharePill(borderGradient: standardBorderGradient)

            // Progressive disclosure placed below Share
            DisclosureGroup(isExpanded: $showHowItWorksDetails) {
                howItWorksSection(includeHeader: false)
                    .padding(.top, 6)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(Theme.Color.accent)
                    Text("See how")
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.92))
                    Spacer()
                }
            }
            .tint(Theme.Color.secondaryText.opacity(0.88))
        }
    }

    // MARK: - Recent Videos Box (Box 3)
    @ViewBuilder
    private func recentBox() -> some View {
        standardBox {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showRecentSheet = true } }) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recent Videos")
                                .font(Theme.Font.title3.weight(.bold))
                                .foregroundColor(Theme.Color.primaryText)
                            Text("Jump back into your latest WorthIt.AI insights")
                                .font(Theme.Font.subheadline)
                                .foregroundColor(Theme.Color.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Color.secondaryText.opacity(0.88))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if viewModel.cumulativeTimeSavedMinutes > 0 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Color.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Minutes stolen from YouTube")
                                .font(Theme.Font.subheadline)
                                .foregroundColor(Theme.Color.primaryText)
                            Text("\(viewModel.uniqueVideosSummarized) videos • \(formattedCumulativeMinutes(viewModel.cumulativeTimeSavedMinutes)) saved")
                                .font(Theme.Font.caption)
                                .foregroundColor(Theme.Color.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func formattedSingleMinutes(_ value: Double) -> String {
        if value >= 10 {
            return "\(Int(value.rounded())) min"
        } else if value >= 1 {
            return String(format: "%.1f min", value)
        } else {
            return String(format: "%.0f sec", value * 60.0)
        }
    }

    private func formattedCumulativeMinutes(_ value: Double) -> String {
        if value >= 120 {
            let hours = Int(value) / 60
            let minutes = Int(value.rounded()) % 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        } else if value >= 60 {
            return String(format: "%.1f h", value / 60.0)
        } else if value >= 10 {
            return "\(Int(value.rounded())) min"
        } else if value >= 1 {
            return String(format: "%.1f min", value)
        } else {
            return String(format: "%.0f sec", value * 60.0)
        }
    }

    private func scheduleTimeSavedToastDismissal() {
        if timeSavedDismissWorkItem != nil {
            Logger.shared.debug("Cancelling pending time-saved banner dismissal", category: .timeSavings)
        }
        timeSavedDismissWorkItem?.cancel()
        guard viewModel.latestTimeSavedEvent != nil else {
            timeSavedDisplayDuration = 0
            return
        }
        let displayDelay: TimeInterval = (viewModel.latestTimeSavedEvent?.alreadyCounted ?? false) ? 3.0 : 4.5
        timeSavedDisplayDuration = displayDelay
        Logger.shared.debug(
            "Scheduling time-saved banner auto-dismiss",
            category: .timeSavings,
            extra: ["delay": displayDelay]
        )
        let workItem = DispatchWorkItem { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            Logger.shared.debug("Auto-dismissing time-saved banner after delay", category: .timeSavings)
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.clearTimeSavedEvent()
            }
        }
        timeSavedDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDelay, execute: workItem)
    }

    @ViewBuilder
    private func sharePill(borderGradient: LinearGradient) -> some View {
        // Non-tappable info row (avoid false affordance)
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
            Text("Share from the YouTube app")
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.Color.accent.opacity(0.25), lineWidth: 0.5))
        }
        .font(Theme.Font.subheadline)
        .foregroundColor(Theme.Color.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.35))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .blur(radius: 5)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderGradient.opacity(0.6), lineWidth: 0.7)
                .blendMode(.overlay)
        )
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }

    @ViewBuilder
    private func pasteAnalyzeSection(borderGradient: LinearGradient) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Color.sectionBackground.opacity(0.32))
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .blur(radius: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
                    )
                    .overlay(
                        // Subtle focus glow that does not affect layout height
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Theme.Color.accent.opacity(isPasteFieldFocused ? 0.25 : 0.0), lineWidth: 2)
                            .animation(.easeInOut(duration: 0.2), value: isPasteFieldFocused)
                    )

                HStack(spacing: 8) {
                    TextField("Paste a YouTube link here", text: $inputURLText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.primaryText)
                        .submitLabel(.go)
                        .focused($isPasteFieldFocused)
                        .onSubmit { if isAnalyzeEnabled { analyzeWithHaptic() } }
                        .frame(maxHeight: .infinity)

                    if !inputURLText.isEmpty {
                        Button(action: { inputURLText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: pasteFromClipboard) {
                            Text("Paste")
                                .font(Theme.Font.captionBold)
                                .foregroundColor(Theme.Color.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Theme.Color.sectionBackground.opacity(0.4))
                                        .overlay(
                                            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                                        )
                                )
                                .overlay(
                                    Capsule().stroke(borderGradient.opacity(0.6), lineWidth: 0.8)
                                        .blendMode(.overlay)
                                )
                        }
                        .accessibilityLabel("Paste from Clipboard")
                    }
                }
                .padding(.horizontal, 10)
            }
            // Lock height so it never "shrinks" on focus or paste
            .frame(maxWidth: .infinity, minHeight: controlHeight, maxHeight: controlHeight)
            .onChange(of: inputURLText) { newVal in
                updateValidation(for: newVal)
                schedulePreview(for: newVal)
            }

            if let hint = validationHint, !isURLValid, !inputURLText.isEmpty {
                Text(hint)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }

            if let preview = previewData, isURLValid {
                TinyLinkPreview(preview: preview)
            }

            // In‑content CTA (primary). Lights up when input is valid.
            HStack {
                Spacer(minLength: 0)
                Button(action: analyzeWithHaptic) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Analyze Video")
                            .font(Theme.Font.subheadline)
                    }
                    .frame(maxWidth: .infinity, minHeight: controlHeight)
                    .foregroundColor(Theme.Color.primaryText)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.Color.sectionBackground.opacity(0.85))
                    )
                    .overlay(
                        // Base border
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderGradient, lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if isAnalyzeEnabled {
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .opacity(ctaPulse ? 0.4 : 0.2)
                                .mask(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(style: StrokeStyle(lineWidth: ctaPulse ? 3.5 : 2.0))
                                )
                                .scaleEffect(ctaPulse ? 1.02 : 1.0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.6, blendDuration: 0).repeatForever(autoreverses: true), value: ctaPulse)
                                .onAppear { ctaPulse = true }
                            }
                        }
                    )
                    .shadow(color: Theme.Color.accent.opacity(ctaPulse ? 0.25 : 0.1), radius: ctaPulse ? 8 : 4, y: ctaPulse ? 4 : 2)
                    .opacity(isAnalyzeEnabled ? 1.0 : 0.5)
                }
                .disabled(!isAnalyzeEnabled)
                Spacer(minLength: 0)
            }
        }
    }

    private func pasteFromClipboard() {
        guard viewModel.viewState != .processing else { return }
        if let url = UIPasteboard.general.url {
            inputURLText = url.absoluteString
        } else if let s = UIPasteboard.general.string {
            inputURLText = s
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // No chip; keep experience subtle
    }

    private func analyzeWithHaptic() {
        guard isAnalyzeEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        analyzePastedInput()
    }

    private func updateValidation(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isURLValid = false
            validationHint = nil
            return
        }
        if resolveVideoURL(from: trimmed) != nil {
            isURLValid = true
            validationHint = nil
        } else {
            isURLValid = false
            validationHint = "We need a YouTube link like https://www.youtube.com/watch?v=abc123 or a video ID."
        }
    }

    private func schedulePreview(for input: String) {
        previewTask?.cancel()
        guard let url = resolveVideoURL(from: input) else { previewData = nil; return }
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
            if Task.isCancelled { return }
            if let meta = await fetchLPMetadata(for: url) {
                let title = meta.title ?? url.host ?? ""
                var image: UIImage? = nil
                if let provider = meta.iconProvider { image = try? await provider.loadImage() }
                if image == nil, let thumb = meta.imageProvider { image = try? await thumb.loadImage() }
                await MainActor.run { previewData = TinyPreviewData(title: title, image: image) }
            }
        }
    }

    private func fetchLPMetadata(for url: URL) async -> LPLinkMetadata? {
        await withCheckedContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.timeout = 3
            provider.startFetchingMetadata(for: url) { metadata, _ in
                continuation.resume(returning: metadata)
            }
        }
    }

    @ViewBuilder
    private func howItWorksSection(includeHeader: Bool = true) -> some View {
        VStack(spacing: 14) {
            if includeHeader {
                Text("How It Works")
                    .font(Theme.Font.headline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
            }
            VStack(spacing: 10) {
                StepGuideRow(number: "1", icon: "play.rectangle.fill", title: "Open a YouTube video", description: "Pick any video you want")
                StepGuideRow(number: "2", icon: "square.and.arrow.up", title: "Tap Share - More (...)", description: "In the YouTube app or browser")
                StepGuideRow(number: "3", icon: "sparkles", title: "Choose WorthIt.AI", description: "Get instant insights")
            }

            // If you don't see WorthIt.AI in Share, make it visible once
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(Theme.Color.accent)
                    Text("Don’t see WorthIt.AI in Share?")
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.primaryText)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "1.circle.fill").foregroundColor(Theme.Color.accent)
                        Text("In the Share sheet, scroll to the end and tap More (…)")
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "2.circle.fill").foregroundColor(Theme.Color.accent)
                        Text("Tap ‘Edit Actions…’, enable WorthIt.AI, then tap Done")
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "3.circle.fill").foregroundColor(Theme.Color.accent)
                        Text("Optional: Add to Favorites (⭐) to keep it at the top")
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.Color.sectionBackground.opacity(0.45))
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.05))
                            .blur(radius: 6)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.Gradient.appBluePurple.opacity(0.45), lineWidth: 0.9)
                    .blendMode(.overlay)
            )
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
                Text("About WorthIt.AI")
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Subscribe to Premium")
                        .font(Theme.Font.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    Text("Unlock unlimited breakdowns and faster insights.")
                        .font(Theme.Font.caption)
                        .foregroundColor(.white.opacity(0.85))

                    Text("You’re on the free tier today. Premium removes the daily limit and speeds up processing.")
                        .font(Theme.Font.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.Gradient.appBluePurple.opacity(0.85))
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .blur(radius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                        )
                )
                .shadow(color: Theme.Color.accent.opacity(0.35), radius: 10, y: 5)
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
            HStack(spacing: 8) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                Text("WorthIt.AI")
                    .font(Theme.Font.toolbarTitle)
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 1)
            }
            .opacity(viewModel.viewState == .idle ? 0.0 : (viewModel.viewState == .processing ? 0.7 : 1.0))
            .animation(.easeInOut, value: viewModel.viewState)
        }
        // Hide Back on initial options when running inside the Share Extension
        if viewModel.viewState == .showingEssentials || viewModel.viewState == .showingAskAnything || (viewModel.viewState == .showingInitialOptions && !isRunningInExtension) {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if viewModel.viewState == .showingInitialOptions {
                        viewModel.goToHome()
                    } else {
                        viewModel.returnToInitialOptions()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 17))
                    }
                }
                .foregroundColor(Theme.Color.primaryText)
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
    }
}

struct StepGuideRow: View {
    let number: String
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Step number badge (subtle, on-brand)
            ZStack {
                Circle()
                    .fill(Theme.Color.sectionBackground.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().stroke(Theme.Gradient.appBluePurple, lineWidth: 1).opacity(0.6)
                    )
                Text(number)
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.accent)
                    .accessibilityLabel("Step \(number)")
            }
            
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Theme.Color.accent)
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
                Text(description)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .lineLimit(2)
            }
            
            Spacer()
        }
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

// MARK: - Recent Videos Center Modal (no database)
struct RecentVideosCenterModal: View {
    let onDismiss: () -> Void
    let onSelect: (CacheManager.RecentAnalysisItem) -> Void
    @State private var items: [CacheManager.RecentAnalysisItem] = []
    @State private var showContent = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    let borderGradient: LinearGradient

    private var backdropOpacity: Double {
        let alpha = 0.35 - Double(min(dragOffset, 160)) / 600.0
        return max(0.05, alpha)
    }

    private func dismiss(after delay: TimeInterval = 0.18, haptic: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        if haptic {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if !haptic {
            dragOffset = 0
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            onDismiss()
        }
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop with subtle blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(backdropOpacity).ignoresSafeArea())
                .onTapGesture {
                    dismiss(haptic: false)
                }

            // Card
            VStack(spacing: 18) {
                HStack {
                    Button(action: { dismiss(haptic: false) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                                .font(Theme.Font.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Theme.Gradient.appBluePurple)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.Color.sectionBackground.opacity(0.72))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.Color.accent.opacity(0.28), lineWidth: 1)
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)

                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Theme.Gradient.appBluePurple)
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                                            .shadow(color: Theme.Color.accent.opacity(0.45), radius: 12, y: 6)
                                    )

                                Image(systemName: "play.rectangle.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Recent Videos")
                                    .font(Theme.Font.title3.weight(.bold))
                                    .foregroundColor(Theme.Color.primaryText)

                                Text("Jump back into your latest WorthIt insights.")
                                    .font(Theme.Font.subheadline)
                                    .foregroundColor(Theme.Color.secondaryText.opacity(0.92))
                            }

                            Spacer()

                            Capsule()
                                .fill(Theme.Gradient.appBluePurple.opacity(0.65))
                                .overlay(
                                    Capsule()
                                        .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
                                )
                                .frame(width: 82, height: 30)
                                .overlay(
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.92))
                                        Text("WorthIt")
                                            .font(Theme.Font.caption.weight(.semibold))
                                            .foregroundColor(.white.opacity(0.92))
                                    }
                                )
                        }

                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.Color.sectionBackground.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
                            )
                            .frame(height: 3)
                            .overlay(
                                LinearGradient(colors: [Theme.Color.accent.opacity(0.8), Theme.Color.purple.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 3)
                                    .cornerRadius(999)
                            )
                            .opacity(0.9)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    Divider()
                        .background(Theme.Color.accent.opacity(0.15))
                        .padding(.horizontal, 24)

                    if items.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "sparkles.tv.fill")
                                .font(.system(size: 48))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Theme.Color.accent, Theme.Color.secondaryText)
                            Text("No recent insights yet!")
                                .font(Theme.Font.headline.weight(.semibold))
                                .foregroundColor(Theme.Color.primaryText)
                            Text("Share a YouTube video or paste a link to get started with WorthIt.AI.")
                                .font(Theme.Font.subheadline)
                                .foregroundColor(Theme.Color.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .padding(.vertical, 48)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(items) { item in
                                    Button(action: { onSelect(item) }) {
                                        let title = cleanedTitle(for: item)
                                        let formattedDate = item.modifiedAt.formatted(date: .abbreviated, time: .omitted)

                                        HStack(alignment: .center, spacing: 18) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(Theme.Color.sectionBackground.opacity(0.85))
                                                AsyncImage(url: item.thumbnailURL) { phase in
                                                    switch phase {
                                                    case .empty:
                                                        ProgressView()
                                                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.Color.accent))
                                                    case .success(let image):
                                                        image
                                                            .resizable()
                                                            .scaledToFill()
                                                    case .failure:
                                                        Image(systemName: "film.fill")
                                                            .resizable()
                                                            .scaledToFit()
                                                            .padding(16)
                                                            .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                                                    @unknown default:
                                                        Color.clear
                                                    }
                                                }
                                            }
                                            .frame(width: 128, height: 78)
                                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(borderGradient, lineWidth: 1)
                                                    .opacity(0.9)
                                            )
                                            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)

                                            VStack(alignment: .leading, spacing: 10) {
                                                if !title.isEmpty {
                                                    Text(title)
                                                        .font(Theme.Font.subheadlineBold)
                                                        .foregroundColor(Theme.Color.primaryText)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.leading)
                                                }

                                                HStack(spacing: 10) {
                                                    Label(formattedDate, systemImage: "calendar")
                                                        .labelStyle(.titleAndIcon)
                                                        .font(Theme.Font.caption)
                                                        .foregroundColor(Theme.Color.secondaryText.opacity(0.95))
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 6)
                                                        .background(
                                                            Capsule()
                                                                .fill(Theme.Color.sectionBackground.opacity(0.7))
                                                        )
                                                        .overlay(
                                                            Capsule()
                                                                .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
                                                        )

                                                    Spacer(minLength: 0)

                                                    if let score = displayedScore(for: item) {
                                                        scoreBadge(for: score)
                                                    }
                                                }
                                            }

                                            Spacer(minLength: 0)

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                                                .padding(12)
                                                .background(
                                                    Circle()
                                                        .fill(Theme.Color.sectionBackground.opacity(0.75))
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
                                                )
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 18)
                                        .background(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [Theme.Color.sectionBackground.opacity(0.92), Theme.Color.sectionBackground.opacity(0.65)]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                        .strokeBorder(borderGradient.opacity(0.55), lineWidth: 1)
                                                )
                                                .shadow(color: .black.opacity(0.25), radius: 22, y: 14)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 26)
                        }
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.97))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(borderGradient, lineWidth: 1.0)
                )
                .shadow(color: .black.opacity(0.34), radius: 20, y: 14)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 18)
            .offset(x: dragOffset)
            .opacity(showContent ? 1 : 0)
            .scaleEffect(showContent ? 1 : 0.98)
            .onAppear {
                dragOffset = 0
                isDismissing = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showContent = true }
                Task { @MainActor in
                    items = await CacheManager.shared.listRecentAnalyses()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        guard !isDismissing else { return }
                        let translation = value.translation.width
                        if translation > 0 {
                            dragOffset = translation
                        }
                    }
                    .onEnded { value in
                        guard !isDismissing else { return }
                        if value.translation.width > 90 {
                            let target = UIScreen.main.bounds.width * 0.65
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                dragOffset = target
                            }
                            dismiss(haptic: true)
                        } else {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .preferredColorScheme(.dark)
    }

    private func displayedScore(for item: CacheManager.RecentAnalysisItem) -> Double? {
        if let score = item.finalScore {
            return score
        }
        // Fallback when there are no comment insights cached yet – mirror the transcript-only heuristic.
        return 60
    }

    private func scoreBadge(for score: Double) -> some View {
        let clampedScore = max(0, min(score, 100))
        let formattedScore = "\(Int(clampedScore))%"

        return ZStack {
            Circle()
                .fill(Theme.Color.sectionBackground.opacity(0.88))
                .shadow(color: Theme.Color.accent.opacity(0.35), radius: 12, y: 6)

            Circle()
                .strokeBorder(scoreGradient(for: clampedScore), lineWidth: 2)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                        .blur(radius: 0.5)
                )

            VStack(spacing: 4) {
                Text(formattedScore)
                    .font(Theme.Font.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)

                Text("Score")
                    .font(Theme.Font.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                    .tracking(0.5)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 66, height: 66)
    }

    private func scoreGradient(for score: Double) -> LinearGradient {
        let colors: [Color]
        switch score {
        case 80...:
            colors = [Theme.Color.accent, Theme.Color.purple]
        case 60..<80:
            colors = [Theme.Color.orange.opacity(0.9), Theme.Color.accent]
        case 40..<60:
            colors = [Theme.Color.warning.opacity(0.85), Theme.Color.orange.opacity(0.8)]
        default:
            colors = [Theme.Color.error.opacity(0.85), Theme.Color.orange.opacity(0.75)]
        }

        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func cleanedTitle(for item: CacheManager.RecentAnalysisItem) -> String {
        let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeId = t.count == 11 && t.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
        return looksLikeId ? "" : t
    }
}

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

// MARK: - Tiny Link Preview
struct TinyPreviewData {
    let title: String
    let image: UIImage?
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
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                                .font(Theme.Font.subheadline.weight(.medium))
                        }
                        .foregroundColor(Theme.Color.accent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.Color.sectionBackground.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(borderGradient.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .accessibilityLabel("Dismiss Share Explanation") // Added accessibility label
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
                                .foregroundStyle(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
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
                            StepData(icon: "square.and.arrow.up", title: "Tap the Share Button", description: "Tap the Share icon (arrow)."),
                            StepData(icon: "sparkles", title: "Choose WorthIt.AI", description: "Select WorthIt.AI from the share sheet.")
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
            Text("If you don’t see WorthIt.AI")
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
                    Text("1. In the share sheet, scroll right and tap More (…)")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                    Text("2. Find WorthIt.AI in the list")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                    Text("3. Tap Edit (top-right) → add WorthIt.AI to Favourites")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                    Text("4. Optional: drag it to the top so it appears first")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
        }
    }
}

struct TinyLinkPreview: View {
    let preview: TinyPreviewData

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let img = preview.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "link.circle.fill")
                        .resizable()
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(preview.title)
                .font(Theme.Font.subheadline)
                .foregroundColor(Theme.Color.primaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Color.sectionBackground.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
        )
    }
}

struct OnboardingView: View {
    @Binding var hasOnboarded: Bool
    @State private var showGlow: Bool = false
    @State private var pageIndex: Int = 0

    private var backgroundGradient: LinearGradient {
        switch pageIndex {
        case 0: return Theme.Gradient.accent
        case 1: return Theme.Gradient.appBluePurple
        case 2: return Theme.Gradient.tealGreen
        case 3: return Theme.Gradient.accent
        default: return Theme.Gradient.appBluePurple
        }
    }

    var body: some View {
        ZStack {
            // Rich background that matches the app's accent look
            Theme.Color.darkBackground.ignoresSafeArea()
            backgroundGradient
                .opacity(showGlow ? 0.5 : 0.25)
                .blur(radius: showGlow ? 30 : 18)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: showGlow)

            VStack(spacing: 0) {
                // Top bar with Skip
                HStack {
                    Spacer()
                    Button("Skip") { hasOnboarded = true }
                        .font(Theme.Font.subheadlineBold)
                        .foregroundColor(Theme.Color.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.Color.sectionBackground.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
                        )
                        .padding([.top, .trailing], 20)
                        .accessibilityLabel("Skip onboarding")
                }

                TabView(selection: $pageIndex) {
                    // 0 — Welcome with app logo
                    OnboardingPage(
                        icon: "sparkles.tv.fill",
                        logoImageName: "AppLogo",
                        title: "Welcome to WorthIt.AI",
                        description: "Smarter summaries, key insights, and Q&A in seconds.",
                        accentColor: Theme.Color.accent,
                        highlights: [
                            "Smart summaries in seconds",
                            "Key insights you can act on",
                            "Ask anything about the video"
                        ]
                    ).tag(0)

                    // 1 — Share from YouTube (blue)
                    OnboardingPage(
                        icon: "square.and.arrow.up",
                        title: "Share from YouTube",
                        description: "In YouTube, tap Share → WorthIt.AI to analyze instantly.",
                        accentColor: Color.blue,
                        highlights: [
                            "No copy/paste needed",
                            "Works from the YouTube app",
                            "Opens results in WorthIt.AI"
                        ]
                    ).tag(1)

                    // 2 — Paste a Link (green)
                    OnboardingPage(
                        icon: "doc.on.clipboard.fill",
                        title: "Paste a Link",
                        description: "Prefer to paste? Drop any YouTube URL to get results.",
                        accentColor: Theme.Color.success,
                        highlights: [
                            "Paste a link from anywhere",
                            "See summary and insights",
                            "Follow up with Q&A"
                        ]
                    ).tag(2)

                    // 3 — Worth‑It Score with gauge
                    OnboardingScorePage().tag(3)

                    // 4 — Ready
                    OnboardingPage(
                        icon: "hand.thumbsup.fill",
                        title: "Ready to Go",
                        description: "Let’s dive into smarter video learning.",
                        accentColor: Color.green,
                        showDismissButton: true,
                        onDismiss: { hasOnboarded = true }
                    ).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .padding(.bottom, 8)

                // Footer note for trust
                Text("We only process public video data you choose to analyze.")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                    .padding(.bottom, 20)
                    .padding(.horizontal)
            }
        }
        .onAppear { showGlow = true }
        .preferredColorScheme(.dark)
    }
}

struct OnboardingPage: View {
    let icon: String
    var logoImageName: String? = nil
    let title: String
    let description: String
    let accentColor: Color
    var highlights: [String] = []
    var showDismissButton: Bool = false
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 26) {
            // Feature card matching app cards style
            VStack(spacing: 18) {
                ZStack {
                    if let logo = logoImageName {
                        // Show only the logo — no background circles or borders
                        Image(logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .shadow(color: accentColor.opacity(0.35), radius: 6, y: 3)
                    } else {
                        // Icon variant with soft circular backdrop
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 96, height: 96)
                            .overlay(Circle().stroke(accentColor.opacity(0.35), lineWidth: 1))

                        Image(systemName: icon)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(accentColor)
                            .shadow(color: accentColor.opacity(0.5), radius: 8, y: 4)
                            .scaleEffect(1.0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: icon)
                    }
                }

                Text(title)
                    .font(Theme.Font.title)
                    .foregroundColor(Theme.Color.primaryText)
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                if !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(highlights, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(accentColor)
                                Text(item)
                                    .font(Theme.Font.caption)
                                    .foregroundColor(Theme.Color.secondaryText)
                            }
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.Color.sectionBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(accentColor.opacity(0.25), lineWidth: 1)
                    )
            )
            .shadow(color: accentColor.opacity(0.15), radius: 10, y: 6)

            if showDismissButton {
                Button(action: { onDismiss?() }) {
                    HStack(spacing: 10) {
                        Text("Get Started")
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(Theme.Font.title3)
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .background(Theme.Gradient.appBluePurple)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1)
                    )
                    .cornerRadius(18)
                    .shadow(color: Theme.Color.accent.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityLabel("Get Started with WorthIt.AI")
            }
        }
        .padding(28)
        .accessibilityElement(children: .combine)
    }
}

// Dedicated page explaining the Worth‑It Score with the existing gauge
struct OnboardingScorePage: View {
    @State private var dummyShow = false
    @State private var animDone = false

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.Color.accent.opacity(0.15))
                        .frame(width: 96, height: 96)
                        .overlay(Circle().stroke(Theme.Color.accent.opacity(0.35), lineWidth: 1))

                    // Gauge preview with a representative score
                    ScoreGaugeView(
                        score: 88,
                        isLoading: false,
                        showBreakdown: $dummyShow,
                        isAnimationCompleted: $animDone
                    )
                    .frame(width: 72, height: 72)
                }

                Text("Worth‑It Score")
                    .font(Theme.Font.title)
                    .foregroundColor(Theme.Color.primaryText)
                    .multilineTextAlignment(.center)

                Text("A quick signal of how valuable a video is for learning.")
                    .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles").foregroundColor(Theme.Color.accent)
                        Text("Focuses on substance: we analyze the talk, not the fluff.")
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.2.fill").foregroundColor(Theme.Color.accent)
                        Text("Blends video content quality with community sentiment.")
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "gauge.high").foregroundColor(Theme.Color.accent)
                        Text("One clear 0–100 score — green is great, yellow is decent.")
                            .font(Theme.Font.caption)
                            .foregroundColor(Theme.Color.secondaryText)
                    }
                }
                .frame(maxWidth: 520)
                .padding(.top, 4)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.Color.sectionBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 1)
                    )
            )
            .shadow(color: Theme.Color.accent.opacity(0.15), radius: 10, y: 6)
        }
        .padding(28)
    }
}

private struct TimeSavedBannerView: View {
    let event: TimeSavedEvent
    let safeAreaInsets: EdgeInsets
    let minutesFormatter: (Double) -> String
    let totalFormatter: (Double) -> String
    let displayDuration: Double
    var onTapDismiss: () -> Void

    @State private var animateIn = false
    @State private var dragOffset: CGFloat = 0
    @State private var progress: CGFloat = 0

    private let bannerHeight: CGFloat = 52
    private let milestoneThresholds: [Double] = [30, 60, 120, 180, 300, 480, 720, 960, 1200, 1440, 1800, 2400, 3000]

    private var iconName: String {
        event.alreadyCounted ? "clock.arrow.circlepath" : "sparkles"
    }

    private var titleText: String {
        if let context = event.context {
            return context.headline
        }
        if event.alreadyCounted {
            return "Time already counted"
        }
        let variants = [
            "Minutes reclaimed",
            "Screen time saved",
            "Progress on your focus streak",
            "Time back in your day",
            "You just got minutes back"
        ]
        let index = Int(event.id.uuidString.hashValue.magnitude) % variants.count
        return variants[index]
    }

    private var subtitleText: String {
        let total = totalFormatter(event.cumulativeMinutes)
        let totalLine = "Total saved: \(total)"
        if let context = event.context {
            if context.detail.isEmpty {
                return totalLine
            } else {
                return "\(context.detail) • \(totalLine)"
            }
        }
        let minutes = minutesFormatter(event.minutes)
        let base = event.alreadyCounted
            ? "Already logged \(minutes) saved • \(totalLine)"
            : "Saved \(minutes) from YouTube • \(totalLine)"
        if let nextLine = nextMilestoneLine {
            return "\(base) • \(nextLine)"
        }
        return base
    }

    private var nextMilestoneLine: String? {
        guard !event.alreadyCounted else { return nil }
        guard let nextGoal = milestoneThresholds.first(where: { $0 > event.cumulativeMinutes }) else { return nil }
        let remaining = max(nextGoal - event.cumulativeMinutes, 0)
        guard remaining >= 0.25 else { return nil }
        let proximity = remaining / nextGoal
        guard proximity <= 0.35 else { return nil }
        let formattedRemaining = minutesFormatter(remaining)
        let targetLabel = formatMilestoneTarget(nextGoal)
        return "\(formattedRemaining) until your next milestone (\(targetLabel))"
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let translation = value.translation.height
                dragOffset = translation < 0 ? translation : translation / 4
            }
            .onEnded { value in
                if value.translation.height < -45 {
                    onTapDismiss()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                }
            }
    }

    var body: some View {
        let topInset = safeAreaInsets.top

        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInset)
                .allowsHitTesting(false)

            bannerCard
                .frame(minHeight: bannerHeight, alignment: .center)
                .frame(maxWidth: .infinity)
                .offset(y: animateIn ? dragOffset : -(bannerHeight + 20))
                .opacity(animateIn ? 1 : 0)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.82, blendDuration: 0.15)) {
                animateIn = true
            }
            startProgressAnimation()
        }
        .onChange(of: event.id) { _ in
            startProgressAnimation()
        }
        .onDisappear {
            progress = 0
        }
    }

    private func formatMilestoneTarget(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            if hours == floor(hours) {
                return "\(Int(hours))h"
            }
            return String(format: "%.1fh", hours)
        }
        if minutes >= 10 {
            return "\(Int(minutes.rounded())) min"
        }
        if minutes >= 1 {
            return String(format: "%.1f min", minutes)
        }
        return String(format: "%.0f sec", minutes * 60.0)
    }

    private var bannerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.Color.sectionBackground.opacity(0.55))
                    .frame(width: 34, height: 34)

                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.Color.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(Theme.Color.primaryText)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.92))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button(action: onTapDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.Color.secondaryText)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss time stolen banner")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(width: geo.size.width * progress, height: 2)
                    .opacity(displayDuration > 0 ? 1 : 0)
            }
        }
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1),
            alignment: .bottom
        )
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTapDismiss() }
        .highPriorityGesture(dismissDrag)
        .allowsHitTesting(true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time stolen notification")
        .accessibilityHint("Dismiss to return to the video summary")
    }

    private func startProgressAnimation() {
        progress = 0
        guard displayDuration > 0 else { return }
        withAnimation(.linear(duration: displayDuration)) {
            progress = 1
        }
    }
}


// Async helper to load UIImage from an NSItemProvider if available
private extension NSItemProvider {
    func loadImage() async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            if self.canLoadObject(ofClass: UIImage.self) {
                self.loadObject(ofClass: UIImage.self) { obj, err in
                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }
                    continuation.resume(returning: obj as? UIImage)
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
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
            vm.scoreBreakdownDetails = ScoreBreakdown(contentDepthScore: 0.75, commentSentimentScore: 0.82, hasComments: true, contentDepthRaw: 0.77, commentSentimentRaw: 0.40, finalScore: 78, videoTitle: "AI Unveiled", positiveCommentThemes: ["Very informative"], negativeCommentThemes: [])
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
                
                overallCommentSentimentScore: 0.6
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



// MARK: - Inline Paywall View

fileprivate struct InlinePaywallView: View {
    let context: MainViewModel.PaywallContext
    let isInExtension: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack {
                    Spacer(minLength: 60)

                    PaywallCard(context: context, isInExtension: isInExtension)
                        .padding(.horizontal, 24)

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .transition(.opacity)
    }
}

import SwiftUI
import StoreKit
import Foundation
import Combine

struct PaywallCard: View {
    @EnvironmentObject private var viewModel: MainViewModel
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.openURL) private var openURL

    let context: MainViewModel.PaywallContext
    let isInExtension: Bool

    @State private var selectedPlanID: String?
    @State private var purchaseInFlight: String?
    @State private var isRestoring = false
    @State private var infoMessage: String?
    @State private var infoMessageColor: Color = Theme.Color.secondaryText
    @State private var showLoadingSkeleton = true
    @State private var extensionLaunchState: ShareExtensionLaunchState = .idle

    private var productsStillLoading: Bool {
        !isInExtension && subscriptionManager.isLoadingProducts && subscriptionManager.products.isEmpty
    }

    private var annualProduct: Product? {
        subscriptionManager.products.first { $0.id == AppConstants.subscriptionProductAnnualID }
    }

    private var weeklyProduct: Product? {
        subscriptionManager.products.first { $0.id == AppConstants.subscriptionProductWeeklyID }
    }

    private var annualSavingsPercent: Int? {
        guard
            let annual = annualProduct,
            let weekly = weeklyProduct
        else {
            return nil
        }

        let annualPrice = NSDecimalNumber(decimal: annual.price).doubleValue
        let weeklyPrice = NSDecimalNumber(decimal: weekly.price).doubleValue
        guard annualPrice > 0, weeklyPrice > 0 else {
            return nil
        }

        let annualIfWeekly = weeklyPrice * 52
        guard annualIfWeekly > 0 else {
            return nil
        }

        let savingsRatio = 1 - (annualPrice / annualIfWeekly)
        let percentage = Int((savingsRatio * 100).rounded())
        return percentage > 0 ? percentage : nil
    }

    private var annualBadgeText: String? {
        guard let percent = annualSavingsPercent else { return nil }
        return "\(percent)% OFF"
    }

    private var plans: [PaywallPlanOption] {
        let annual = annualProduct
        let weekly = weeklyProduct

        let options: [PaywallPlanOption] = [
            PaywallPlanOption(
                id: AppConstants.subscriptionProductAnnualID,
                title: "Annual",
                priceText: annual?.displayPrice ?? "Loading…",
                detailText: "Best value • Billed yearly",
                trailingBadge: annualBadgeText,
                product: annual,
                isRecommended: true,
                footnote: nil
            ),
            PaywallPlanOption(
                id: AppConstants.subscriptionProductWeeklyID,
                title: "Weekly",
                priceText: weekly?.displayPrice ?? "Loading…",
                detailText: "Cancel anytime",
                trailingBadge: nil,
                product: weekly,
                isRecommended: false,
                footnote: "Stay flexible. Cancel anytime."
            )
        ]
        return options
    }

    private var selectedPlan: PaywallPlanOption? {
        if let current = selectedPlanID, let match = plans.first(where: { $0.id == current }) {
            return match
        }
        return plans.first
    }

    private var productAvailabilityMessage: String? {
        guard subscriptionManager.hasAttemptedProductLoad, !subscriptionManager.isLoadingProducts else {
            return nil
        }

        if subscriptionManager.lastProductLoadError != nil {
            return "We couldn't load the plans right now. Please try again later."
        }

        if subscriptionManager.products.isEmpty {
            return "We couldn't load the subscription plans right now. Please try again shortly."
        }

        let expected = Set(AppConstants.subscriptionProductIDs)
        let loaded = Set(subscriptionManager.products.map { $0.id })
        let missing = expected.subtracting(loaded)
        guard !missing.isEmpty else { return nil }

        return "Some subscription options are temporarily unavailable. You can still subscribe to any plans shown below."
    }

    private var maxCardWidth: CGFloat { isInExtension ? 320 : 340 }

    var body: some View {
        VStack(spacing: isInExtension ? 16 : 18) {
            header
            momentumSection
            usageSummary

            premiumBenefits

            if isInExtension {
                shareExtensionActions
            } else {
                mainExperienceStack
            }
        }
        .frame(maxWidth: maxCardWidth)
        .padding(.vertical, isInExtension ? 18 : 22)
        .padding(.horizontal, isInExtension ? 18 : 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.78))
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .blur(radius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.Color.accent.opacity(0.2), lineWidth: 1)
                        .blendMode(.overlay)
                )
                .shadow(color: Theme.Color.darkBackground.opacity(0.4), radius: 24, y: 18)
        )
        .onAppear {
            if isInExtension {
                infoMessage = nil
                triggerExtensionAutoLaunchIfNeeded()
            } else if selectedPlanID == nil, let defaultPlan = plans.first?.id {
                selectedPlanID = defaultPlan
            }
            showLoadingSkeleton = productsStillLoading || (!isInExtension && subscriptionManager.products.isEmpty)
            viewModel.paywallPresented(reason: context.reason)
            Task {
                await subscriptionManager.refreshProducts()
                await subscriptionManager.refreshEntitlement()
            }
        }
        .onChange(of: subscriptionManager.products) { _ in
            guard !isInExtension else { return }
            if selectedPlanID == nil, let defaultPlan = plans.first?.id {
                selectedPlanID = defaultPlan
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                showLoadingSkeleton = productsStillLoading
            }
        }
        .onChange(of: subscriptionManager.isLoadingProducts) { _ in
            guard !isInExtension else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showLoadingSkeleton = productsStillLoading
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shareExtensionOpenMainAppFailed)) { _ in
            guard isInExtension else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                extensionLaunchState = .failed
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, y: 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text("WorthIt Premium")
                        .font(Theme.Font.title3.weight(.semibold))
                        .foregroundColor(Theme.Color.primaryText)
                    Text("Unlimited breakdowns. Zero waiting for tomorrow.")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                }

                Spacer()
            }
        }
    }

    private var momentumSection: some View {
        let metrics = context.metrics
        return VStack(alignment: .leading, spacing: 6) {
            Text("Momentum snapshot")
                .font(Theme.Font.captionBold)
                .foregroundColor(Theme.Color.secondaryText)

            HStack(spacing: 10) {
                momentumTile(title: "Minutes saved", value: formattedMinutes(metrics.totalMinutesSaved))
                momentumTile(title: "Day streak", value: "\(metrics.activeStreakDays)")
            }
        }
        .padding(12)
        .background(cardFill(opacity: 0.65, cornerRadius: 20))
        .overlay(cardStroke(cornerRadius: 20))
    }

    private func momentumTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
            Text(value)
                .font(Theme.Font.title3.weight(.semibold))
                .foregroundColor(Theme.Color.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(cardFill(opacity: 0.38, cornerRadius: 14))
        .overlay(cardStroke(cornerRadius: 14))
    }

    private func formattedMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = minutes / 60.0
            return hours >= 10 ? String(format: "%.0f hr", hours) : String(format: "%.1f hr", hours)
        }
        return String(format: "%.0f min", minutes)
    }

    private var usageSummary: some View {
        let snapshot = context.usageSnapshot
        let dailyLimit = max(snapshot.limit, AppConstants.dailyFreeAnalysisLimit)
        let used = min(snapshot.count, dailyLimit)
        let remaining = max(0, dailyLimit - used)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Free plan • \(dailyLimit) analyses/day")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.secondaryText)
                Spacer()
                Text("\(remaining) left today")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.primaryText)
            }

            ProgressView(value: Double(used), total: Double(dailyLimit))
                .progressViewStyle(LinearProgressViewStyle(tint: Theme.Color.accent))

            Text("Premium removes the cap so you never wait for tomorrow.")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)

        }
        .padding(isInExtension ? 12 : 14)
        .background(cardFill(cornerRadius: isInExtension ? 16 : 18))
        .overlay(cardStroke(cornerRadius: isInExtension ? 16 : 18))
    }

    private var premiumBenefits: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "infinity")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("WorthIt Premium")
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(Theme.Color.primaryText)
                Text("Unlimited breakdowns. Zero waiting for tomorrow.")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var mainExperienceStack: some View {
        VStack(spacing: 18) {
            planSelector
            if let message = infoMessage {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundColor(infoMessageColor)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            mainAppActions
            legalLinks
        }
    }

    private var planSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick your plan")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)

            if showLoadingSkeleton {
                planSkeletonPlaceholder
            } else {
                ForEach(plans) { plan in
                    Button(action: { select(plan) }) {
                        planSummaryContent(plan: plan, showSelection: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(plan.product == nil)
                }
                if let message = productAvailabilityMessage {
                    Text(message)
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 6)
                }
            }
        }
    }

    private var planSkeletonPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<AppConstants.subscriptionProductIDs.count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.6))
                        .frame(width: 110, height: 14)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.6))
                        .frame(width: 160, height: 22)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.45))
                        .frame(width: 140, height: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(cardFill(opacity: 0.46, cornerRadius: 18))
                .overlay(cardStroke(cornerRadius: 18))
                .redacted(reason: .placeholder)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showLoadingSkeleton)
    }

    @ViewBuilder
    private var selectedPlanSummary: some View {
        if let plan = selectedPlan {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected plan")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.secondaryText)
                Text("\(plan.title) • \(plan.priceText)")
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planSummaryContent(plan: PaywallPlanOption, showSelection: Bool) -> some View {
        let isSelected = selectedPlan?.id == plan.id
        let priceLoaded = plan.product != nil
        let strokeStyle: AnyShapeStyle = isSelected
            ? AnyShapeStyle(Theme.Gradient.appBluePurple)
            : AnyShapeStyle(Color.white.opacity(0.1))

        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        if plan.isRecommended {
                            Text("POPULAR")
                                .font(Theme.Font.captionBold)
                                .foregroundColor(Theme.Color.accent)
                                .textCase(.uppercase)
                        }
                        Text(plan.title)
                            .font(Theme.Font.subheadline.weight(.semibold))
                            .foregroundColor(Theme.Color.primaryText)
                    }
                    Spacer()
                    if let trailing = plan.trailingBadge {
                        Text(trailing)
                            .font(Theme.Font.captionBold)
                            .foregroundColor(Theme.Color.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.Color.accent.opacity(0.18)))
                    }
                }

                priceLabel(for: plan, loaded: priceLoaded)

                Text(plan.detailText)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote = plan.footnote {
                    Text(footnote)
                        .font(Theme.Font.caption2)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if showSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.Color.accent : Theme.Color.secondaryText.opacity(0.5))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(cardFill(opacity: isSelected ? 0.6 : 0.42, cornerRadius: 18))
        .overlay(
            cardStroke(
                strokeStyle,
                lineWidth: isSelected ? 1.6 : 0.7,
                cornerRadius: 18
            )
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.Color.accent.opacity(0.45), lineWidth: 0.5)
                    .blendMode(.screen)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private func priceLabel(for plan: PaywallPlanOption, loaded: Bool) -> some View {
        Group {
            if loaded {
                Text(plan.priceText)
            } else if plan.product == nil, plan.priceText.lowercased() != "loading…" {
                Text(plan.priceText)
                    .foregroundColor(Theme.Color.secondaryText)
            } else {
                Text(plan.placeholderPrice)
                    .redacted(reason: .placeholder)
            }
        }
        .font(Theme.Font.title3.weight(.bold))
        .foregroundColor(Theme.Color.primaryText)
        .animation(.easeInOut(duration: 0.2), value: loaded)
    }

    private var primaryButtonSkeleton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )

            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Color.secondaryText))
                Text("Loading pricing…")
                    .font(Theme.Font.body.weight(.semibold))
                    .foregroundColor(Theme.Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .animation(.easeInOut(duration: 0.2), value: showLoadingSkeleton)
    }

    private var mainAppActions: some View {
        VStack(spacing: 16) {
            if showLoadingSkeleton {
                primaryButtonSkeleton
            } else {
                Button(action: { attemptPurchase(source: .primary) }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.Gradient.appBluePurple)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                                    .blendMode(.screen)
                            )

                        if purchaseInFlight != nil {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Continue with \(selectedPlan?.title ?? "plan")")
                                .font(Theme.Font.body.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .disabled(purchaseInFlight != nil || selectedPlan?.product == nil)
                .animation(.easeInOut(duration: 0.2), value: purchaseInFlight)
            }

            selectedPlanSummary

            Button(action: dismissTapped) {
                Text("Maybe later")
                    .font(Theme.Font.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.Color.secondaryText)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
                    )
            )
        }
    }

    private var legalLinks: some View {
        VStack(spacing: 12) {
            Text("By upgrading you agree to our Terms of Use and Privacy Policy.")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                legalLinkButton(title: "Privacy Policy", url: AppConstants.privacyPolicyURL)
                Text("•")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.5))
                legalLinkButton(title: "Terms of Use", url: AppConstants.termsOfUseURL)
            }
            .frame(maxWidth: .infinity)

            Button(action: restorePurchases) {
                HStack(spacing: 6) {
                    if isRestoring {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.Color.accent))
                    }
                    Text(isRestoring ? "Restoring purchases…" : "Restore purchases")
                        .font(Theme.Font.captionBold)
                        .foregroundColor(Theme.Color.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isRestoring)
        }
        .padding(.top, 4)
    }

    private func legalLinkButton(title: String, url: URL) -> some View {
        Button(action: { openURL(url) }) {
            Text(title)
                .font(Theme.Font.captionBold)
                .foregroundColor(Theme.Color.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private var shareExtensionActions: some View {
        VStack(spacing: 18) {
            shareExtensionStatusRow
            Button(action: manuallyOpenWorthIt) {
                HStack(spacing: 10) {
                    if extensionLaunchState == .launching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(extensionLaunchState == .failed ? "Try opening WorthIt again" : "Open WorthIt")
                        .font(Theme.Font.body.weight(.semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Gradient.appBluePurple)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
                            .blendMode(.screen)
                    )
            )
            .disabled(extensionLaunchState == .launching)
            .opacity(extensionLaunchState == .launching ? 0.65 : 1.0)

            Button(action: dismissTapped) {
                Text("Close share sheet")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.secondaryText)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private func shareExtensionStatusText() -> (text: String, color: Color) {
        switch extensionLaunchState {
        case .launching:
            return ("Opening WorthIt…", Theme.Color.primaryText)
        case .failed:
            return ("Couldn't open automatically. Tap below or try again.", Theme.Color.warning)
        case .idle:
            return ("Open WorthIt to finish upgrading to Premium.", Theme.Color.primaryText)
        }
    }

    @ViewBuilder
    private var shareExtensionStatusRow: some View {
        let status = shareExtensionStatusText()
        HStack(spacing: 12) {
            if extensionLaunchState == .launching {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Color.accent))
            } else {
                Image(systemName: extensionLaunchState == .failed ? "exclamationmark.triangle.fill" : "sparkles")
                    .foregroundColor(extensionLaunchState == .failed ? Theme.Color.warning : Theme.Color.accent)
            }
            Text(status.text)
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(status.color)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func manuallyOpenWorthIt() {
        guard extensionLaunchState != .launching else { return }
        extensionLaunchState = .launching
        openWorthItFromExtension()
    }

    private func openWorthItFromExtension() {
        if let url = URL(string: AppConstants.subscriptionDeepLink) {
            NotificationCenter.default.post(name: .shareExtensionOpenMainApp, object: url)
        } else {
            NotificationCenter.default.post(name: .shareExtensionOpenMainApp, object: nil)
        }
    }

    private func select(_ plan: PaywallPlanOption) {
        selectedPlanID = plan.id
        infoMessage = nil
        infoMessageColor = Theme.Color.secondaryText
        viewModel.paywallPlanSelected(productId: plan.id)
    }

    private func attemptPurchase(source: PurchaseSource = .primary) {
        guard let plan = selectedPlan else {
            infoMessage = "Select a plan to continue."
            infoMessageColor = Theme.Color.warning
            return
        }
        guard let product = plan.product else {
            infoMessage = "Pricing is still loading. Please try again in a moment."
            infoMessageColor = Theme.Color.warning
            return
        }
        guard purchaseInFlight == nil else { return }

        purchaseInFlight = plan.id
        infoMessage = nil
        infoMessageColor = Theme.Color.secondaryText
        viewModel.paywallCheckoutStarted(productId: plan.id, source: source.analyticsValue, isTrial: false)
        viewModel.paywallPurchaseTapped(productId: plan.id)

        Task { @MainActor in
            let outcome = await subscriptionManager.purchase(product)
            purchaseInFlight = nil
            switch outcome {
            case .success(let productId):
                viewModel.paywallPurchaseSucceeded(productId: productId)
            case .userCancelled:
                infoMessage = "Purchase cancelled."
                infoMessageColor = Theme.Color.secondaryText
                viewModel.paywallPurchaseCancelled(productId: plan.id)
            case .pending:
                infoMessage = "Purchase pending. We'll unlock Premium once it's confirmed."
                infoMessageColor = Theme.Color.secondaryText
            case .failed:
                infoMessage = "Something went wrong. Please try again."
                infoMessageColor = Theme.Color.warning
                viewModel.paywallPurchaseFailed(productId: plan.id)
            }
        }
    }

    private func restorePurchases() {
        guard !isRestoring else { return }
        isRestoring = true
        infoMessage = nil
        infoMessageColor = Theme.Color.secondaryText
        viewModel.paywallRestoreTapped()

        Task { @MainActor in
            do {
                try await subscriptionManager.restorePurchases()
                infoMessage = "Restored purchases."
                infoMessageColor = Theme.Color.secondaryText
            } catch {
                infoMessage = "Could not restore purchases."
                infoMessageColor = Theme.Color.warning
                Logger.shared.error("Failed to restore purchases: \(error.localizedDescription)", category: .purchase, error: error)
            }
            isRestoring = false
        }
    }

    private func dismissTapped() {
        viewModel.paywallMaybeLaterTapped()
        dismissPaywallAfterRescue()
    }

    private func dismissPaywallAfterRescue() {
        viewModel.dismissPaywall()
        if isInExtension {
            NotificationCenter.default.post(name: .shareExtensionShouldDismissGlobal, object: nil)
        }
    }

    private func cardFill(opacity: Double = 0.45, cornerRadius: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Color.sectionBackground.opacity(opacity))
    }

    private func cardStroke<S: ShapeStyle>(_ style: S = Color.white.opacity(0.14), lineWidth: CGFloat = 0.8, cornerRadius: CGFloat = 18) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(style, lineWidth: lineWidth)
    }

    private func triggerExtensionAutoLaunchIfNeeded() {
        guard isInExtension, extensionLaunchState == .idle else { return }
        extensionLaunchState = .launching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            openWorthItFromExtension()
        }
    }

    private enum PurchaseSource {
        case primary

        var analyticsValue: String { "primary_cta" }
    }

    private enum ShareExtensionLaunchState {
        case idle
        case launching
        case failed
    }
}

struct PaywallPlanOption: Identifiable, Equatable {
    let id: String
    let title: String
    let priceText: String
    let detailText: String
    let trailingBadge: String?
    let product: Product?
    let isRecommended: Bool
    let footnote: String?

    var placeholderPrice: String {
        switch id {
        case AppConstants.subscriptionProductWeeklyID:
            return "$2.99 / week"
        case AppConstants.subscriptionProductAnnualID:
            return "$99.99 / year"
        default:
            return "$19.99"
        }
    }
}

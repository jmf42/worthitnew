import SwiftUI
import StoreKit
import Foundation

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

    private var productsStillLoading: Bool {
        let expected = Set(AppConstants.subscriptionProductIDs)
        let loaded = Set(subscriptionManager.products.map(\.id))
        return !expected.isSubset(of: loaded)
    }

    private var plans: [PaywallPlanOption] {
        let products = subscriptionManager.products
        let annual = products.first { $0.id == AppConstants.subscriptionProductAnnualID }
        let monthly = products.first { $0.id == AppConstants.subscriptionProductMonthlyID }

        return [
            PaywallPlanOption(
                id: AppConstants.subscriptionProductAnnualID,
                title: "Annual",
                priceText: annual?.displayPrice ?? "Loading…",
                detailText: "Best value • Billed yearly",
                badge: "Popular",
                product: annual,
                isRecommended: true
            ),
            PaywallPlanOption(
                id: AppConstants.subscriptionProductMonthlyID,
                title: "Monthly",
                priceText: monthly?.displayPrice ?? "Loading…",
                detailText: "Cancel anytime",
                badge: nil,
                product: monthly,
                isRecommended: false
            )
        ]
    }

    private var selectedPlan: PaywallPlanOption? {
        if let current = selectedPlanID, let match = plans.first(where: { $0.id == current }) {
            return match
        }
        return plans.first
    }

    private var usageProgress: Double {
        guard context.usageSnapshot.limit > 0 else { return 1 }
        return min(1, Double(context.usageSnapshot.count) / Double(context.usageSnapshot.limit))
    }

    private var maxCardWidth: CGFloat { isInExtension ? 320 : 340 }

    var body: some View {
        VStack(spacing: isInExtension ? 16 : 18) {
            header
            premiumSummary
            premiumBenefits

            if isInExtension {
                shareExtensionActions
            } else {
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
            } else if selectedPlanID == nil, let defaultPlan = plans.first?.id {
                selectedPlanID = defaultPlan
            }
            showLoadingSkeleton = !isInExtension && productsStillLoading
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
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

            usageSummary
        }
    }

    private var usageSummary: some View {
        Group {
            if isInExtension {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Today’s free limit", systemImage: "clock")
                            .labelStyle(.titleAndIcon)
                            .font(Theme.Font.captionBold)
                            .foregroundColor(Theme.Color.primaryText)

                        Spacer()

                        Text("\(context.usageSnapshot.count)/\(context.usageSnapshot.limit)")
                            .font(Theme.Font.captionBold)
                            .foregroundColor(Theme.Color.primaryText)
                    }

                    ProgressView(value: usageProgress)
                        .tint(Theme.Color.accent)

                    Text("Reset tomorrow at midnight.")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.7)
                        )
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today’s free limit")
                            .font(Theme.Font.captionBold)
                            .foregroundColor(Theme.Color.secondaryText)

                        Spacer()

                        Text("\(context.usageSnapshot.count) of \(context.usageSnapshot.limit) used")
                            .font(Theme.Font.captionBold)
                            .foregroundColor(Theme.Color.primaryText)
                    }

                    ProgressView(value: usageProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: Theme.Color.accent))

                    Text("Reset tomorrow at midnight.")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.45))
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .blur(radius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                )
            }
        }
    }

    @ViewBuilder
    private var premiumSummary: some View {
        if isInExtension {
            EmptyView()
        } else {
            let reportedLimit = context.usageSnapshot.limit
            let dailyLimit = reportedLimit > 0 ? reportedLimit : AppConstants.dailyFreeAnalysisLimit
            let used = context.usageSnapshot.count
            let remaining = max(dailyLimit - used, 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("Today: \(used)/\(dailyLimit) free breakdowns used")
                    .font(Theme.Font.subheadlineBold)
                    .foregroundColor(Theme.Color.primaryText)

                Text(
                    remaining == 0
                    ? "Come back tomorrow for another \(dailyLimit) free videos, or upgrade to keep going now."
                    : "You can analyze \(remaining) more video\(remaining == 1 ? "" : "s") today for free, or go unlimited with Premium."
                )
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var premiumBenefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WorthIt Premium unlocks")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)

            VStack(alignment: .leading, spacing: 8) {
                benefitRow(icon: "infinity", text: "Unlimited video breakdowns without the wait")
                benefitRow(icon: "bolt.fill", text: "Faster analysis with priority processing")
                benefitRow(icon: "sparkles", text: "Full Worth-It Score, insights, and Q&A on every video")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Color.accent)
                .frame(width: 18)

            Text(text)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.46))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                )
                .redacted(reason: .placeholder)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showLoadingSkeleton)
    }

    private func planSummaryContent(plan: PaywallPlanOption, showSelection: Bool) -> some View {
        let verticalPadding: CGFloat = showSelection ? 14 : 12
        let horizontalPadding: CGFloat = showSelection ? 16 : 14
        let isSelected = selectedPlan?.id == plan.id
        let priceLoaded = plan.product != nil

        let base = HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(Theme.Font.subheadline.weight(.semibold))
                        .foregroundColor(Theme.Color.primaryText)

                    if showSelection, let badge = plan.badge, plan.isRecommended {
                        Text(badge.uppercased())
                            .font(Theme.Font.captionBold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.Color.accent.opacity(0.22))
                            .foregroundColor(Theme.Color.accent)
                            .clipShape(Capsule())
                    }
                }

                priceLabel(for: plan, loaded: priceLoaded)

                Text(plan.detailText)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 14)

            if showSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.Color.accent : Theme.Color.secondaryText.opacity(0.5))
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, horizontalPadding)

        return base
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(showSelection && isSelected ? 0.6 : 0.46))
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .blur(radius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(showSelection && isSelected ? Theme.Color.accent.opacity(0.45) : Theme.Color.sectionBackground.opacity(0.25), lineWidth: 0.9)
                            .blendMode(.overlay)
                    )
            )
    }

    private func priceLabel(for plan: PaywallPlanOption, loaded: Bool) -> some View {
        Group {
            if loaded {
                Text(plan.priceText)
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
                Button(action: attemptPurchase) {
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
            Text("Open WorthIt to finish upgrading to Premium.")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button(action: openWorthItFromExtension) {
                Text("Open WorthIt")
                    .font(Theme.Font.body.weight(.semibold))
                    .foregroundColor(.white)
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
    }

    private func attemptPurchase() {
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
        viewModel.dismissPaywall()
        if isInExtension {
            NotificationCenter.default.post(name: .shareExtensionShouldDismissGlobal, object: nil)
        }
    }
}

struct PaywallPlanOption: Identifiable, Equatable {
    let id: String
    let title: String
    let priceText: String
    let detailText: String
    let badge: String?
    let product: Product?
    let isRecommended: Bool

    var placeholderPrice: String {
        switch id {
        case AppConstants.subscriptionProductMonthlyID:
            return "$9.99 / month"
        case AppConstants.subscriptionProductAnnualID:
            return "$99.99 / year"
        default:
            return "$19.99"
        }
    }
}

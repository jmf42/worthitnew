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

    private var productsStillLoading: Bool {
        subscriptionManager.isLoadingProducts && subscriptionManager.products.isEmpty
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

        // Compare annual cost against paying weekly for a full year (52 weeks).
        let annualIfWeekly = weeklyPrice * 52
        guard annualIfWeekly > 0 else {
            return nil
        }

        let savingsRatio = 1 - (annualPrice / annualIfWeekly)
        let percentage = Int((savingsRatio * 100).rounded())
        return percentage > 0 ? percentage : nil
    }
    
    private var annualSavingsAmount: String? {
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

        // Calculate what you'd pay if you paid weekly for a year
        let annualIfWeekly = weeklyPrice * 52
        guard annualIfWeekly > 0 else {
            return nil
        }

        let savings = annualIfWeekly - annualPrice
        guard savings > 0 else {
            return nil
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: savings))
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
                detailText: "Billed weekly • Cancel anytime",
                trailingBadge: nil,
                product: weekly,
                isRecommended: false,
                footnote: nil
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
    private var isQAPaywall: Bool { context.reason == .qaLimitReached }
    private var qaSnapshot: QAUsageTracker.Snapshot? { context.qaSnapshot }

    var body: some View {
        VStack(spacing: isInExtension ? 18 : 20) {
            header
            usageSummary

            premiumBenefits

            mainExperienceStack
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
            showLoadingSkeleton = productsStillLoading
            viewModel.paywallPresented(reason: context.reason)
            Task {
                await subscriptionManager.refreshProducts()
                await subscriptionManager.refreshEntitlement()
            }
        }
        .onChange(of: subscriptionManager.products) { _ in
            if selectedPlanID == nil, let defaultPlan = plans.first?.id {
                selectedPlanID = defaultPlan
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                showLoadingSkeleton = productsStillLoading
            }
        }
        .onChange(of: subscriptionManager.isLoadingProducts) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showLoadingSkeleton = productsStillLoading
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                }

                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Color.accent)
                        .frame(width: 16)
                    Text("Join 5,000+ Premium users")
                        .font(Theme.Font.caption2)
                        .foregroundColor(Theme.Color.secondaryText)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Color.accent.opacity(0.8))
                        .frame(width: 16)
                    Text("Cancel anytime • No questions asked")
                        .font(Theme.Font.caption2)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
        }
    }

    private func formattedMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = minutes / 60.0
            return hours >= 10 ? String(format: "%.0f hr", hours) : String(format: "%.1f hr", hours)
        }
        return String(format: "%.0f min", minutes)
    }

    @ViewBuilder
    private var usageSummary: some View {
        if isQAPaywall, let qa = qaSnapshot {
            let dailyLimit = max(qa.limitPerDay, AppConstants.dailyFreeQAQuestionLimit)
            let used = min(qa.totalCount, dailyLimit)
            let remaining = max(0, dailyLimit - used)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Free plan • \(dailyLimit) Q&A questions/day")
                        .font(Theme.Font.captionBold)
                        .foregroundColor(Theme.Color.secondaryText)
                    Spacer()
                    Text("\(remaining) left today")
                        .font(Theme.Font.captionBold)
                        .foregroundColor(Theme.Color.primaryText)
                }

                ProgressView(value: Double(used), total: Double(dailyLimit))
                    .progressViewStyle(LinearProgressViewStyle(tint: Theme.Color.accent))

                Text("This video: \(qa.countForVideo)/\(qa.limitPerVideo) free questions used")
                    .font(Theme.Font.caption2)
                    .foregroundColor(Theme.Color.secondaryText)
            }
            .padding(isInExtension ? 10 : 12)
            .background(cardFill(cornerRadius: isInExtension ? 16 : 18))
            .overlay(cardStroke(cornerRadius: isInExtension ? 16 : 18))
        } else {
            let snapshot = context.usageSnapshot
            let dailyLimit = max(snapshot.limit, AppConstants.dailyFreeAnalysisLimit)
            let used = min(snapshot.count, dailyLimit)
            let remaining = max(0, dailyLimit - used)

            VStack(alignment: .leading, spacing: 10) {
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
            }
            .padding(isInExtension ? 10 : 12)
            .background(cardFill(cornerRadius: isInExtension ? 16 : 18))
            .overlay(cardStroke(cornerRadius: isInExtension ? 16 : 18))
        }
    }

    private var premiumBenefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isInExtension {
                Text("Upgrade here. Premium unlocks unlimited videos in the WorthIt app.")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.Color.accent)
                    Text("Includes:")
                        .font(Theme.Font.subheadlineBold)
                        .foregroundColor(Theme.Color.primaryText)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                benefitRow(icon: "infinity", text: "Unlimited video breakdowns, zero waiting for tomorrow")
                benefitRow(icon: "message.fill", text: "Chat freely with every video transcript")
                benefitRow(icon: "chart.bar.fill", text: "Deep insights & sentiment analysis")
            }
            .padding(.leading, 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
    
    private func benefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.Color.accent)
                .frame(width: 18)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var mainExperienceStack: some View {
        VStack(spacing: 20) {
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
        VStack(alignment: .leading, spacing: 14) {
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
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Theme.Gradient.appBluePurple)
                            )
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
                            Text(primaryButtonTitle)
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

    private var primaryButtonTitle: String {
        isInExtension ? "Upgrade to Premium" : "Start Premium"
    }

    private enum PurchaseSource {
        case primary

        var analyticsValue: String { "primary_cta" }
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

#if DEBUG
struct PaywallCard_Previews: PreviewProvider {
    private static let subscriptionManager = SubscriptionManager()
    private static let viewModel = MainViewModel(
        apiManager: APIManager(),
        cacheManager: CacheManager.shared,
        subscriptionManager: subscriptionManager,
        usageTracker: UsageTracker.shared
    )

    private static let sampleContext = MainViewModel.PaywallContext(
        reason: .manual,
        usageSnapshot: UsageTracker.Snapshot(
            date: Date(),
            count: 4,
            limit: 3,
            remaining: 1,
            videoIds: ["abc123", "def456", "ghi789", "jkl000"]
        )
    )

    static var previews: some View {
        ZStack {
            Theme.Color.darkBackground.ignoresSafeArea()
            PaywallCard(context: sampleContext, isInExtension: false)
                .environmentObject(viewModel)
                .environmentObject(subscriptionManager)
        }
        .preferredColorScheme(.dark)
    }
}
#endif

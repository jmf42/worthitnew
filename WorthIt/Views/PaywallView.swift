import SwiftUI
import StoreKit

struct PaywallView: View {
    let context: MainViewModel.PaywallContext
    let isInExtension: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .transition(.opacity)

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
    }
}

#if DEBUG
struct PaywallView_Previews: PreviewProvider {
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
            count: 3,
            limit: 5,
            remaining: 2,
            videoIds: ["abc123", "def456", "ghi789"]
        )
    )

    static var previews: some View {
        PaywallView(context: sampleContext, isInExtension: false)
            .environmentObject(viewModel)
            .environmentObject(subscriptionManager)
            .preferredColorScheme(.dark)
    }
}
#endif

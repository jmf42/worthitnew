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

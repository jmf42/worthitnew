import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    struct Entitlement: Codable, Equatable {
        let productId: String
        let purchaseDate: Date
        let expirationDate: Date?
        let isAutoRenewing: Bool
    }

    enum Status: Equatable {
        case unknown
        case inactive
        case subscribed(Entitlement)

        var isSubscribed: Bool {
            if case .subscribed = self { return true }
            return false
        }
    }

    enum PurchaseOutcome: Equatable {
        case success(productId: String)
        case userCancelled
        case pending
        case failed
    }

    @Published private(set) var status: Status = .unknown {
        didSet {
            guard oldValue != status else { return }
            Logger.shared.notice(
                "Subscription status changed: \(oldValue) → \(status)",
                category: .purchase
            )
        }
    }
    @Published private(set) var products: [Product] = [] {
        didSet {
            let newIDs = products.map { $0.id }
            let previousIDs = oldValue.map { $0.id }
            guard newIDs != previousIDs else { return }
            Logger.shared.debug(
                "Available products updated",
                category: .purchase,
                extra: ["product_ids": newIDs.joined(separator: ",")]
            )
        }
    }

    private let defaults: UserDefaults
    private let entitlementKey = "subscription_manager_entitlement_v1"
    private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupID)) {
        self.defaults = defaults ?? .standard
        if let stored = loadStoredEntitlement() {
            status = stored
        } else {
            status = .unknown
        }

        updatesTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                await self.handle(transactionResult: update)
            }
        }

        Task {
            await refreshProducts()
            await refreshEntitlement()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var isSubscribed: Bool {
        status.isSubscribed
    }

    var currentStatus: Status {
        status
    }

    func ensureEntitlementIfUnknown() async {
        if case .unknown = status {
            await refreshEntitlement()
        }
    }

    func refreshProducts() async {
        do {
            let fetched = try await Product.products(for: AppConstants.subscriptionProductIDs)
            let order = AppConstants.subscriptionProductIDs
            let ordered = fetched.sorted { lhs, rhs in
                let lhsIndex = order.firstIndex(of: lhs.id) ?? Int.max
                let rhsIndex = order.firstIndex(of: rhs.id) ?? Int.max
                if lhsIndex == rhsIndex {
                    return lhs.id < rhs.id
                }
                return lhsIndex < rhsIndex
            }
            products = ordered
        } catch {
            Logger.shared.error("Failed to fetch StoreKit products: \(error.localizedDescription)", category: .purchase, error: error)
        }
    }

    func refreshEntitlement() async {
        let transactions = await latestTransactions()
        guard let active = transactions.first(where: { transaction in
            guard transaction.revocationDate == nil else { return false }
            if let expiration = transaction.expirationDate {
                return expiration > Date()
            }
            return true
        }) else {
            setStatus(.inactive)
            clearStoredEntitlement()
            Logger.shared.info("No active subscriptions found during entitlement refresh", category: .purchase)
            return
        }

        let entitlement = Entitlement(
            productId: active.productID,
            purchaseDate: active.purchaseDate,
            expirationDate: active.expirationDate,
            isAutoRenewing: true
        )
        setStatus(.subscribed(entitlement))
        store(entitlement: entitlement)
        var extras: [String: Any] = [
            "product_id": entitlement.productId,
            "purchase_date": entitlement.purchaseDate.timeIntervalSince1970
        ]
        if let expiration = entitlement.expirationDate {
            extras["expiration"] = expiration.timeIntervalSince1970
        }
        Logger.shared.info("Entitlement refreshed", category: .purchase, extra: extras)
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await handleVerified(transaction: transaction)
                    await transaction.finish()
                    return .success(productId: transaction.productID)
                } else {
                    Logger.shared.warning("Purchase verification failed for product \(product.id)", category: .purchase)
                    return .failed
                }
            case .pending:
                Logger.shared.info("Purchase pending for product \(product.id)", category: .purchase)
                return .pending
            case .userCancelled:
                return .userCancelled
            @unknown default:
                Logger.shared.warning("Encountered unknown purchase result for \(product.id)", category: .purchase)
                return .failed
            }
        } catch {
            Logger.shared.error("Purchase failed for product \(product.id): \(error.localizedDescription)", category: .purchase, error: error)
            return .failed
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
    }

    func manageSubscriptionsURL() -> URL {
        AppConstants.manageSubscriptionsURL
    }

    private func loadStoredEntitlement() -> Status? {
        guard let data = defaults.data(forKey: entitlementKey) else { return nil }
        do {
            let entitlement = try JSONDecoder().decode(Entitlement.self, from: data)
            if let expiration = entitlement.expirationDate, expiration <= Date() {
                return .inactive
            }
            return .subscribed(entitlement)
        } catch {
            Logger.shared.error("Failed to decode stored entitlement: \(error.localizedDescription)", category: .purchase, error: error)
            return nil
        }
    }

    private func store(entitlement: Entitlement) {
        do {
            let data = try JSONEncoder().encode(entitlement)
            defaults.set(data, forKey: entitlementKey)
        } catch {
            Logger.shared.error("Failed to persist entitlement: \(error.localizedDescription)", category: .purchase, error: error)
        }
    }

    private func clearStoredEntitlement() {
        defaults.removeObject(forKey: entitlementKey)
    }

    private func setStatus(_ newStatus: Status) {
        if status != newStatus {
            status = newStatus
        }
    }

    private func latestTransactions() async -> [Transaction] {
        var results: [Transaction] = []
        for productID in AppConstants.subscriptionProductIDs {
            if let latest = await Transaction.latest(for: productID) {
                switch latest {
                case .verified(let transaction):
                    results.append(transaction)
                case .unverified(let transaction, let error):
                    Logger.shared.error("Unverified transaction for product \(transaction.productID): \(error.localizedDescription)", category: .purchase, error: error)
                }
            }
        }
        return results.sorted { lhs, rhs in
            let lhsExpiration = lhs.expirationDate ?? Date.distantFuture
            let rhsExpiration = rhs.expirationDate ?? Date.distantFuture
            return lhsExpiration > rhsExpiration
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        switch transactionResult {
        case .verified(let transaction):
            await handleVerified(transaction: transaction)
            await transaction.finish()
        case .unverified(let transaction, let error):
            Logger.shared.error("Unverified transaction for product \(transaction.productID): \(error.localizedDescription)", category: .purchase, error: error)
        }
    }

    private func handleVerified(transaction: Transaction) async {
        guard AppConstants.subscriptionProductIDs.contains(transaction.productID) else { return }
        if transaction.revocationDate != nil {
            setStatus(.inactive)
            clearStoredEntitlement()
            return
        }
        if let expiration = transaction.expirationDate, expiration <= Date() {
            setStatus(.inactive)
            clearStoredEntitlement()
            return
        }
        let entitlement = Entitlement(
            productId: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            isAutoRenewing: true
        )
        setStatus(.subscribed(entitlement))
        store(entitlement: entitlement)
    }
}

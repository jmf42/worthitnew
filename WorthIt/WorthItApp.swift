//
//  WorthItApp.swift
//  WorthIt
//
import SwiftUI

@main
struct WorthItApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var mainViewModel: MainViewModel
    @StateObject private var subscriptionManager: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase

    // apiManager and cacheManager are no longer stored properties of WorthItApp if only used for VM init.
    // If they were used elsewhere in WorthItApp, they would need to be @StateObject or similar.

    init() {
        // Initialize dependencies first
        let cacheManager = CacheManager.shared // Singleton, safe to access
        let apiManager = APIManager()         // New instance, no 'self' dependency
        let subscriptionManager = SubscriptionManager()
        let usageTracker = UsageTracker.shared
        let qaUsageTracker = QAUsageTracker.shared
        apiManager.preWarm()   // Keep Render container warm

        // Now initialize StateObject with these local constants/variables
        self._subscriptionManager = StateObject(wrappedValue: subscriptionManager)
        self._mainViewModel = StateObject(
            wrappedValue: MainViewModel(
                apiManager: apiManager,
                cacheManager: cacheManager,
                subscriptionManager: subscriptionManager,
                usageTracker: usageTracker,
                qaUsageTracker: qaUsageTracker
            )
        )

        Logger.shared.info("WorthItApp (Main App) initialized.", category: .lifecycle)
        AnalyticsService.shared.logAppLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(mainViewModel)
                .environmentObject(subscriptionManager)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    Logger.shared.info("App received deeplink URL: \(url.absoluteString)", category: .lifecycle)
                    if url.scheme == AppConstants.urlScheme {
                        if mainViewModel.handleDeepLink(url) == false {
                            mainViewModel.processSharedURL(url)
                            appState.currentView = .processing
                        }
                    } else {
                        Logger.shared.warning("Received URL with unexpected scheme: \(url.scheme ?? "nil")", category: .lifecycle)
                    }
                }
                .onChange(of: scenePhase) { phase in
                    Logger.shared.info("Scene phase changed to \(phase)", category: .lifecycle)
                    guard phase == .active else { return }
                    Task {
                        Logger.shared.info("Refreshing StoreKit entitlement (scene became active)", category: .purchase)
                        await subscriptionManager.refreshEntitlement()
                        Logger.shared.info("Finished StoreKit entitlement refresh", category: .purchase)
                    }
                }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var currentView: AppViewScreen = .placeholder
}

enum AppViewScreen {
    case placeholder, processing, initialScreen
}

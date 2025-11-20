//
//  AnalyticsService.swift
//  WorthIt
//

import Foundation
import os.log

class AnalyticsService {
    static let shared = AnalyticsService()
    
    // Analytics event names
    enum EventName: String {
        case appLaunch = "app_launch"
        case shareExtensionUsed = "share_extension_used"
        case videoAnalysisStarted = "video_analysis_started"
        case videoAnalysisCompleted = "video_analysis_completed"
        case videoAnalysisFailed = "video_analysis_failed"
        case qaQuestionAsked = "qa_question_asked"
        case essentialsViewed = "essentials_viewed"
        case cacheHit = "cache_hit"
        case cacheMiss = "cache_miss"
        case networkError = "network_error"
        case transcriptNotFound = "transcript_not_found"
        case commentsNotFound = "comments_not_found"
        case paywallShown = "paywall_shown"
        case paywallDismissed = "paywall_dismissed"
        case paywallLimitHit = "paywall_limit_hit"
        case paywallPurchaseTapped = "paywall_purchase_tapped"
        case paywallPurchaseSucceeded = "paywall_purchase_succeeded"
        case paywallPurchaseFailed = "paywall_purchase_failed"
        case paywallPurchaseCancelled = "paywall_purchase_cancelled"
        case paywallRestoreTapped = "paywall_restore_tapped"
        case paywallManageTapped = "paywall_manage_tapped"
        case paywallDeepLink = "paywall_deeplink"
        case paywallPlanSelected = "paywall_plan_selected"
        case paywallCheckoutStarted = "paywall_checkout_started"
        case paywallMaybeLater = "paywall_maybe_later"
    }
    
    // User properties
    enum UserProperty: String {
        case firstLaunchDate = "first_launch_date"
        case totalAnalyses = "total_analyses"
        case preferredLanguage = "preferred_language"
    }

    private init() {
        setupAnalytics()
        Logger.shared.info("AnalyticsService initialized.", category: .analytics)
    }
    
    private func setupAnalytics() {
        // In a real implementation, you would initialize Firebase here
        // FirebaseApp.configure()
        // For now, we'll use a simple logging approach
        Logger.shared.info("Analytics setup completed (using logging fallback).", category: .analytics)
    }

    // MARK: - Event Tracking
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        logEvent(EventName(rawValue: name) ?? .appLaunch, parameters: parameters)
    }
    
    func logEvent(_ event: EventName, parameters: [String: Any]? = nil) {
        var logParams = parameters ?? [:]
        logParams["event_name"] = event.rawValue
        logParams["timestamp"] = Date().timeIntervalSince1970
        logParams["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        
        // Log to console for debugging
        Logger.shared.info("Analytics Event: \(event.rawValue)", category: .analytics, extra: logParams)
        
        // In production, you would send to Firebase Analytics here
        // Analytics.logEvent(event.rawValue, parameters: logParams)
    }
    
    // MARK: - User Properties
    func setUserProperty(_ property: UserProperty, value: String) {
        Logger.shared.info("User Property Set: \(property.rawValue) = \(value)", category: .analytics)
        // In production: Analytics.setUserProperty(value, forName: property.rawValue)
    }
    
    func setUserProperty(_ property: UserProperty, value: Int) {
        setUserProperty(property, value: String(value))
    }
    
    // MARK: - Error Tracking
    func logError(_ message: String, context: String? = nil, error: Error? = nil, videoId: String? = nil) {
        var params: [String: Any] = ["error_message": message]
        if let context = context { params["error_context"] = context }
        if let error = error { params["error_details"] = error.localizedDescription }
        if let videoId = videoId { params["video_id"] = videoId }
        
        Logger.shared.error("Analytics Error: \(message)", category: .analytics, error: error, extra: params)
        
        // In production, you would send to Crashlytics here
        // Crashlytics.crashlytics().record(error: error, userInfo: params)
    }
    
    // MARK: - App Lifecycle Events
    func logAppLaunch() {
        logEvent(.appLaunch)
        
        // Track first launch
        let defaults = UserDefaults.standard
        if defaults.object(forKey: UserProperty.firstLaunchDate.rawValue) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: UserProperty.firstLaunchDate.rawValue)
            setUserProperty(.firstLaunchDate, value: Date().timeIntervalSince1970.description)
        }
    }
    
    // MARK: - Video Analysis Events
    func logVideoAnalysisStarted(videoId: String) {
        logEvent(.videoAnalysisStarted, parameters: ["video_id": videoId])
    }
    
    func logVideoAnalysisCompleted(videoId: String, score: Double, hasComments: Bool) {
        logEvent(.videoAnalysisCompleted, parameters: [
            "video_id": videoId,
            "score": score,
            "has_comments": hasComments
        ])
    }
    
    func logVideoAnalysisFailed(videoId: String, error: String) {
        logEvent(.videoAnalysisFailed, parameters: [
            "video_id": videoId,
            "error": error
        ])
    }
    
    // MARK: - Cache Events
    func logCacheHit(type: String, videoId: String) {
        logEvent(.cacheHit, parameters: [
            "cache_type": type,
            "video_id": videoId
        ])
    }
    
    func logCacheMiss(type: String, videoId: String) {
        logEvent(.cacheMiss, parameters: [
            "cache_type": type,
            "video_id": videoId
        ])
    }
    
    // MARK: - Network Events
    func logNetworkError(endpoint: String, error: String) {
        logEvent(.networkError, parameters: [
            "endpoint": endpoint,
            "error": error
        ])
    }
    
    // MARK: - Content Events
    func logTranscriptNotFound(videoId: String) {
        logEvent(.transcriptNotFound, parameters: ["video_id": videoId])
    }
    
    func logCommentsNotFound(videoId: String) {
        logEvent(.commentsNotFound, parameters: ["video_id": videoId])
    }
    
    // MARK: - User Interaction Events
    func logQAQuestionAsked(videoId: String, questionLength: Int) {
        logEvent(.qaQuestionAsked, parameters: [
            "video_id": videoId,
            "question_length": questionLength
        ])
    }
    
    func logEssentialsViewed(videoId: String) {
        logEvent(.essentialsViewed, parameters: ["video_id": videoId])
    }
    
    func logShareExtensionUsed(videoId: String) {
        logEvent(.shareExtensionUsed, parameters: ["video_id": videoId])
    }

    // MARK: - Paywall Events
    func logPaywallLimitHit(videoId: String, used: Int, limit: Int) {
        logEvent(.paywallLimitHit, parameters: [
            "video_id": videoId,
            "used": used,
            "limit": limit
        ])
    }

    func logPaywallShown(trigger: String, used: Int, limit: Int) {
        logEvent(.paywallShown, parameters: [
            "trigger": trigger,
            "used": used,
            "limit": limit
        ])
    }

    func logPaywallDismissed(purchased: Bool) {
        logEvent(.paywallDismissed, parameters: ["purchased": purchased])
    }

    func logPaywallPurchaseTapped(productId: String) {
        logEvent(.paywallPurchaseTapped, parameters: ["product_id": productId])
    }

    func logPaywallPurchaseSucceeded(productId: String) {
        logEvent(.paywallPurchaseSucceeded, parameters: ["product_id": productId])
    }

    func logPaywallPurchaseFailed(productId: String) {
        logEvent(.paywallPurchaseFailed, parameters: ["product_id": productId])
    }

    func logPaywallPurchaseCancelled(productId: String) {
        logEvent(.paywallPurchaseCancelled, parameters: ["product_id": productId])
    }

    func logPaywallRestoreTapped() {
        logEvent(.paywallRestoreTapped)
    }

    func logPaywallManageTapped() {
        logEvent(.paywallManageTapped)
    }

    func logPaywallDeepLinkOpened() {
        logEvent(.paywallDeepLink)
    }

    func logPaywallPlanSelected(productId: String) {
        logEvent(.paywallPlanSelected, parameters: ["product_id": productId])
    }

    func logPaywallCheckoutStarted(productId: String, source: String, isTrial: Bool) {
        logEvent(.paywallCheckoutStarted, parameters: [
            "product_id": productId,
            "source": source,
            "is_trial": isTrial
        ])
    }

    func logPaywallMaybeLater(trialEligible: Bool, trialViewPresented: Bool) {
        logEvent(.paywallMaybeLater, parameters: [
            "trial_eligible": trialEligible,
            "trial_view_presented": trialViewPresented
        ])
    }
}

//
//  MainViewModel.swift
//  WorthIt
//

import SwiftUI
import Combine
import OSLog // For Logger

@MainActor
class MainViewModel: ObservableObject {

    // MARK: - Published Properties for UI State
    @Published var viewState: ViewState = .idle { // Now finds ViewState from Models.swift
        didSet {
            guard oldValue != viewState else { return }
            Logger.shared.notice(
                "ViewState changed \(oldValue) → \(viewState)",
                category: .ui,
                extra: ["source": "MainViewModel"]
            )
        }
    }
    @Published var currentScreenOverride: ViewState? = nil
    @Published var processingProgress: Double = 0.0
    @Published var userFriendlyError: UserFriendlyError? = nil // Now finds UserFriendlyError from Models.swift

    // MARK: - Published Properties for Data Results
    @Published var analysisResult: ContentAnalysis?
    @Published var worthItScore: Double?
    @Published var scoreBreakdownDetails: ScoreBreakdown?
    /// Quick metrics returned by the light‑weight GPT pass before a full comment scan
    @Published var essentialsCommentAnalysis: EssentialsCommentAnalysis?
    /// Decision card data shown on the root overlay
    @Published var decisionCardModel: DecisionCardModel?
    /// Flag to trigger the decision card overlay once per presentation
    @Published var shouldPromptDecisionCard: Bool = false
    /// Tracks if the current video already displayed its decision card this session
    @Published private(set) var hasShownDecisionCardForCurrentVideo: Bool = false

    @Published var qaMessages: [ChatMessage] = []
    @Published var qaInputText: String = ""
    @Published var isQaLoading: Bool = false
    @Published var shouldPresentScoreBreakdown: Bool = false

    private var allFetchedComments: [String] = [] // Full fetched comments
    private var llmAnalyzedComments: [String] = [] // The truncated array sent to LLM (up to 50)
    @Published var suggestedQuestions: [String] = [] // From Essentials (fast analysis)
    @Published var hasCommentsAvailableForError: Bool = false
    @Published var activePaywall: PaywallContext? = nil
    @Published var shouldOpenManageSubscriptions: Bool = false
    @Published var hasHitQALimit: Bool = false

    private(set) var currentVideoID: String?
    @Published var currentVideoTitle: String?
    @Published var currentVideoThumbnailURL: URL?

    var rawTranscript: String?
    private var cleanedTranscriptForLLM: String?
    private var transcriptForAnalysis: String?

    private var activeAnalysisTask: Task<Void, Never>? = nil
    private var fullAnalysisTask: Task<Void, Never>? = nil
    private var minimumDisplayTimerTask: Task<Void, Never>? = nil
    // Keep UI snappy: shorter minimum loader time while avoiding flicker
    private let minimumDisplayTime: TimeInterval = 3.5

    private var processedVideoIDsThisSession = Set<String>()

    private let commentClassificationLimit = 50
    private let commentInsightsLimit = 50
    private var decisionCardShownVideoIDs = Set<String>()

    // MARK: - Score breakdown presentation
    func requestScoreBreakdownPresentation() {
        shouldPresentScoreBreakdown = true
    }

    func consumeScoreBreakdownRequest() {
        shouldPresentScoreBreakdown = false
    }
    private let apiManager: APIManager
    private let cacheManager: CacheManager
    private let subscriptionManager: SubscriptionManager
    private let usageTracker: UsageTracker
    private let qaUsageTracker: QAUsageTracker
    private var cancellables = Set<AnyCancellable>()
    @Published private(set) var isUserSubscribed: Bool = false
    private var usageReservations: [String: Bool] = [:]
    private var latestUsageSnapshot: UsageTracker.Snapshot?
    private var paywallLoggedImpression = false
    @Published private(set) var lastQALimitSnapshot: QAUsageTracker.Snapshot?

    private var isRunningInExtension: Bool {
        Bundle.main.bundlePath.lowercased().contains(".appex")
    }

    struct PaywallContext {
        let reason: PaywallReason
        let usageSnapshot: UsageTracker.Snapshot
        let qaSnapshot: QAUsageTracker.Snapshot?

        init(reason: PaywallReason, usageSnapshot: UsageTracker.Snapshot, qaSnapshot: QAUsageTracker.Snapshot? = nil) {
            self.reason = reason
            self.usageSnapshot = usageSnapshot
            self.qaSnapshot = qaSnapshot
        }
    }

    enum PaywallReason: String {
        case dailyLimitReached
        case manual
        case qaLimitReached

        var analyticsLabel: String {
            switch self {
            case .dailyLimitReached: return "daily_limit"
            case .manual: return "manual"
            case .qaLimitReached: return "qa_limit"
            }
        }
    }

    private func refreshCommentsIfStale(videoId: String, cachedAnalysis: ContentAnalysis) async {
        let missingSummary = (cachedAnalysis.CommentssentimentSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let missingThemes = (cachedAnalysis.topThemes?.isEmpty ?? true)
        guard missingSummary && missingThemes else { return }

        do {
            let comments = try await fetchComments(videoId: videoId)
            let classificationComments = Array(comments.prefix(commentClassificationLimit))
            let classificationResult = try await apiManager.fetchCommentsClassification(comments: classificationComments)

            let rawThemes: [CommentTheme] = (classificationResult.topThemes ?? []).map {
                let trimmedExample = $0.exampleComment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let clipped = String(trimmedExample.prefix(80))
                return CommentTheme(
                    theme: $0.theme,
                    sentiment: $0.sentiment,
                    sentimentScore: $0.sentimentScore,
                    exampleComment: clipped.isEmpty ? nil : clipped
                )
            }
            let validatedThemes: [CommentTheme] = rawThemes.filter { theme in
                guard let ex = theme.exampleComment, ex.count <= 80 else { return false }
                return classificationComments.contains { $0.contains(ex) }
            }
            let themesToUse = validatedThemes.isEmpty ? rawThemes : validatedThemes
            let resolvedSpamRatio: Double? = {
                guard let raw = classificationResult.spamRatio else { return nil }
                return max(0.0, min(raw, 1.0))
            }()

            let updated = ContentAnalysis(
                longSummary: cachedAnalysis.longSummary,
                takeaways: cachedAnalysis.takeaways,
                gemsOfWisdom: cachedAnalysis.gemsOfWisdom,
                videoId: cachedAnalysis.videoId,
                videoTitle: cachedAnalysis.videoTitle,
                videoDurationSeconds: cachedAnalysis.videoDurationSeconds,
                videoThumbnailUrl: cachedAnalysis.videoThumbnailUrl,
                CommentssentimentSummary: classificationResult.CommentssentimentSummary,
                topThemes: themesToUse.isEmpty ? [] : themesToUse,
                spamRatio: resolvedSpamRatio,
                viewerTips: MainViewModel.sanitizeTips(classificationResult.viewerTips, within: classificationComments),
                openQuestions: MainViewModel.sanitizeOpenQuestions(classificationResult.openQuestions, within: classificationComments)
            )

            await cacheManager.saveContentAnalysis(updated, for: videoId)
            self.analysisResult = updated
            self.calculateAndSetWorthItScore()
        } catch {
            Logger.shared.warning("refreshCommentsIfStale failed for \(videoId): \(error.localizedDescription)", category: .services)
        }
    }

    private func syncDecisionCardSeenState(for videoId: String?) {
        guard let id = videoId else {
            hasShownDecisionCardForCurrentVideo = false
            return
        }
        hasShownDecisionCardForCurrentVideo = decisionCardShownVideoIDs.contains(id)
    }

    private func promptDecisionCardIfReady() {
        guard decisionCardModel != nil,
              !hasShownDecisionCardForCurrentVideo else { return }
        shouldPromptDecisionCard = true
    }

    // Streaming removed: we now render a skeleton until full analysis is ready

    init(apiManager: APIManager, cacheManager: CacheManager, subscriptionManager: SubscriptionManager, usageTracker: UsageTracker, qaUsageTracker: QAUsageTracker = QAUsageTracker.shared) {
        self.apiManager = apiManager
        self.cacheManager = cacheManager
        self.subscriptionManager = subscriptionManager
        self.usageTracker = usageTracker
        self.qaUsageTracker = qaUsageTracker
        self.isUserSubscribed = subscriptionManager.isSubscribed
        Logger.shared.info("MainViewModel initialized.", category: .lifecycle)

        subscriptionManager.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isUserSubscribed = status.isSubscribed
                if status.isSubscribed {
                    self.dismissPaywall(afterSuccessfulPurchase: true)
                    self.latestUsageSnapshot = nil
                    self.usageReservations.removeAll()
                    Task { [weak self] in
                        await self?.usageTracker.clearAll()
                        await self?.qaUsageTracker.clearAll()
                    }
                    self.hasHitQALimit = false
                    self.lastQALimitSnapshot = nil
                }
            }
            .store(in: &cancellables)
    }

    // Limit and sanitize suggested questions to at most 3 concise, unique items
    private func normalizeSuggestedQuestions(_ questions: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in questions {
            let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { continue }
            let key = q.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(q)
            if result.count == 3 { break }
        }
        return result
    }

    /// Trim empties and dedupe text while preserving order (case-insensitive)
    private func uniqueNonEmpty(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in items {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    /// Keep only LLM outputs that literally appear in the analyzed comments, to avoid hallucinated tips/questions.
    nonisolated private static func sanitizeTips(_ items: [String]?, within comments: [String]) -> [String]? {
        guard let items = items else { return nil }
        let trimmed = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 140 && !$0.contains("?") }
        guard !trimmed.isEmpty else { return [] }

        let bannedTokens = ["http", "www", ".com", "%", "percent", "subscribe", "coupon", "code", "book", "episode", "supplement", "offer", "off ", "thanks", "thank", "great", "awesome", "congrats", "appreciate", "love", "cool", "nice"]
        func isPromoOrPraise(_ text: String) -> Bool {
            let lower = text.lowercased()
            return bannedTokens.contains { lower.contains($0) }
        }

        let filtered = trimmed.filter { tip in
            guard !isPromoOrPraise(tip) else { return false }
            return comments.contains { $0.contains(tip) }
        }
        return filtered.isEmpty ? [] : filtered
    }

    nonisolated private static func sanitizeOpenQuestions(_ items: [String]?, within comments: [String]) -> [String]? {
        guard let items = items else { return nil }
        let trimmed = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 140 && $0.contains("?") }
        guard !trimmed.isEmpty else { return [] }

        let filtered = trimmed.filter { question in
            let lower = question.lowercased()
            let bannedTokens = ["http", "www", ".com", "percent", "coupon", "code", "subscribe"]
            if bannedTokens.contains(where: { lower.contains($0) }) { return false }
            return comments.contains { $0.contains(question) }
        }
        return filtered.isEmpty ? [] : filtered
    }

    private func makeViewerThemes(from themes: [CommentTheme]?) -> [ViewerThemeDisplay] {
        guard let themes, !themes.isEmpty else { return [] }

        var seenKeys = Set<String>()
        var results: [ViewerThemeDisplay] = []

        for theme in themes {
            let title = friendlyThemeTitle(theme.theme)
            let key = title.lowercased()
            guard !title.isEmpty, seenKeys.insert(key).inserted else { continue }

            let cleanedExample: String? = {
                guard let example = theme.exampleComment?.trimmingCharacters(in: .whitespacesAndNewlines), !example.isEmpty else { return nil }
                let squashed = example.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                return squashed.count > 120 ? String(squashed.prefix(117)) + "..." : squashed
            }()

            let sentimentKind = viewerSentimentKind(from: theme.sentiment)
            results.append(ViewerThemeDisplay(title: title, sentiment: sentimentKind, sentimentScore: theme.sentimentScore, example: cleanedExample))
        }
        return results
    }

    private func friendlyThemeTitle(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "-", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "([a-z])([A-Z0-9])", with: "$1 $2", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return raw }

        let acronyms = ["ai", "ml", "ui", "ux", "pm"]
        let words = cleaned.split(separator: " ").map { word -> String in
            let lower = word.lowercased()
            if acronyms.contains(lower) { return lower.uppercased() }
            return lower
        }
        guard !words.isEmpty else { return cleaned }

        var sentenceWords: [String] = []
        for (index, word) in words.enumerated() {
            if index == 0 {
                sentenceWords.append(word.prefix(1).uppercased() + word.dropFirst())
            } else {
                sentenceWords.append(word)
            }
        }
        return sentenceWords.joined(separator: " ")
    }

    private func viewerSentimentKind(from raw: String) -> ViewerThemeSentiment {
        switch raw.lowercased() {
        case "positive": return .positive
        case "negative": return .negative
        case "mixed": return .mixed
        default: return .neutral
        }
    }

    /// Evenly samples up to `limit` comments across the list to capture early, middle, and late signals.
    private func sampleComments(_ comments: [String], limit: Int) -> [String] {
        guard comments.count > limit, limit > 0 else { return Array(comments.prefix(limit)) }
        let step = Double(comments.count - 1) / Double(limit - 1)
        var result: [String] = []
        for i in 0..<limit {
            let idx = Int(round(Double(i) * step))
            result.append(comments[idx])
        }
        return result
    }

    private func releaseUsageReservation(for videoId: String, revertIfNeeded: Bool) {
        guard let wasCounted = usageReservations.removeValue(forKey: videoId) else { return }
        if revertIfNeeded && wasCounted {
            Task {
                await usageTracker.remove(videoId: videoId, dailyLimit: AppConstants.dailyFreeAnalysisLimit)
            }
        }
    }

    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme == AppConstants.urlScheme else { return false }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        if host == "subscribe" || path.contains("subscribe") {
            if isUserSubscribed {
                AnalyticsService.shared.logPaywallDeepLinkOpened()
                paywallManageTapped()
                shouldOpenManageSubscriptions = true
            } else {
                Task { @MainActor in
                    let snapshot = await usageTracker.snapshot(dailyLimit: AppConstants.dailyFreeAnalysisLimit)
                    presentPaywall(reason: .manual, usageSnapshot: snapshot)
                    AnalyticsService.shared.logPaywallDeepLinkOpened()
                }
            }
            return true
        }
        return false
    }

    func processSharedURL(_ url: URL) {
        Task { @MainActor in
            await self.processSharedURLInternal(url)
        }
    }

    private func processSharedURLInternal(_ url: URL) async {
        Logger.shared.info("Processing shared URL: \(url.absoluteString)", category: .lifecycle)

        guard let videoId = extractVideoID(from: url) else {
            setPublicError(message: "Invalid video link. Please share a valid video URL.", canRetry: false)
            return
        }

        Logger.shared.info("Extracted Video ID: \(videoId)", category: .lifecycle)

        var allowanceSnapshot: UsageTracker.Snapshot?
        var reservationWasCounted = false

        if !isUserSubscribed {
            await subscriptionManager.ensureEntitlementIfUnknown()
            if subscriptionManager.isSubscribed {
                isUserSubscribed = true
            }
        }

        if !isUserSubscribed {
            let allowance = await usageTracker.registerAttempt(for: videoId, dailyLimit: AppConstants.dailyFreeAnalysisLimit)
            allowanceSnapshot = allowance.snapshot
            latestUsageSnapshot = allowance.snapshot

            if allowance.allowed == false {
                AnalyticsService.shared.logPaywallLimitHit(videoId: videoId, used: allowance.snapshot.count, limit: allowance.snapshot.limit)
                presentPaywall(reason: .dailyLimitReached, usageSnapshot: allowance.snapshot)
                return
            }

            reservationWasCounted = allowance.wasCounted
        } else {
            latestUsageSnapshot = nil
        }

        resetForNewAnalysis()

        self.currentVideoID = videoId
        syncDecisionCardSeenState(for: videoId)
        self.currentVideoThumbnailURL = URL(string: "https://i.ytimg.com/vi/\(videoId)/hq720.jpg")
        latestUsageSnapshot = allowanceSnapshot
        usageReservations[videoId] = isUserSubscribed ? false : reservationWasCounted

        // Log analytics events
        AnalyticsService.shared.logShareExtensionUsed(videoId: videoId)
        AnalyticsService.shared.logVideoAnalysisStarted(videoId: videoId)

        // Check for cached results (both session and disk cache)
        let cache = cacheManager

        if let cachedAnalysis = await cache.loadContentAnalysis(for: videoId) {
            Logger.shared.info("processSharedURL cache HIT for \(videoId).", category: .cache)
            
            // Populate view model from cache
            self.analysisResult = cachedAnalysis
            self.essentialsCommentAnalysis = await cache.loadCommentInsights(for: videoId)
            Task { await self.refreshCommentsIfStale(videoId: videoId, cachedAnalysis: cachedAnalysis) }

            var resolvedTranscript = await cache.loadTranscript(for: videoId)
            if resolvedTranscript == nil {
                do {
                    Logger.shared.info("Transcript cache miss during share flow. Refetching for \(videoId)", category: .cache)
                    let fetched = try await apiManager.fetchTranscript(videoId: videoId)
                    await cache.saveTranscript(fetched, for: videoId)
                    resolvedTranscript = fetched
                } catch {
                    Logger.shared.warning("Failed to refetch transcript during share flow: \(error.localizedDescription)", category: .services)
                }
            }

            self.rawTranscript = resolvedTranscript
            if let transcript = resolvedTranscript {
                let variants = await preprocessTranscriptVariants(transcript)
                self.transcriptForAnalysis = variants.stripped
                self.cleanedTranscriptForLLM = variants.cleaned
            } else {
                self.transcriptForAnalysis = nil
                self.cleanedTranscriptForLLM = nil
            }
            self.currentVideoTitle = cachedAnalysis.videoTitle
            
            // Set thumbnail URL
            let fallback = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
            let thumb = cachedAnalysis.videoThumbnailUrl
            self.currentVideoThumbnailURL = URL(string: (thumb?.isEmpty == false ? thumb! : fallback))

            // Restore suggested questions from essentials cache only
            if let cachedEssentials = self.essentialsCommentAnalysis {
                self.suggestedQuestions = normalizeSuggestedQuestions(cachedEssentials.suggestedQuestions)
            }

            // Calculate score and update progress
            self.calculateAndSetWorthItScore()
            self.processingProgress = 1.0
            // Reset decision card for this video and rebuild it for cached results
            self.decisionCardModel = nil
            self.shouldPromptDecisionCard = false

            // Show options immediately without waiting
            self.viewState = .showingInitialOptions
            self.refreshDecisionCardIfPossible(videoId: videoId)
            // Add to processed set so future loads are instant
            processedVideoIDsThisSession.insert(videoId)
            releaseUsageReservation(for: videoId, revertIfNeeded: false)
            return
        }

        // No cache hit: enter processing state
        self.viewState = .processing
        self.decisionCardModel = nil
        self.shouldPromptDecisionCard = false
        // Only start minimum display timer if we don't have cached results
        startMinimumDisplayTimer()

        activeAnalysisTask = Task(priority: .userInitiated) {
            do {
                // Step 1: Fetch transcript and comments in parallel
                async let transcriptTask = fetchTranscript(videoId: videoId)
                async let commentsTask = fetchComments(videoId: videoId)
                let transcriptOpt = try? await transcriptTask
                let comments = (try? await commentsTask) ?? []

                // --- Transcript Validation ---
                guard let transcript = transcriptOpt, !transcript.isEmpty else {
                    Logger.shared.warning("Transcript unavailable for \(videoId). Prompting user to try another video.", category: .services)
                    self.hasCommentsAvailableForError = false
                    self.allFetchedComments = []
                    setPublicError(message: "Transcript unavailable.", canRetry: true, videoIdForRetry: videoId)
                    updateProgress(1.0, message: "Transcript Unavailable")
                    return
                }
                self.rawTranscript = transcript
                let variants = await preprocessTranscriptVariants(transcript)
                self.transcriptForAnalysis = variants.stripped
                self.cleanedTranscriptForLLM = variants.cleaned
                updateProgress(0.4, message: "Transcript Ready")

                // --- Comments Handling ---
                updateProgress(0.5, message: "Comments Ready")
                self.allFetchedComments = comments // Store all fetched
                // Store the truncated array sent to LLM for index mapping
                let truncated = Array(comments.prefix(commentClassificationLimit))
                self.llmAnalyzedComments = truncated

                guard let finalTranscriptForAnalysis = self.transcriptForAnalysis else {
                    Logger.shared.critical("transcriptForAnalysis is nil despite successful fetch for \(videoId).", category: .services)
                    setPublicError(message: "Internal error preparing transcript.", canRetry: true, videoIdForRetry: videoId)
                    return
                }

                let titleForGpt = self.currentVideoTitle ?? videoId

                // --- FULL ANALYSIS (primary) ---
                // Launch full analysis (streaming). We no longer run fast analysis in parallel.
        self.fullAnalysisTask?.cancel()
        self.fullAnalysisTask = Task(priority: .userInitiated) {
            await self.performNonStreamingAnalysis(
                videoId: videoId,
                transcript: finalTranscriptForAnalysis,
                comments: comments,
                titleForGpt: titleForGpt
            )
        }

        // Streaming removed; skeleton UI will show until analysis completes.
            } catch {
                Logger.shared.error("Error in main analysis Task: \(error.localizedDescription)", category: .services, error: error)
                setPublicError(message: error.localizedDescription, canRetry: true, videoIdForRetry: videoId)
                updateProgress(1.0, message: "Analysis Failed")
            }
        }
    }

    // Proceed with comments-only insights when transcript is missing
    func reviewCommentsOnly() {
        guard let videoId = currentVideoID else { return }
        clearCurrentError()
        let existingComments = allFetchedComments
        let cache = cacheManager

        Task {
            do {
                let comments: [String]
                if existingComments.isEmpty {
                    comments = await cache.loadComments(for: videoId) ?? []
                } else {
                    comments = existingComments
                }
                let limitedComments = Array(comments.prefix(commentInsightsLimit))
                let essentials: EssentialsCommentAnalysis? = limitedComments.isEmpty ? nil : try await apiManager.fetchCommentInsights(comments: limitedComments, transcriptContext: "")

                await MainActor.run {
                    self.essentialsCommentAnalysis = essentials
                    if let essentials = essentials {
                        self.suggestedQuestions = self.normalizeSuggestedQuestions(essentials.suggestedQuestions)
                    } else {
                        self.suggestedQuestions = []
                    }
                    self.calculateAndSetWorthItScore()
                    self.hasCommentsAvailableForError = false
                    self.viewState = .showingInitialOptions
                }

                if let essentials = essentials {
                    await cache.saveCommentInsights(essentials, for: videoId)
                }
            } catch {
                Logger.shared.error("Comments-only insights failed: \(error.localizedDescription)", category: .services, error: error)
                await MainActor.run {
                    self.essentialsCommentAnalysis = nil
                    self.suggestedQuestions = []
                    self.calculateAndSetWorthItScore()
                    self.viewState = .showingInitialOptions
                }
            }
        }
    }

    /// Restore UI state from cached results for a given video ID without triggering processing.
    func restoreFromCache(videoId: String) async {
        Logger.shared.info("Restoring from cache for videoId: \(videoId)", category: .cache)
        // Reset any in-flight tasks/UI state, but keep caches
        resetForNewAnalysis()

        self.currentVideoID = videoId
        syncDecisionCardSeenState(for: videoId)

        let cache = cacheManager

        guard let cachedAnalysis = await cache.loadContentAnalysis(for: videoId) else {
            Logger.shared.warning("restoreFromCache: No cached analysis found for \(videoId)", category: .cache)
            // Fall back to showing idle with basic thumbnail
            self.currentVideoThumbnailURL = URL(string: "https://i.ytimg.com/vi/\(videoId)/hq720.jpg")
            self.currentVideoTitle = videoId
            return
        }

        // Populate view model from cache
        self.analysisResult = cachedAnalysis
        self.essentialsCommentAnalysis = await cache.loadCommentInsights(for: videoId)
        Task { await self.refreshCommentsIfStale(videoId: videoId, cachedAnalysis: cachedAnalysis) }

        var resolvedTranscript = await cache.loadTranscript(for: videoId)
        if resolvedTranscript == nil {
            do {
                Logger.shared.info("Transcript cache miss during restore. Refetching for \(videoId)", category: .cache)
                let fetched = try await apiManager.fetchTranscript(videoId: videoId)
                await cache.saveTranscript(fetched, for: videoId)
                resolvedTranscript = fetched
            } catch {
                Logger.shared.warning("Failed to refetch transcript during restore: \(error.localizedDescription)", category: .services)
            }
        }

        self.rawTranscript = resolvedTranscript
        if let transcript = resolvedTranscript {
            let variants = await preprocessTranscriptVariants(transcript)
            self.transcriptForAnalysis = variants.stripped
            self.cleanedTranscriptForLLM = variants.cleaned
        } else {
            self.transcriptForAnalysis = nil
            self.cleanedTranscriptForLLM = nil
        }
        self.currentVideoTitle = cachedAnalysis.videoTitle

        // Set thumbnail URL (UI layer will try higher-res fallbacks automatically)
        let fallback = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        let thumb = cachedAnalysis.videoThumbnailUrl
        self.currentVideoThumbnailURL = URL(string: (thumb?.isEmpty == false ? thumb! : fallback))

        // Restore suggested questions from essentials cache only
        if let cachedEssentials = self.essentialsCommentAnalysis {
            self.suggestedQuestions = normalizeSuggestedQuestions(cachedEssentials.suggestedQuestions)
        }

        // Calculate score and update state
        self.calculateAndSetWorthItScore()
        self.processingProgress = 1.0
        self.viewState = .showingInitialOptions
        promptDecisionCardIfReady()
        processedVideoIDsThisSession.insert(videoId)
    }



    private func performNonStreamingAnalysis(videoId: String, transcript: String, comments: [String], titleForGpt: String) async {
        Logger.shared.info("Starting full analysis (non-stream) for video ID: \(videoId)", category: .analysis)
        processedVideoIDsThisSession.insert(videoId)
        updateProgress(0.6, message: "Analyzing")

        let classificationComments = Array(comments.prefix(commentClassificationLimit))
        let insightsComments = sampleComments(comments, limit: commentInsightsLimit)
        let cache = cacheManager
        let precleanedTranscript = self.cleanedTranscriptForLLM
        let insightsContextSource = precleanedTranscript ?? transcript
        let truncatedInsightsContext = insightsContextSource.truncate(to: 12000)

        do {
            var contentAnalysisData: ContentAnalysis!
            var insights: EssentialsCommentAnalysis?

            var commentClassificationFailed = false

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    async let transcriptTask = self.apiManager.fetchTranscriptSummary(
                        transcript: transcript,
                        videoTitle: titleForGpt,
                        precleanedTranscript: precleanedTranscript
                    )
                    let transcriptResult = try await transcriptTask

                    var classificationResult: APIManager.CommentsOnlyResponse?
                    do {
                        classificationResult = try await self.apiManager.fetchCommentsClassification(comments: classificationComments)
                    } catch {
                        Logger.shared.warning("Comment classification unavailable for \(videoId): \(error.localizedDescription)", category: .services)
                        await MainActor.run {
                            commentClassificationFailed = true
                        }
                    }

                    let rawThemes: [CommentTheme] = (classificationResult?.topThemes ?? []).map {
                        let trimmedExample = $0.exampleComment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let clipped = String(trimmedExample.prefix(80))
                        return CommentTheme(
                            theme: $0.theme,
                            sentiment: $0.sentiment,
                            sentimentScore: $0.sentimentScore,
                            exampleComment: clipped.isEmpty ? nil : clipped
                        )
                    }
                    let validatedThemes: [CommentTheme] = rawThemes.filter { theme in
                        guard let ex = theme.exampleComment, ex.count <= 80 else { return false }
                        return classificationComments.contains { $0.contains(ex) }
                    }
                    let resolvedSpamRatio: Double? = {
                        guard let raw = classificationResult?.spamRatio else { return nil }
                        return max(0.0, min(raw, 1.0))
                    }()
                    // Fall back to raw themes if validation trims everything, so we still render usable data
                    let themesToUse = validatedThemes.isEmpty ? rawThemes : validatedThemes

                    let analysis = ContentAnalysis(
                        longSummary: transcriptResult.longSummary,
                        takeaways: transcriptResult.takeaways,
                        gemsOfWisdom: transcriptResult.gemsOfWisdom,
                        videoId: videoId,
                        videoTitle: titleForGpt,
                        videoDurationSeconds: nil,
                        videoThumbnailUrl: nil,
                        CommentssentimentSummary: classificationResult?.CommentssentimentSummary,
                        topThemes: themesToUse.isEmpty ? [] : themesToUse,
                        spamRatio: resolvedSpamRatio,
                        viewerTips: MainViewModel.sanitizeTips(classificationResult?.viewerTips, within: classificationComments),
                        openQuestions: MainViewModel.sanitizeOpenQuestions(classificationResult?.openQuestions, within: classificationComments)
                    )

                    await MainActor.run {
                        contentAnalysisData = analysis
                    }
                }

                if !insightsComments.isEmpty {
                    group.addTask {
                        let local = try? await self.apiManager.fetchCommentInsights(
                            comments: insightsComments,
                            transcriptContext: truncatedInsightsContext
                        )
                        await MainActor.run {
                            self.essentialsCommentAnalysis = local
                            var sq = self.normalizeSuggestedQuestions(local?.suggestedQuestions ?? [])
                            if sq.isEmpty {
                                sq = self.generateFallbackSuggestedQuestions(from: transcript)
                            }
                            self.suggestedQuestions = sq
                            self.calculateAndSetWorthItScore()
                        }
                        insights = local
                    }
                }

                try await group.waitForAll()
            }

            // Persist
            self.analysisResult = contentAnalysisData
            let resolvedTitle = contentAnalysisData.videoTitle ?? titleForGpt
            self.currentVideoTitle = resolvedTitle
        self.currentVideoThumbnailURL = URL(string: contentAnalysisData.videoThumbnailUrl ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        await cache.saveContentAnalysis(contentAnalysisData, for: videoId)

        if commentClassificationFailed {
            AnalyticsService.shared.logCommentsNotFound(videoId: videoId)
        }

            self.essentialsCommentAnalysis = insights
            if let insights = insights { await cache.saveCommentInsights(insights, for: videoId) }
            var finalSQ = normalizeSuggestedQuestions(insights?.suggestedQuestions ?? [])
            if finalSQ.isEmpty {
                finalSQ = generateFallbackSuggestedQuestions(from: transcript)
            }
            self.suggestedQuestions = finalSQ
        self.calculateAndSetWorthItScore()
        self.refreshDecisionCardIfPossible(videoId: videoId)
            self.promptDecisionCardIfReady()

            // Done
            self.updateProgress(1.0, message: "Analysis Complete")
            Logger.shared.info("Full analysis completed for \(videoId)", category: .analysis)
            AnalyticsService.shared.logVideoAnalysisCompleted(
                videoId: videoId,
                score: self.worthItScore ?? 0,
                hasComments: !(self.llmAnalyzedComments.isEmpty)
            )
            if self.minimumDisplayTimerTask == nil {
                if self.currentScreenOverride != .showingAskAnything &&
                   self.currentScreenOverride != .showingEssentials {
                    self.viewState = .showingInitialOptions
                    self.promptDecisionCardIfReady()
                }
            }
            releaseUsageReservation(for: videoId, revertIfNeeded: false)
        } catch {
            Logger.shared.error("Error during non-stream full analysis for \(videoId): \(error.localizedDescription)", category: .analysis, error: error)
            AnalyticsService.shared.logVideoAnalysisFailed(videoId: videoId, error: error.localizedDescription)
            showFriendlyError(for: error, videoId: videoId)
            updateProgress(1.0, message: "Analysis Failed")
        }
    }

    private func preprocessTranscriptVariants(_ transcript: String) async -> (stripped: String, cleaned: String) {
        await Task.detached(priority: .userInitiated) {
            let stripped = transcript.stripTimestamps()
            let resolvedStripped = stripped.isEmpty ? transcript : stripped
            let cleaned = resolvedStripped.cleanedForLLM(alreadyStripped: true)
            let resolvedCleaned = cleaned.isEmpty ? resolvedStripped : cleaned
            return (resolvedStripped, resolvedCleaned)
        }.value
    }

    private func fetchTranscript(videoId: String) async throws -> String {
        let cache = cacheManager
        if let cachedTranscript = await cache.loadTranscript(for: videoId) {
            Logger.shared.info("Transcript cache HIT for \(videoId)", category: .cache)
            return cachedTranscript
        }
        Logger.shared.info("Fetching transcript from API for \(videoId)", category: .networking)
        let transcript = try await apiManager.fetchTranscript(videoId: videoId)
        await cache.saveTranscript(transcript, for: videoId)
        return transcript
    }

    private func fetchComments(videoId: String) async throws -> [String] {
        let cache = cacheManager
        if let cachedComments = await cache.loadComments(for: videoId) {
            Logger.shared.info("Comments cache HIT for \(videoId). Count: \(cachedComments.count). First: \(cachedComments.first ?? "none")", category: .cache)
            return cachedComments
        }
        Logger.shared.info("Fetching comments from API for \(videoId)", category: .networking)
        let comments = try await apiManager.fetchComments(videoId: videoId)
        Logger.shared.info("Fetched \(comments.count) comments from API for \(videoId). First: \(comments.first ?? "none")", category: .networking)
        await cache.saveComments(comments, for: videoId)
        return comments
    }

    // MARK: - Decision Card helpers
    func presentDecisionCard(_ model: DecisionCardModel) {
        decisionCardModel = model
        if let videoId = currentVideoID, decisionCardShownVideoIDs.contains(videoId) {
            hasShownDecisionCardForCurrentVideo = true
            shouldPromptDecisionCard = false
        } else {
            shouldPromptDecisionCard = true
        }
    }

    func consumeDecisionCardPrompt() {
        shouldPromptDecisionCard = false
    }

    func markDecisionCardShownIfNeeded() {
        guard let videoId = currentVideoID else { return }
        decisionCardShownVideoIDs.insert(videoId)
        hasShownDecisionCardForCurrentVideo = true
    }

    private func calculateAndSetWorthItScore() {
        let transcriptText = transcriptForAnalysis ?? rawTranscript ?? ""
        let lowTranscriptQuality = transcriptText.count < 600
        let depthBase = lowTranscriptQuality ? 0.25 : 0.4
        let depthRaw = essentialsCommentAnalysis?.contentDepthScore
        let depthNormalized = max(0.0, min(depthRaw ?? depthBase, 1.0))
        let sentimentRaw = essentialsCommentAnalysis?.overallCommentSentimentScore
        let initialCommentSentiment = max(0.0, min(sentimentRaw ?? 0.0, 1.0))

        // "Why this depth score" - ONLY transcript-based depth evidence
        // Use depthExplanation from comment insights if available, otherwise empty
        var contentHighlights: [String] = []
        var contentWatchouts: [String] = []
        
        if let depthExplanation = essentialsCommentAnalysis?.depthExplanation {
            contentHighlights = uniqueNonEmpty(depthExplanation.strengths)
            contentWatchouts = uniqueNonEmpty(depthExplanation.weaknesses)
        }

        // "What viewers are saying" - ONLY unique comment insights (not shown in Decision Card)
        let positiveThemes = analysisResult?.topThemes?.filter { ($0.sentimentScore ?? 0) > 0.1 }.map { $0.theme } ?? []
        let negativeThemes = analysisResult?.topThemes?.filter { ($0.sentimentScore ?? 0) < -0.1 }.map { $0.theme } ?? []
        var commentHighlights = uniqueNonEmpty(positiveThemes)
        var commentWatchouts = uniqueNonEmpty(negativeThemes)
        let commentSummary = analysisResult?.CommentssentimentSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let viewerThemes = makeViewerThemes(from: analysisResult?.topThemes)
        let viewerTips = uniqueNonEmpty(analysisResult?.viewerTips ?? [])
        let openQuestions = uniqueNonEmpty(analysisResult?.openQuestions ?? [])

        // Add sentiment summary at the beginning if available
        if let sentimentSummary = analysisResult?.CommentssentimentSummary, !sentimentSummary.isEmpty {
            commentHighlights.insert(sentimentSummary, at: 0)
        }
        let spamRatio: Double? = {
            if let reported = analysisResult?.spamRatio {
                return max(0.0, min(reported, 1.0))
            }
            return nil
        }()
        let commentsAnalyzedCount: Int? = {
            if !llmAnalyzedComments.isEmpty { return llmAnalyzedComments.count }
            return analysisResult?.topThemes?.count
        }()
        let hasDepthSignal = depthRaw != nil || analysisResult != nil
        let hasCommentSignal = sentimentRaw != nil || !(llmAnalyzedComments.isEmpty)
        guard hasDepthSignal || hasCommentSignal else {
            worthItScore = nil
            scoreBreakdownDetails = nil
            return
        }

        let commentCount = commentsAnalyzedCount ?? 0
        let spamPenaltyFactor: Double = {
            guard let ratio = spamRatio, ratio > 0.25 else { return 1.0 }
            if ratio >= 0.5 { return 0.5 }
            // Linearly temper between 0.25 -> 0.5 spam
            let delta = ratio - 0.25
            return max(0.5, 1.0 - (delta * 2.0))
        }()

        let commentWeight: Double = {
            if commentCount <= 0 { return 0.0 }
            // Smooth ramp: 0 → 0.4 over 0–30 comments
            let clamped = min(Double(commentCount), 30.0)
            var weight = 0.4 * (clamped / 30.0)
            // If spam is present, scale down comment weight
            if let ratio = spamRatio {
                if ratio >= 0.4 { weight *= 0.4 }
                else if ratio >= 0.25 { weight *= 0.6 }
            }
            return weight
        }()
        let depthWeight = max(0.3, 1.0 - commentWeight)
        let commentSentimentNormalized = initialCommentSentiment * spamPenaltyFactor

        var blendedScore = (depthNormalized * depthWeight) + (commentSentimentNormalized * commentWeight)

        // Post-blend spread/compress to pull mids down and let highs pop
        if blendedScore > 0.7 {
            let excess = blendedScore - 0.7
            blendedScore = min(0.7 + excess * 1.25, 0.98)
        } else if blendedScore >= 0.55 {
            let midBand = blendedScore - 0.55
            blendedScore = 0.55 + midBand * 0.9
        }

        // Stricter caps for low depth; require volume + high sentiment to escape
        if depthNormalized < 0.25 && commentSentimentNormalized < 0.30 {
            blendedScore = min(blendedScore, 0.55)
        } else if depthNormalized < 0.25 {
            blendedScore = min(blendedScore, 0.60)
        } else if depthNormalized < 0.40 {
            if commentCount >= 15 && commentSentimentNormalized >= 0.78 {
                blendedScore = min(blendedScore, 0.72)
            } else {
                blendedScore = min(blendedScore, 0.65)
            }
        } else if commentSentimentNormalized < 0.30 && commentCount > 0 {
            blendedScore = min(blendedScore, 0.70)
        }

        // Synergy boost: reward videos that are strong on both depth and sentiment
        if depthNormalized > 0.78 && commentSentimentNormalized > 0.78 && commentCount >= 12 && spamPenaltyFactor >= 0.9 {
            let avg = (depthNormalized + commentSentimentNormalized) / 2.0
            let boost = max(0.0, (avg - 0.78)) * 0.35 // Up to ~0.077 when avg ≈ 1.0
            blendedScore = min(blendedScore + boost, 0.98)
        }

        var finalScoreValue = max(0.0, min(blendedScore, 1.0))

        // Uncertainty tempering: small samples or spam-tempered sentiment lower the score slightly
        if commentCount > 0 && commentCount < 8 {
            finalScoreValue *= 0.97
        }
        if spamPenaltyFactor < 1.0 {
            finalScoreValue *= 0.97
        }

        let finalScorePercent = (finalScoreValue * 1000).rounded() / 10.0 // keep one decimal internally
        self.worthItScore = finalScorePercent

        // Note: We intentionally do NOT add decisionReasons, decisionLearnings, decisionBestMoment,
        // decisionSkip, signalQualityNote, or viewerTips here because:
        // - decisionReasons: Already shown in Decision Card hero text
        // - decisionLearnings: Already shown in Decision Card "You'll learn" section
        // - decisionBestMoment: Already shown in Decision Card "Best part" chip
        // - decisionSkip: Already shown in Decision Card skip note
        // - signalQualityNote: Already shown in Decision Card comments chip
        // - viewerTips: Not generated by current prompt (always null)
        // These fields are used elsewhere in the UI, so we avoid duplication in score breakdown.

        contentHighlights = uniqueNonEmpty(contentHighlights)
        contentWatchouts = uniqueNonEmpty(contentWatchouts)
        commentHighlights = uniqueNonEmpty(commentHighlights)
        commentWatchouts = uniqueNonEmpty(commentWatchouts)

        let scoreReasonLine = makeScoreReasonLine(
            llmLine: essentialsCommentAnalysis?.scoreReasonLine,
            depth: depthNormalized,
            sentiment: commentSentimentNormalized,
            hasComments: commentCount > 0,
            spamRatio: spamRatio
        )

        self.scoreBreakdownDetails = ScoreBreakdown(
            contentDepthScore: depthNormalized,
            commentSentimentScore: commentSentimentNormalized,
            hasComments: commentCount > 0,
            scoreReasonLine: scoreReasonLine,
            contentDepthRaw: depthNormalized,
            commentSentimentRaw: sentimentRaw ?? 0.0,
            finalScore: finalScorePercent,
            videoTitle: analysisResult?.videoTitle ?? currentVideoTitle ?? "Video",
            positiveCommentThemes: positiveThemes,
            negativeCommentThemes: negativeThemes,
            contentHighlights: contentHighlights,
            contentWatchouts: contentWatchouts,
            commentHighlights: commentHighlights,
            commentWatchouts: commentWatchouts,
            spamRatio: spamRatio,
            commentsAnalyzed: commentsAnalyzedCount,
            commentSummary: commentSummary,
            viewerThemes: viewerThemes,
            viewerTips: viewerTips,
            openQuestions: openQuestions
        )

        Logger.shared.info("Worth-It Score calculated: \(self.worthItScore ?? -1). Depth: \(depthNormalized), Comment Sentiment: \(sentimentRaw ?? 0)", category: .services)

        // Trigger Decision Card after gauge animation completes (1.5s animation + small buffer)
        if let videoId = currentVideoID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { // Wait for gauge to fully animate
                self.refreshDecisionCardIfPossible(videoId: videoId)
            }
        }
    }

    // MARK: - Decision Card Construction
    private func refreshDecisionCardIfPossible(videoId: String) {
        // Allow a provisional card as soon as comment insights land; fall back to transcript takeaways when available.
        guard analysisResult != nil || essentialsCommentAnalysis != nil else { return }

        let resolvedScore = worthItScore ?? 0
        let decision = essentialsCommentAnalysis
        let analysis = analysisResult
        let verdict = verdictForScore(resolvedScore)

        let depthDetail: String = {
            if let reason = decision?.decisionReasons.first, !reason.isEmpty {
                return truncateForCard(reason, max: 110)
            }
            if let takeaway = analysis?.takeaways?.first, !takeaway.isEmpty {
                return truncateForCard(takeaway, max: 110)
            }
            let depthPercent = Int((essentialsCommentAnalysis?.contentDepthScore ?? 0) * 100)
            return depthPercent > 0 ? "Depth: \(depthPercent)%" : "Depth insights ready"
        }()

        let commentsCount = llmAnalyzedComments.count
        let sentimentPercent = essentialsCommentAnalysis?.overallCommentSentimentScore.map { Int($0 * 100) }
        var commentsDetail = commentsCount > 0 ? "\(commentsCount) comments analyzed" : "No comments yet - score based on content"
        if let sent = sentimentPercent {
            commentsDetail = "\(commentsDetail) · Sentiment \(sent)%"
        }
        if let quality = decision?.signalQualityNote, !quality.isEmpty {
            commentsDetail = quality
        }
        commentsDetail = truncateForCard(commentsDetail, max: 110)

        let jumpDetail = truncateForCard(decision?.decisionBestMoment ?? "Best moment coming soon", max: 110)
        let bestStart = parseBestMomentSeconds(from: decision?.decisionBestMoment)

        let depthChip = DecisionProofChip(
            iconName: "doc.text.magnifyingglass",
            title: "Depth",
            detail: depthDetail
        )

        let commentsChip = DecisionProofChip(
            iconName: "bubble.left.and.bubble.right.fill",
            title: "Comments",
            detail: commentsDetail
        )

        let jumpChip = DecisionProofChip(
            iconName: "arrow.right.circle.fill",
            title: "Best part",
            detail: jumpDetail
        )

        // Use the enhanced reason directly - it's already optimized for the UI (≤140 chars)
        let reasonText = decision?.decisionReasons.first ?? analysis?.takeaways?.first ?? "Your Worth-It verdict is ready."
        let model = DecisionCardModel(
            title: analysis?.videoTitle ?? currentVideoTitle ?? "Video",
            reason: reasonText,
            scoreReasonLine: scoreBreakdownDetails?.scoreReasonLine,
            score: resolvedScore,
            depthChip: depthChip,
            commentsChip: commentsChip,
            jumpChip: jumpChip,
            verdict: verdict,
            timeValue: formattedTimeValue(seconds: analysis?.videoDurationSeconds),
            thumbnailURL: currentVideoThumbnailURL,
            bestStartSeconds: bestStart,
            learnings: (decision?.decisionLearnings ?? analysis?.takeaways ?? []).prefix(2).map { $0 },
            skipNote: decision?.decisionSkip,
            signalQuality: decision?.signalQualityNote,
            topQuestion: suggestedQuestions.first
        )

        presentDecisionCard(model)
    }

    private func verdictForScore(_ score: Double) -> DecisionVerdict {
        if score >= 70 { return .worthIt }
        if score <= 45 { return .skip }
        return .maybe
    }

    private func parseBestMomentSeconds(from text: String?) -> Int? {
        guard let t = text else { return nil }
        // Expect formats like "mm:ss - ..." or "m:ss"
        let parts = t.split(separator: " ").first ?? ""
        let timeParts = parts.split(separator: ":")
        guard timeParts.count == 2,
              let minutes = Int(timeParts[0]),
              let seconds = Int(timeParts[1]),
              seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }

    private func formattedTimeValue(seconds: Int?) -> String? {
        guard let total = seconds, total > 0 else { return nil }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m watch"
        }
        let roundedMinutes = max(1, Int((Double(total) / 60.0).rounded()))
        return "\(roundedMinutes)m watch"
    }

    private func makeScoreReasonLine(
        llmLine: String?,
        depth: Double,
        sentiment: Double,
        hasComments: Bool,
        spamRatio: Double?
    ) -> String {
        if let spam = spamRatio, spam >= 0.4 {
            return "Score tempered by spammy comments."
        }

        if let line = llmLine?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty,
           line.count <= 90,
           !line.contains("\n")
        {
            return line
        }

        if !hasComments {
            return "Solid content depth; no comments (neutral)."
        }

        switch (depth, sentiment) {
        case (let d, let s) where d >= 0.82 && s >= 0.82:
            return "Highly actionable and loved by viewers."
        case (let d, let s) where d >= 0.78 && s >= 0.65:
            return "Deep and specific; viewers mostly positive."
        case (let d, let s) where d >= 0.70 && s < 0.60:
            return "Strong depth; reactions are mixed."
        case (let d, let s) where d < 0.60 && s >= 0.78:
            return "Light depth, carried by happy viewers."
        case (let d, let s) where d >= 0.65 && s < 0.45:
            return "Good depth, but comments raise concerns."
        default:
            return "Balanced depth and sentiment; provisional on comments."
        }
    }

    private func truncateForCard(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: max)
        return text[text.startIndex..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    

    // MARK: - Fallbacks
    private func generateFallbackSuggestedQuestions(from transcript: String?) -> [String] {
        // Very light heuristic for Spanish vs English
        let t = (transcript ?? "").lowercased()
        let isSpanish = [" el ", " la ", " de ", " que ", " y ", " para "]
            .contains { t.contains($0) }
        if isSpanish {
            return [
                "Idea clave?",
                "Pasos prácticos?",
                "Por qué importa?"
            ]
        } else {
            return [
                "Key idea?",
                "Practical steps?",
                "Why it matters?"
            ]
        }
    }

    func requestEssentials() {
        // Allow navigating to Essentials as soon as score is shown, or when full results are ready
        guard analysisResult != nil || worthItScore != nil else {
            Logger.shared.warning("Essentials requested but no score/result yet. State: \(viewState)", category: .ui)
            return
        }
        if let videoId = currentVideoID {
            AnalyticsService.shared.logEssentialsViewed(videoId: videoId)
        }
        viewState = .showingEssentials
    }

    func requestAskAnything() {
        let cache = cacheManager
        Task { @MainActor in
            if let vid = currentVideoID,
               let cached = await cache.loadQAMessages(for: vid),
               !cached.isEmpty {
                qaMessages = cached
            } else if qaMessages.isEmpty {
                qaMessages.append(ChatMessage(content: "Hi! What would you like to know about this video?", isUser: false))
            }
            viewState = .showingAskAnything
        }
    }

    func askTopQuestionIfAvailable(_ question: String?) {
        Task { @MainActor in
            guard let prompt = question, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                requestAskAnything()
                return
            }
            qaInputText = prompt
            requestAskAnything()
            sendQAQuestion()
        }
    }

    func sendQAQuestion() {
        Task { @MainActor in
            await performSendQAQuestion()
        }
    }

    @MainActor
    private func performSendQAQuestion() async {
        let trimmedInput = qaInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            Logger.shared.warning("Cannot send Q&A: input text missing.", category: .ui)
            return
        }

        // Free-tier gating for Q&A usage
        if !isUserSubscribed, let videoId = currentVideoID {
            let allowance = await qaUsageTracker.registerQAQuestion(
                for: videoId,
                dailyLimit: AppConstants.dailyFreeQAQuestionLimit,
                perVideoLimit: AppConstants.freeQuestionsPerVideoLimit
            )

            if allowance.allowed == false {
                hasHitQALimit = true
                lastQALimitSnapshot = allowance.snapshot
                presentQAPaywall(from: allowance.snapshot)
                return
            } else {
                hasHitQALimit = false
                lastQALimitSnapshot = allowance.snapshot
            }
        } else {
            hasHitQALimit = false
        }

        let userMessage = ChatMessage(content: trimmedInput, isUser: true)
        qaMessages.append(userMessage)
        let cache = cacheManager
        if let vid = self.currentVideoID {
            let snapshot = qaMessages
            Task {
                await cache.saveQAMessages(snapshot, for: vid)
            }
        }
        let currentQuestion = trimmedInput
        
        // Log analytics
        if let videoId = currentVideoID {
            AnalyticsService.shared.logQAQuestionAsked(videoId: videoId, questionLength: currentQuestion.count)
        }
        
        qaInputText = ""
        isQaLoading = true
        userFriendlyError = nil
        hasCommentsAvailableForError = false

        let history = Array(qaMessages.dropLast().suffix(6))
        let initialTranscriptForQA = self.transcriptForAnalysis ?? self.rawTranscript ?? ""
        let videoIdForCache = currentVideoID

        Task {
            var workingTranscript = initialTranscriptForQA

            if workingTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let vid = videoIdForCache {
                if let cachedTranscript = await cache.loadTranscript(for: vid) {
                    workingTranscript = cachedTranscript
                    let variants = await self.preprocessTranscriptVariants(cachedTranscript)
                    await MainActor.run {
                        self.rawTranscript = cachedTranscript
                        self.transcriptForAnalysis = variants.stripped
                        self.cleanedTranscriptForLLM = variants.cleaned
                    }
                } else if let fetched = try? await self.apiManager.fetchTranscript(videoId: vid) {
                    workingTranscript = fetched
                    await cache.saveTranscript(fetched, for: vid)
                    let variants = await self.preprocessTranscriptVariants(fetched)
                    await MainActor.run {
                        self.rawTranscript = fetched
                        self.transcriptForAnalysis = variants.stripped
                        self.cleanedTranscriptForLLM = variants.cleaned
                    }
                }
            }

            if workingTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let fallbackMessage = "Transcript unavailable for this video right now."
                await MainActor.run {
                    self.qaMessages.append(ChatMessage(content: "Sorry, I couldn't answer that. \(fallbackMessage)", isUser: false))
                    self.isQaLoading = false
                }
                if let vid = videoIdForCache {
                    let messages = await MainActor.run { self.qaMessages }
                    await cache.saveQAMessages(messages, for: vid)
                }
                return
            }

            do {
                let response = try await apiManager.answerQuestion(
                    transcript: workingTranscript,
                    question: currentQuestion,
                    history: history
                )
                await MainActor.run {
                    self.qaMessages.append(ChatMessage(content: response.answer, isUser: false))
                }
                if let vid = videoIdForCache {
                    let messages = await MainActor.run { self.qaMessages }
                    await cache.saveQAMessages(messages, for: vid)
                }
            } catch {
                Logger.shared.error("Failed to get Q&A answer: \(error.localizedDescription)", category: .services, error: error)
                let fallbackMessage = (error as? NetworkError)?.localizedDescription ?? error.localizedDescription
                let errorMessage = "Sorry, I couldn't answer that. \(fallbackMessage)"
                await MainActor.run {
                    self.qaMessages.append(ChatMessage(content: errorMessage, isUser: false))
                }
                if let vid = videoIdForCache {
                    let messages = await MainActor.run { self.qaMessages }
                    await cache.saveQAMessages(messages, for: vid)
                }
            }
            await MainActor.run { self.isQaLoading = false }
        }
    }

    func selectSuggestedQuestion(_ question: String) {
        qaInputText = question
        sendQAQuestion()
    }

    func askKeyQuestion(_ question: String) {
        // Switch to the Ask Anything screen
        viewState = .showingAskAnything
        
        // Set the question and send it immediately
        qaInputText = question
        sendQAQuestion()
    }

    func returnToInitialOptions() {
        userFriendlyError = nil
        viewState = .showingInitialOptions
    }

    // Public helper to return to the home (idle) screen for starting a new analysis
    func goToHome() {
        resetForNewAnalysis()
    }

    private func resetForNewAnalysis() {
        Logger.shared.info("Resetting MainViewModel for new analysis.", category: .lifecycle)
        activeAnalysisTask?.cancel()
        activeAnalysisTask = nil
        fullAnalysisTask?.cancel()
        fullAnalysisTask = nil
        minimumDisplayTimerTask?.cancel()
        minimumDisplayTimerTask = nil
        viewState = .idle
        processingProgress = 0.0
        userFriendlyError = nil
        analysisResult = nil
        worthItScore = nil
        scoreBreakdownDetails = nil
        essentialsCommentAnalysis = nil
        decisionCardModel = nil
        shouldPromptDecisionCard = false
        qaMessages = []
        qaInputText = ""
        isQaLoading = false
        suggestedQuestions = []
        currentVideoID = nil
        currentVideoTitle = nil
        currentVideoThumbnailURL = nil
        rawTranscript = nil
        transcriptForAnalysis = nil
        cleanedTranscriptForLLM = nil
        hasShownDecisionCardForCurrentVideo = false

        // Clear comment caches
        allFetchedComments = []
        llmAnalyzedComments = []
        
        // Reset GPT thread & intro‑cache so a fresh video starts brand‑new context
        apiManager.resetConversationState()

        usageReservations.removeAll()
        latestUsageSnapshot = nil
        activePaywall = nil
        paywallLoggedImpression = false
        hasHitQALimit = false
        lastQALimitSnapshot = nil
    }

    func clearCurrentError() {
        userFriendlyError = nil
        if case .error = viewState { // Check if current state is error
            viewState = analysisResult != nil ? .showingInitialOptions : .idle
        }
    }
    
    // MARK: - Cache Management
    
    func clearSessionCache() {
        processedVideoIDsThisSession.removeAll()
        Logger.shared.info("Session cache cleared.", category: .cache)
    }

    // MARK: - Paywall Presentation

    private func presentPaywall(reason: PaywallReason, usageSnapshot: UsageTracker.Snapshot, qaSnapshot: QAUsageTracker.Snapshot? = nil) {
        activePaywall = PaywallContext(reason: reason, usageSnapshot: usageSnapshot, qaSnapshot: qaSnapshot)
        paywallLoggedImpression = false
        latestUsageSnapshot = usageSnapshot
    }

    func requestManualPaywallPresentation() {
        Task { @MainActor in
            let snapshot = await usageTracker.snapshot(dailyLimit: AppConstants.dailyFreeAnalysisLimit)
            presentPaywall(reason: .manual, usageSnapshot: snapshot)
        }
    }

    private func presentQAPaywall(from snapshot: QAUsageTracker.Snapshot) {
        let mapped = UsageTracker.Snapshot(
            date: snapshot.date,
            count: snapshot.totalCount,
            limit: snapshot.limitPerDay,
            remaining: snapshot.remainingToday,
            videoIds: []
        )
        presentPaywall(reason: .qaLimitReached, usageSnapshot: mapped, qaSnapshot: snapshot)
    }

    func requestQAPaywallPresentation() {
        Task { @MainActor in
            if let snapshot = lastQALimitSnapshot {
                presentQAPaywall(from: snapshot)
                return
            }
            if let videoId = currentVideoID {
                let snapshot = await qaUsageTracker.snapshot(
                    dailyLimit: AppConstants.dailyFreeQAQuestionLimit,
                    perVideoLimit: AppConstants.freeQuestionsPerVideoLimit,
                    videoId: videoId
                )
                lastQALimitSnapshot = snapshot
                hasHitQALimit = snapshot.totalCount >= snapshot.limitPerDay || snapshot.countForVideo >= snapshot.limitPerVideo
                presentQAPaywall(from: snapshot)
            }
        }
    }

    func paywallPresented(reason: PaywallReason) {
        guard paywallLoggedImpression == false else { return }
        paywallLoggedImpression = true
        let snapshot = activePaywall?.usageSnapshot ?? latestUsageSnapshot
        AnalyticsService.shared.logPaywallShown(
            trigger: reason.analyticsLabel,
            used: snapshot?.count ?? 0,
            limit: snapshot?.limit ?? AppConstants.dailyFreeAnalysisLimit
        )
    }

    func dismissPaywall() {
        dismissPaywall(afterSuccessfulPurchase: false)
    }

    private func dismissPaywall(afterSuccessfulPurchase: Bool) {
        guard activePaywall != nil else { return }
        activePaywall = nil
        paywallLoggedImpression = false
        latestUsageSnapshot = nil
        AnalyticsService.shared.logPaywallDismissed(purchased: afterSuccessfulPurchase)
    }

    func paywallPurchaseTapped(productId: String) {
        AnalyticsService.shared.logPaywallPurchaseTapped(productId: productId)
    }

    func paywallPurchaseSucceeded(productId: String) {
        AnalyticsService.shared.logPaywallPurchaseSucceeded(productId: productId)
        dismissPaywall(afterSuccessfulPurchase: true)
    }

    func paywallPurchaseCancelled(productId: String) {
        AnalyticsService.shared.logPaywallPurchaseCancelled(productId: productId)
    }

    func paywallPurchaseFailed(productId: String) {
        AnalyticsService.shared.logPaywallPurchaseFailed(productId: productId)
    }

    func paywallRestoreTapped() {
        AnalyticsService.shared.logPaywallRestoreTapped()
    }

    func paywallManageTapped() {
        AnalyticsService.shared.logPaywallManageTapped()
    }

    func paywallPlanSelected(productId: String) {
        AnalyticsService.shared.logPaywallPlanSelected(productId: productId)
    }

    func paywallCheckoutStarted(productId: String, source: String, isTrial: Bool) {
        AnalyticsService.shared.logPaywallCheckoutStarted(productId: productId, source: source, isTrial: isTrial)
    }

    func paywallMaybeLaterTapped(trialEligible: Bool = false, trialViewPresented: Bool = false) {
        AnalyticsService.shared.logPaywallMaybeLater(trialEligible: trialEligible, trialViewPresented: trialViewPresented)
    }

    func consumeManageSubscriptionsDeepLinkRequest() {
        shouldOpenManageSubscriptions = false
    }

    func setPublicError(message: String, canRetry: Bool, videoIdForRetry: String? = nil) {
        let videoToRetry = videoIdForRetry ?? self.currentVideoID
        if let id = videoToRetry {
            releaseUsageReservation(for: id, revertIfNeeded: true)
        }
        self.userFriendlyError = UserFriendlyError(message: message, canRetry: canRetry, videoIdForRetry: videoToRetry)
        self.viewState = .error
        activeAnalysisTask?.cancel()
        activeAnalysisTask = nil
        fullAnalysisTask?.cancel()
        fullAnalysisTask = nil
        minimumDisplayTimerTask?.cancel()
        minimumDisplayTimerTask = nil
        AnalyticsService.shared.logError(message, context: "AnalysisError", videoId: videoToRetry)
    }

    func retryLastFailedAnalysis() {
        guard let errorInfo = userFriendlyError, errorInfo.canRetry, let videoId = errorInfo.videoIdForRetry else {
            Logger.shared.warning("Retry called but no retryable error or videoId found.", category: .ui)
            clearCurrentError()
            if viewState == .error { viewState = .idle }
            return
        }

        Logger.shared.info("Retrying analysis for video ID: \(videoId)", category: .lifecycle)
        clearCurrentError()

        let retryURLString = "https://www.youtube.com/watch?v=\(videoId)"
        if let retryURL = URL(string: retryURLString) {
            processedVideoIDsThisSession.remove(videoId)
            processSharedURL(retryURL)
        } else {
            Logger.shared.error("Failed to create retry URL for video ID: \(videoId)", category: .lifecycle)
            setPublicError(message: "Internal error: Could not retry.", canRetry: false)
        }
    }

    private func startMinimumDisplayTimer() {
        // Only enforce minimum display delay if we do not have cached results
        guard self.analysisResult == nil else {
            // Already have a cached result; no delay needed
            Logger.shared.debug("Skipping minimum display timer - cached results available", category: .ui)
            return
        }
        
        minimumDisplayTimerTask?.cancel()
        let startTime = Date()
        Logger.shared.debug("Starting minimum display timer (\(minimumDisplayTime)s)...", category: .ui)

        minimumDisplayTimerTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(minimumDisplayTime * 1_000_000_000))
                try Task.checkCancellation()

                await MainActor.run {
                    let elapsedTime = Date().timeIntervalSince(startTime)
                    Logger.shared.info("Minimum display timer finished (\(String(format: "%.2f", elapsedTime))s). Current state: \(self.viewState)", category: .ui)
                    self.minimumDisplayTimerTask = nil

                    // After minimum time, transition to options unless user navigated elsewhere
                    if self.viewState == .processing {
                        if self.currentScreenOverride != .showingAskAnything &&
                           self.currentScreenOverride != .showingEssentials {
                            Logger.shared.info("Minimum display time reached. Transitioning to initial options.", category: .ui)
                            self.viewState = .showingInitialOptions
                        } else {
                            Logger.shared.info("Minimum display time reached but user already navigated elsewhere. No transition.", category: .ui)
                        }
                    } else {
                        Logger.shared.info("Minimum display timer finished but analysis completed or state changed.", category: .ui)
                    }
                }
            } catch is CancellationError {
                Logger.shared.info("Minimum display timer cancelled.", category: .ui)
                await MainActor.run { self.minimumDisplayTimerTask = nil }
            } catch {
                Logger.shared.error("Error in minimum display timer: \(error.localizedDescription)", category: .ui, error: error)
                await MainActor.run { self.minimumDisplayTimerTask = nil }
            }
        }
    }

    private func updateProgress(_ value: Double, message: String? = nil) {
        let newProgress = min(max(value, 0.0), 1.0)
        self.processingProgress = newProgress
        if let msg = message {
            Logger.shared.debug("Progress: \(Int(newProgress * 100))% - \(msg)", category: .services)
        }
    }

    private func extractVideoID(from url: URL) -> String? {
        do {
            return try URLParser.extractVideoID(from: url)
        } catch let error as URLParserError { // Be specific about error type
            Logger.shared.error("URLParserError: \(error.localizedDescription)", category: .parsing, error: error)
            return nil
        } catch {
            Logger.shared.error("Unknown error parsing URL: \(error.localizedDescription)", category: .parsing, error: error)
            return nil
        }
    }

    deinit {
        activeAnalysisTask?.cancel()
        fullAnalysisTask?.cancel()
        minimumDisplayTimerTask?.cancel()
        Logger.shared.info("MainViewModel deinitialized.", category: .lifecycle)
    }

    // Helper for showing a friendly error message for a given error and videoId
    private func showFriendlyError(for error: Error, videoId: String?) {
        if let netErr = error as? NetworkError {
            setPublicError(
                message: netErr.localizedDescription,
                canRetry: {
                    if case .rateLimited = netErr {
                        return false
                    } else {
                        return true
                    }
                }(),
                videoIdForRetry: videoId
            )
        } else if (error as? CancellationError) == nil {
            setPublicError(
                message: error.localizedDescription,
                canRetry: true,
                videoIdForRetry: videoId
            )
        }
    }
}

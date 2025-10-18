//
//  CacheManager.swift
//  WorthIt

import Foundation

actor CacheManager {
    static let shared = CacheManager()

    private let memoryCache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var recentAnalysesCache: [RecentAnalysisItem] = []
    private var recentAnalysesDirty: Bool = true

    private init() {
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) {
            cacheDirectory = groupURL.appendingPathComponent("WorthItAICache", isDirectory: true)
        } else {
            Logger.shared.warning("App Group container not available. Falling back to local Caches directory.", category: .cache)
            let fallbackBase = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            cacheDirectory = fallbackBase.appendingPathComponent("WorthItAICache", isDirectory: true)
        }

        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch let creationError {
            Logger.shared.error("Failed to create cache directory at \(cacheDirectory.path) – \(creationError.localizedDescription)", category: .cache)
        }
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        Logger.shared.info("CacheManager initialized. Disk cache location: \(cacheDirectory.path)", category: .cache)
    }

    private func fileURL<T>(for key: String, type: T.Type) -> URL {
        let typeName = String(describing: T.self)
        let fileName = "\(key)_\(typeName).json"
            .replacingOccurrences(of: "[^a-zA-Z0-9_.-]", with: "_", options: .regularExpression)
        return cacheDirectory.appendingPathComponent(fileName)
    }

    private func stringFileURL(for key: String) -> URL {
        let fileName = "\(key)_String.txt"
            .replacingOccurrences(of: "[^a-zA-Z0-9_.-]", with: "_", options: .regularExpression)
        return cacheDirectory.appendingPathComponent(fileName)
    }

    private func saveDataToCache<T: Codable>(_ data: T, forKey key: String) {
        do {
            let encodedData = try JSONEncoder().encode(data)
            memoryCache.setObject(encodedData as NSData, forKey: key as NSString, cost: encodedData.count)
            let url = fileURL(for: key, type: T.self)
            try encodedData.write(to: url, options: .atomic)
            Logger.shared.debug("Saved \(T.self) to cache for key: \(key)", category: .cache)
            markRecentAnalysesDirtyIfNeeded(for: key)
        } catch let saveError {
            Logger.shared.error("Failed to save \(T.self) to cache for key: \(key). – \(saveError.localizedDescription)", category: .cache)
        }
    }

    private func loadDataFromCache<T: Codable>(forKey key: String, type: T.Type) -> T? {
        if let nsData = memoryCache.object(forKey: key as NSString) {
            do {
                let decodedData = try JSONDecoder().decode(T.self, from: nsData as Data)
                Logger.shared.debug("Loaded \(T.self) from memory cache for key: \(key)", category: .cache)
                return decodedData
            } catch let decodeError {
                Logger.shared.warning("Failed to decode \(T.self) from memory cache for key: \(key). – \(decodeError.localizedDescription)", category: .cache)
                memoryCache.removeObject(forKey: key as NSString)
            }
        }

        let url = fileURL(for: key, type: T.self)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let fileData = try Data(contentsOf: url)
            let decodedData = try JSONDecoder().decode(T.self, from: fileData)
            memoryCache.setObject(fileData as NSData, forKey: key as NSString, cost: fileData.count)
            Logger.shared.debug("Loaded \(T.self) from disk cache for key: \(key)", category: .cache)
            return decodedData
        } catch let loadError {
            Logger.shared.error("Failed to load or decode \(T.self) from disk cache for key: \(key). – \(loadError.localizedDescription)", category: .cache)
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func saveContentAnalysis(_ analysis: ContentAnalysis, for videoId: String) {
        saveDataToCache(analysis, forKey: "contentAnalysis_\(videoId)")
    }

    func loadContentAnalysis(for videoId: String) -> ContentAnalysis? {
        let result = loadDataFromCache(forKey: "contentAnalysis_\(videoId)", type: ContentAnalysis.self)
        if result != nil {
            AnalyticsService.shared.logCacheHit(type: "content_analysis", videoId: videoId)
        } else {
            AnalyticsService.shared.logCacheMiss(type: "content_analysis", videoId: videoId)
        }
        return result
    }

    func saveCommentInsights(_ insights: CommentInsights, for videoId: String) {
        saveDataToCache(insights, forKey: "commentInsights_\(videoId)")
    }

    func loadCommentInsights(for videoId: String) -> CommentInsights? {
        let result = loadDataFromCache(forKey: "commentInsights_\(videoId)", type: CommentInsights.self)
        if result != nil {
            AnalyticsService.shared.logCacheHit(type: "comment_insights", videoId: videoId)
        } else {
            AnalyticsService.shared.logCacheMiss(type: "comment_insights", videoId: videoId)
        }
        return result
    }

    func saveTranscript(_ transcript: String, for videoId: String) {
        let key = "transcript_\(videoId)"
        guard let data = transcript.data(using: .utf8) else {
            Logger.shared.error("Failed to convert transcript string to Data for videoId: \(videoId)", category: .cache)
            return
        }
        let nsData = data as NSData
        memoryCache.setObject(nsData, forKey: key as NSString, cost: nsData.length)
        let url = stringFileURL(for: key)
        do {
            try data.write(to: url, options: .atomic)
            Logger.shared.debug("Saved Transcript (String) to cache for key: \(key)", category: .cache)
            markRecentAnalysesDirty()
        } catch let error {
            Logger.shared.error("Failed to save Transcript (String) to disk for key: \(key) – \(error.localizedDescription)", category: .cache)
        }
    }

    func loadTranscript(for videoId: String) -> String? {
        let key = "transcript_\(videoId)"
        if let nsData = memoryCache.object(forKey: key as NSString),
           let transcript = String(data: nsData as Data, encoding: .utf8) {
            Logger.shared.debug("Loaded Transcript (String) from memory cache for key: \(key)", category: .cache)
            AnalyticsService.shared.logCacheHit(type: "transcript", videoId: videoId)
            return transcript
        }
        let url = stringFileURL(for: key)
        if let data = try? Data(contentsOf: url),
           let transcript = String(data: data, encoding: .utf8) {
            memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
            Logger.shared.debug("Loaded Transcript (String) from disk cache for key: \(key)", category: .cache)
            AnalyticsService.shared.logCacheHit(type: "transcript", videoId: videoId)
            return transcript
        }
        AnalyticsService.shared.logCacheMiss(type: "transcript", videoId: videoId)
        return nil
    }

    func saveComments(_ comments: [String], for videoId: String) {
        saveDataToCache(comments, forKey: "comments_\(videoId)")
    }

    func loadComments(for videoId: String) -> [String]? {
        let result = loadDataFromCache(forKey: "comments_\(videoId)", type: [String].self)
        if result != nil {
            AnalyticsService.shared.logCacheHit(type: "comments", videoId: videoId)
        } else {
            AnalyticsService.shared.logCacheMiss(type: "comments", videoId: videoId)
        }
        return result
    }

    func clearAllMemoryCache() {
        memoryCache.removeAllObjects()
        Logger.shared.info("All memory cache cleared.", category: .cache)
        markRecentAnalysesDirty()
    }

    func clearAllDiskCache() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil, options: [])
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
            Logger.shared.info("All disk cache cleared from: \(cacheDirectory.path)", category: .cache)
            markRecentAnalysesDirty()
        } catch let error {
            Logger.shared.error("Failed to clear disk cache. – \(error.localizedDescription)", category: .cache)
        }
    }

    func clearAllCache() {
        clearAllMemoryCache()
        clearAllDiskCache()
    }

    // MARK: - Q&A Messages Cache
    func saveQAMessages(_ messages: [ChatMessage], for videoId: String) {
        saveDataToCache(messages, forKey: "qa_\(videoId)")
    }

    func loadQAMessages(for videoId: String) -> [ChatMessage]? {
        loadDataFromCache(forKey: "qa_\(videoId)", type: [ChatMessage].self)
    }

    // MARK: - Recent Analyses (no database)
    struct RecentAnalysisItem: Identifiable, Sendable {
        let id = UUID()
        let videoId: String
        let title: String
        let thumbnailURL: URL?
        let finalScore: Double?
        let modifiedAt: Date
    }

    func listRecentAnalyses(limit: Int? = nil) -> [RecentAnalysisItem] {
        if recentAnalysesDirty {
            recentAnalysesCache = rebuildRecentAnalysesCache()
            recentAnalysesDirty = false
        }
        guard let limit else { return recentAnalysesCache }
        return Array(recentAnalysesCache.prefix(limit))
    }

    private func rebuildRecentAnalysesCache() -> [RecentAnalysisItem] {
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            let matches = contents.filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("contentAnalysis_") && name.hasSuffix("_ContentAnalysis.json")
            }

            let sorted = matches.sorted { a, b in
                let aVals = try? a.resourceValues(forKeys: [.contentModificationDateKey])
                let bVals = try? b.resourceValues(forKeys: [.contentModificationDateKey])
                let aDate = aVals?.contentModificationDate ?? Date.distantPast
                let bDate = bVals?.contentModificationDate ?? Date.distantPast
                return aDate > bDate
            }

            var items: [RecentAnalysisItem] = []
            items.reserveCapacity(sorted.count)

            for url in sorted {
                let name = url.lastPathComponent
                let prefix = "contentAnalysis_"
                let suffix = "_ContentAnalysis.json"
                guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { continue }
                let start = name.index(name.startIndex, offsetBy: prefix.count)
                let end = name.index(name.endIndex, offsetBy: -suffix.count)
                let videoId = String(name[start..<end])

                let analysis = loadContentAnalysis(for: videoId)
                let title = analysis?.videoTitle ?? videoId
                let thumbString = analysis?.videoThumbnailUrl
                let fallbackThumb = URL(string: "https://i.ytimg.com/vi/\(videoId)/hq720.jpg")
                let thumbnailURL = URL(string: thumbString ?? "") ?? fallbackThumb

                var finalScore: Double? = nil
                if let insights = loadCommentInsights(for: videoId) {
                    let depth = max(0.0, min(insights.contentDepthScore ?? 0.6, 1.0))
                    let sentiment = max(0.0, min(insights.overallCommentSentimentScore ?? 0.0, 1.0))
                    let value = (depth * 0.60) + (sentiment * 0.40)
                    finalScore = round(value * 100)
                }

                let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let modifiedAt = vals?.contentModificationDate ?? Date()

                items.append(RecentAnalysisItem(
                    videoId: videoId,
                    title: title,
                    thumbnailURL: thumbnailURL,
                    finalScore: finalScore,
                    modifiedAt: modifiedAt
                ))
            }
            return items
        } catch {
            Logger.shared.error("Failed to list recent analyses – \(error.localizedDescription)", category: .cache)
            return []
        }
    }

    private func markRecentAnalysesDirtyIfNeeded(for key: String) {
        if key.hasPrefix("contentAnalysis_") || key.hasPrefix("commentInsights_") {
            markRecentAnalysesDirty()
        }
    }

    private func markRecentAnalysesDirty() {
        recentAnalysesDirty = true
    }
}

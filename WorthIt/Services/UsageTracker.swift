import Foundation

actor UsageTracker {
    struct Snapshot: Codable {
        let date: Date
        let count: Int
        let limit: Int
        let remaining: Int
        var videoIds: [String]
    }

    struct Allowance {
        let allowed: Bool
        let wasCounted: Bool
        let snapshot: Snapshot
    }

    static let shared = UsageTracker()

    private enum Keys {
        static let storageDate = "usage_tracker_storage_date_v1"
        static let storageVideos = "usage_tracker_video_ids_v1"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(calendar: Calendar = .current, defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupID)) {
        self.calendar = calendar
        self.defaults = defaults ?? .standard
    }

    func registerAttempt(for videoId: String, dailyLimit: Int, date: Date = Date()) async -> Allowance {
        let current = snapshot(dailyLimit: dailyLimit, date: date)
        if current.videoIds.contains(videoId) {
            return Allowance(
                allowed: true,
                wasCounted: false,
                snapshot: Snapshot(
                    date: current.date,
                    count: current.count,
                    limit: current.limit,
                    remaining: max(0, current.limit - current.count),
                    videoIds: current.videoIds
                )
            )
        }

        if current.count >= dailyLimit {
            return Allowance(
                allowed: false,
                wasCounted: false,
                snapshot: current
            )
        }

        var updatedIds = current.videoIds
        updatedIds.append(videoId)
        let newSnapshot = Snapshot(
            date: current.date,
            count: updatedIds.count,
            limit: dailyLimit,
            remaining: max(0, dailyLimit - updatedIds.count),
            videoIds: updatedIds
        )
        persist(snapshot: newSnapshot)
        return Allowance(allowed: true, wasCounted: true, snapshot: newSnapshot)
    }

    func remove(videoId: String, dailyLimit: Int, date: Date = Date()) async {
        let currentSnapshot = snapshot(dailyLimit: dailyLimit, date: date)
        var ids = currentSnapshot.videoIds
        if let index = ids.firstIndex(of: videoId) {
            ids.remove(at: index)
            let updated = Snapshot(
                date: currentSnapshot.date,
                count: ids.count,
                limit: dailyLimit,
                remaining: max(0, dailyLimit - ids.count),
                videoIds: ids
            )
            persist(snapshot: updated)
        }
    }

    func snapshot(dailyLimit: Int, date: Date = Date()) -> Snapshot {
        let startOfDay = calendar.startOfDay(for: date)
        guard let storedDate = defaults.object(forKey: Keys.storageDate) as? Date,
              calendar.isDate(storedDate, inSameDayAs: startOfDay),
              let storedIds = defaults.array(forKey: Keys.storageVideos) as? [String]
        else {
            let snapshot = Snapshot(
                date: startOfDay,
                count: 0,
                limit: dailyLimit,
                remaining: dailyLimit,
                videoIds: []
            )
            persist(snapshot: snapshot)
            return snapshot
        }

        var uniqueOrderedIds: [String] = []
        for id in storedIds {
            if !uniqueOrderedIds.contains(id) {
                uniqueOrderedIds.append(id)
            }
        }
        let clampedIds = uniqueOrderedIds.prefix(dailyLimit)
        return Snapshot(
            date: startOfDay,
            count: clampedIds.count,
            limit: dailyLimit,
            remaining: max(0, dailyLimit - clampedIds.count),
            videoIds: Array(clampedIds)
        )
    }

    private func persist(snapshot: Snapshot) {
        defaults.set(snapshot.date, forKey: Keys.storageDate)
        defaults.set(snapshot.videoIds, forKey: Keys.storageVideos)
    }

    func clearAll() {
        defaults.removeObject(forKey: Keys.storageDate)
        defaults.removeObject(forKey: Keys.storageVideos)
    }
}

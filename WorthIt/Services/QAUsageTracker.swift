import Foundation

actor QAUsageTracker {
    struct Snapshot: Codable {
        let date: Date
        let totalCount: Int
        let limitPerDay: Int
        let countForVideo: Int
        let limitPerVideo: Int

        var remainingToday: Int { max(0, limitPerDay - totalCount) }
        var remainingForVideo: Int { max(0, limitPerVideo - countForVideo) }
    }

    struct Allowance {
        let allowed: Bool
        let snapshot: Snapshot
    }

    static let shared = QAUsageTracker()

    private enum Keys {
        static let storageDate = "qa_usage_tracker_date_v1"
        static let storageCounts = "qa_usage_tracker_counts_v1"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(calendar: Calendar = .current, defaults: UserDefaults? = UserDefaults(suiteName: AppConstants.appGroupID)) {
        self.calendar = calendar
        self.defaults = defaults ?? .standard
    }

    func registerQAQuestion(for videoId: String, dailyLimit: Int, perVideoLimit: Int, date: Date = Date()) async -> Allowance {
        let snapshot = currentSnapshot(dailyLimit: dailyLimit, perVideoLimit: perVideoLimit, date: date, videoId: videoId)

        if snapshot.totalCount >= dailyLimit || snapshot.countForVideo >= perVideoLimit {
            return Allowance(allowed: false, snapshot: snapshot)
        }

        var counts = loadCounts(for: snapshot.date)
        counts[videoId, default: 0] += 1
        persist(counts: counts, date: snapshot.date)

        let updatedSnapshot = Snapshot(
            date: snapshot.date,
            totalCount: snapshot.totalCount + 1,
            limitPerDay: dailyLimit,
            countForVideo: snapshot.countForVideo + 1,
            limitPerVideo: perVideoLimit
        )

        return Allowance(allowed: true, snapshot: updatedSnapshot)
    }

    func snapshot(dailyLimit: Int, perVideoLimit: Int, date: Date = Date(), videoId: String? = nil) -> Snapshot {
        currentSnapshot(dailyLimit: dailyLimit, perVideoLimit: perVideoLimit, date: date, videoId: videoId)
    }

    func clearAll() {
        defaults.removeObject(forKey: Keys.storageDate)
        defaults.removeObject(forKey: Keys.storageCounts)
    }

    // MARK: - Internals

    private func currentSnapshot(dailyLimit: Int, perVideoLimit: Int, date: Date = Date(), videoId: String? = nil) -> Snapshot {
        let startOfDay = calendar.startOfDay(for: date)
        let counts = loadCounts(for: startOfDay)

        let total = counts.values.reduce(0, +)
        let videoCount: Int
        if let vid = videoId {
            videoCount = counts[vid] ?? 0
        } else {
            videoCount = 0
        }

        return Snapshot(
            date: startOfDay,
            totalCount: total,
            limitPerDay: dailyLimit,
            countForVideo: videoCount,
            limitPerVideo: perVideoLimit
        )
    }

    private func loadCounts(for date: Date) -> [String: Int] {
        guard
            let storedDate = defaults.object(forKey: Keys.storageDate) as? Date,
            calendar.isDate(storedDate, inSameDayAs: date),
            let data = defaults.data(forKey: Keys.storageCounts),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            persist(counts: [:], date: date)
            return [:]
        }
        return decoded
    }

    private func persist(counts: [String: Int], date: Date) {
        defaults.set(date, forKey: Keys.storageDate)
        if let data = try? JSONEncoder().encode(counts) {
            defaults.set(data, forKey: Keys.storageCounts)
        }
    }
}

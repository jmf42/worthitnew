import SwiftUI
import UIKit

// MARK: - Recent Videos Center Modal (no database)
struct RecentVideosCenterModal: View {
    let onDismiss: () -> Void
    let onSelect: (CacheManager.RecentAnalysisItem) -> Void
    let initialItems: [CacheManager.RecentAnalysisItem]?
    @State private var items: [CacheManager.RecentAnalysisItem] = []
    @State private var orderedRecent: [CacheManager.RecentAnalysisItem] = []
    @State private var orderedHighScore: [CacheManager.RecentAnalysisItem] = []
    @State private var showContent = false
    let borderGradient: LinearGradient
    
    init(
        onDismiss: @escaping () -> Void,
        onSelect: @escaping (CacheManager.RecentAnalysisItem) -> Void,
        initialItems: [CacheManager.RecentAnalysisItem]? = nil,
        borderGradient: LinearGradient
    ) {
        self.onDismiss = onDismiss
        self.onSelect = onSelect
        self.initialItems = initialItems
        self.borderGradient = borderGradient
    }
    
    // MARK: - Sort & Stats helpers
    private enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Most Recent"
        case highScore = "Highest Score"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .recent: return "clock.arrow.circlepath"
            case .highScore: return "medal.fill"
            }
        }
    }
    @State private var selectedSort: SortOption = .recent

    private var currentItems: [CacheManager.RecentAnalysisItem] {
        switch selectedSort {
        case .recent: return orderedRecent
        case .highScore: return orderedHighScore
        }
    }

    private var averageScore: Int? {
        let scores = items.compactMap { $0.finalScore }
        guard !scores.isEmpty else { return nil }
        let avg = scores.reduce(0, +) / Double(scores.count)
        return Int(avg.rounded())
    }

    private var lastUpdatedRelative: String? {
        guard let latest = items.map({ $0.modifiedAt }).max() else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: latest, relativeTo: Date())
    }

    private func loadItems() {
        if let seededItems = initialItems {
            Task { @MainActor in updateItems(seededItems) }
            return
        }

        Task(priority: .userInitiated) {
            let fetched = await CacheManager.shared.listRecentAnalyses()
            await MainActor.run {
                updateItems(fetched)
            }
        }
    }

    @MainActor
    private func updateItems(_ newItems: [CacheManager.RecentAnalysisItem]) {
        items = newItems
        orderedRecent = newItems.sorted { $0.modifiedAt > $1.modifiedAt }
        orderedHighScore = newItems.sorted { lhs, rhs in
            let lhsScore = displayedScore(for: lhs) ?? 0
            let rhsScore = displayedScore(for: rhs) ?? 0
            if lhsScore == rhsScore {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhsScore > rhsScore
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom navigation bar - completely outside iOS toolbar system
            customNavigationBar
            
            ScrollView(showsIndicators: false) {
                cardContent
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.Color.darkBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            loadItems()
        }
    }
    
    private var customNavigationBar: some View {
        ZStack {
            // Center: Title
            WorthItToolbarTitle()
            
            // Left: Back button
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(Theme.Font.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(borderGradient.opacity(0.7), lineWidth: 0.9)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }
                
                Spacer()
            }
            .padding(.leading, 16)
        }
        .frame(height: 44)
        .padding(.top, 4)
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            headerSection
            sortSection
            listSection
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(borderGradient.opacity(0.7), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                RecentVideosHeaderLabel()
                Spacer()
            }

            statsRow

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.35))
                .frame(height: 2)
                .overlay(
                    LinearGradient(colors: [Theme.Color.accent.opacity(0.75), Theme.Color.purple.opacity(0.55)], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                        .cornerRadius(999)
                )
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your latest insights")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                Text("\(items.count) videos analyzed")
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
                if let updated = lastUpdatedRelative {
                    Text("Updated \(updated)")
                        .font(Theme.Font.caption)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.5))
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Average score")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                Text("\(averageScore.map { "\($0)%" } ?? "–")")
                    .font(Theme.Font.title2.weight(.bold))
                    .foregroundColor(.white)
                if let avg = averageScore {
                    let tier = avg >= 80 ? "Top 25%" : (avg >= 60 ? "Top 75%" : "Below avg")
                    Text(tier)
                        .font(Theme.Font.caption.weight(.semibold))
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.5))
            )
        }
    }

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sort order")
                .font(Theme.Font.captionBold)
                .foregroundColor(Theme.Color.secondaryText.opacity(0.9))

            HStack(spacing: 8) {
                ForEach(SortOption.allCases) { sort in
                    sortButton(for: sort)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.45))
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func sortButton(for sort: SortOption) -> some View {
        Button(action: { withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { selectedSort = sort } }) {
            Label(sort.rawValue, systemImage: sort.iconName)
                .labelStyle(.titleAndIcon)
                .font(Theme.Font.captionBold)
                .foregroundStyle(selectedSort == sort ? .white : Theme.Color.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selectedSort == sort ? AnyShapeStyle(Theme.Gradient.appBluePurple) : AnyShapeStyle(Theme.Color.sectionBackground.opacity(0.35)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.Color.primaryText.opacity(selectedSort == sort ? 0.25 : 0.08), lineWidth: selectedSort == sort ? 1 : 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    private var listSection: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Theme.Color.accent, Theme.Color.secondaryText)
                    Text("No recent insights yet!")
                        .font(Theme.Font.headline.weight(.semibold))
                        .foregroundColor(Theme.Color.primaryText)
                    Text("Share a YouTube video or paste a link to get started with WorthIt.")
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding(.vertical, 48)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(currentItems) { item in
                        listRow(for: item)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 26)
            }
        }
    }

    private func listRow(for item: CacheManager.RecentAnalysisItem) -> some View {
        Button(action: { onSelect(item) }) {
            let title = cleanedTitle(for: item)
            let formattedDate = item.modifiedAt.formatted(date: .abbreviated, time: .omitted)

            let rowScore = displayedScore(for: item)

            HStack(alignment: .center, spacing: 10) {
                thumbnailSection(for: item)
                infoSection(title: title, formattedDate: formattedDate)
                Spacer(minLength: 0)
                if let score = rowScore {
                    scoreBadge(for: score)
                }
                navigationChevron
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(cardRowBackground)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func thumbnailSection(for item: CacheManager.RecentAnalysisItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.8))
            AsyncImage(url: item.thumbnailURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Color.accent))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "film.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.9))
                @unknown default:
                    Color.clear
                }
            }
            Circle()
                .fill(Theme.Gradient.appBluePurple)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: Theme.Color.accent.opacity(0.45), radius: 5, y: 2)
                .offset(x: 36, y: 18)
        }
        .frame(width: 96, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderGradient.opacity(0.5), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
    }

    private func infoSection(title: String, formattedDate: String) -> some View {
        return VStack(alignment: .center, spacing: 0) {
            Text(formattedDate)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var navigationChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
            .padding(.leading, 6)
    }

    private var cardRowBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.Color.sectionBackground.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderGradient.opacity(0.3), lineWidth: 0.9)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func displayedScore(for item: CacheManager.RecentAnalysisItem) -> Double? {
        if let score = item.finalScore {
            return score
        }
        // Fallback when there are no comment insights cached yet – mirror the transcript-only heuristic.
        return 60
    }

    private func scoreBadge(for score: Double) -> some View {
        let clampedScore = max(0, min(score, 100))
        let formattedScore = "\(Int(clampedScore))%"
        let fillPercentage = clampedScore / 100.0

        return ZStack {
            // Background circle
            Circle()
                .fill(Theme.Color.sectionBackground.opacity(0.75))
                .shadow(color: Theme.Color.accent.opacity(0.2), radius: 6, y: 2)
            
            // Empty stroke (background for the filled portion)
            Circle()
                .stroke(Theme.Color.sectionBackground.opacity(0.3), lineWidth: 3)
            
            // Filled portion based on percentage
            Circle()
                .trim(from: 0, to: CGFloat(fillPercentage))
                .stroke(
                    scoreGradient(for: clampedScore),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: -90))
            
            // Percentage text
            Text(formattedScore)
                .font(Theme.Font.subheadline.weight(.bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 52, height: 52)
    }

    private func scoreGradient(for score: Double) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Theme.Color.error, Theme.Color.orange, Theme.Color.warning, Theme.Color.success]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func cleanedTitle(for item: CacheManager.RecentAnalysisItem) -> String {
        let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeId = t.count == 11 && t.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
        return looksLikeId ? "" : t
    }
}

#if DEBUG
struct RecentVideosCenterModal_Previews: PreviewProvider {
    static var previews: some View {
        RecentVideosCenterModal(
            onDismiss: {},
            onSelect: { _ in },
            initialItems: [
                CacheManager.RecentAnalysisItem(
                    videoId: "abc123xyz01",
                    title: "AI Productivity: 7 Habits to Work Smarter",
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/5MgBikgcWnY/hq720.jpg"),
                    finalScore: 82,
                    modifiedAt: Date().addingTimeInterval(-3600)
                ),
                CacheManager.RecentAnalysisItem(
                    videoId: "def456uvw02",
                    title: "The Hidden Costs of Automation",
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hq720.jpg"),
                    finalScore: 68,
                    modifiedAt: Date().addingTimeInterval(-86000)
                ),
                CacheManager.RecentAnalysisItem(
                    videoId: "ghi789rst03",
                    title: "Quantum Computing Explained Simply",
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/oHg5SJYRHA0/hq720.jpg"),
                    finalScore: 90,
                    modifiedAt: Date().addingTimeInterval(-172800)
                )
            ],
            borderGradient: Theme.Gradient.appBluePurple
        )
        .preferredColorScheme(.dark)
    }
}
#endif

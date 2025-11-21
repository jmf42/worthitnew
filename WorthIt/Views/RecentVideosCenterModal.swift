import SwiftUI

// MARK: - Recent Videos Center Modal (no database)
struct RecentVideosCenterModal: View {
    let onDismiss: () -> Void
    let onSelect: (CacheManager.RecentAnalysisItem) -> Void
    @State private var items: [CacheManager.RecentAnalysisItem] = []
    @State private var showContent = false
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    let borderGradient: LinearGradient

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

    private var orderedItems: [CacheManager.RecentAnalysisItem] {
        switch selectedSort {
        case .recent:
            return items.sorted { $0.modifiedAt > $1.modifiedAt }
        case .highScore:
            return items.sorted { lhs, rhs in
                let lhsScore = displayedScore(for: lhs) ?? 0
                let rhsScore = displayedScore(for: rhs) ?? 0
                if lhsScore == rhsScore {
                    return lhs.modifiedAt > rhs.modifiedAt
                }
                return lhsScore > rhsScore
            }
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

    private var backdropOpacity: Double {
        let alpha = 0.35 - Double(min(dragOffset, 160)) / 600.0
        return max(0.05, alpha)
    }

    private func dismiss(after delay: TimeInterval = 0.18, haptic: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        if haptic {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if !haptic {
            dragOffset = 0
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            onDismiss()
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backdrop
                cardBody(safeAreaInsets: proxy.safeAreaInsets)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .overlay(Theme.Color.darkBackground.opacity(backdropOpacity).ignoresSafeArea())
            .onTapGesture { dismiss(haptic: false) }
    }

    private func cardBody(safeAreaInsets: EdgeInsets) -> some View {
        let horizontalInset = max(12, max(safeAreaInsets.leading, safeAreaInsets.trailing))
        let contentTopPadding = safeAreaInsets.top + 32

        return ZStack(alignment: .topLeading) {
            ScrollView(showsIndicators: false) {
                cardContent
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, contentTopPadding)
                    .padding(.bottom, safeAreaInsets.bottom + 24)
            }

            topBar(safeAreaInsets: safeAreaInsets)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(x: dragOffset)
        .opacity(showContent ? 1 : 0)
        .scaleEffect(showContent ? 1 : 0.98)
        .onAppear {
            dragOffset = 0
            isDismissing = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showContent = true }
            Task { @MainActor in
                items = await CacheManager.shared.listRecentAnalyses()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 15)
                .onChanged { value in
                    guard !isDismissing else { return }
                    let translation = value.translation.width
                    if translation > 0 {
                        dragOffset = translation
                    }
                }
                .onEnded { value in
                    guard !isDismissing else { return }
                    if value.translation.width > 90 {
                        let target = UIScreen.main.bounds.width * 0.65
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            dragOffset = target
                        }
                        dismiss(haptic: true)
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private func topBar(safeAreaInsets: EdgeInsets) -> some View {
        let leadingInset = max(16, safeAreaInsets.leading + 6)
        let trailingInset = max(16, safeAreaInsets.trailing + 6)

        return HStack(spacing: 0) {
            Button(action: { dismiss(haptic: false) }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Back")
                        .font(Theme.Font.subheadline.weight(.medium))
                }
                .foregroundColor(Theme.Color.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.Color.sectionBackground.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.Color.primaryText.opacity(0.08), lineWidth: 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderGradient.opacity(0.35), lineWidth: 0.8)
                        .blendMode(.overlay)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            }
            Spacer()
        }
        .padding(.top, safeAreaInsets.top + 4)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.bottom, 6)
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
                .background(Theme.Color.accent.opacity(0.12))
                .padding(.horizontal, 24)
            statsSection
            sortSection
            listSection
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.Color.primaryText.opacity(0.06), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(borderGradient, lineWidth: 0.8)
                .blendMode(.overlay)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 10)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.Gradient.appBluePurple)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                                .shadow(color: Theme.Color.accent.opacity(0.45), radius: 12, y: 6)
                        )

                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Videos")
                        .font(Theme.Font.title3.weight(.bold))
                        .foregroundColor(Theme.Color.primaryText)

                    Text("Jump back into your latest WorthIt insights.")
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.92))
                }

                Spacer()
            }

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Color.sectionBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
                )
                .frame(height: 3)
                .overlay(
                    LinearGradient(colors: [Theme.Color.accent.opacity(0.8), Theme.Color.purple.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 3)
                        .cornerRadius(999)
                )
                .opacity(0.9)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 16)
    }

    private var statsSection: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your latest insights")
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
                Text("\(items.count) videos analyzed")
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
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
                    .fill(Theme.Color.sectionBackground.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.Color.primaryText.opacity(0.08), lineWidth: 0.8)
                    )
            )
            .layoutPriority(1)

            VStack(alignment: .center, spacing: 6) {
                Text("Average score")
                    .font(Theme.Font.subheadline.weight(.semibold))
                    .foregroundColor(Theme.Color.primaryText)
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
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Color.sectionBackground.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.Color.primaryText.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
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
                    .fill(Theme.Color.sectionBackground.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.Color.primaryText.opacity(0.05), lineWidth: 1)
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
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
                        .fill(selectedSort == sort ? AnyShapeStyle(Theme.Gradient.appBluePurple) : AnyShapeStyle(Color.clear))
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
                    Text("Share a YouTube video or paste a link to get started with WorthIt.AI.")
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding(.vertical, 48)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(orderedItems) { item in
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

            HStack(alignment: .center, spacing: 12) {
                thumbnailSection(for: item)
                infoSection(title: title, formattedDate: formattedDate)
                Spacer(minLength: 0)
                if let score = rowScore {
                    scoreBadge(for: score)
                }
                navigationChevron
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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
                .strokeBorder(borderGradient.opacity(0.8), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }

    private func infoSection(title: String, formattedDate: String) -> some View {
        let resolvedTitle = title.isEmpty ? "Untitled insight" : title

        return VStack(alignment: .leading, spacing: 6) {
            Text(formattedDate)
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                .lineLimit(1)
            Text(resolvedTitle)
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .layoutPriority(1)
        }
    }

    private var navigationChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
            .padding(.leading, 6)
    }

    private var cardRowBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.Color.sectionBackground.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.Color.primaryText.opacity(0.05), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderGradient.opacity(0.35), lineWidth: 0.8)
                    .blendMode(.overlay)
            )
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
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

        return ZStack {
            Circle()
                .fill(Theme.Color.sectionBackground.opacity(0.82))
                .shadow(color: Theme.Color.accent.opacity(0.28), radius: 10, y: 4)

            Circle()
                .strokeBorder(scoreGradient(for: clampedScore), lineWidth: 2.4)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                        .blur(radius: 0.4)
                )

            VStack(spacing: 2) {
                Text(formattedScore)
                    .font(Theme.Font.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)

                Text("Score")
                    .font(Theme.Font.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Color.secondaryText.opacity(0.8))
                    .tracking(0.4)
            }
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
            borderGradient: Theme.Gradient.appBluePurple
        )
        .preferredColorScheme(.dark)
    }
}
#endif

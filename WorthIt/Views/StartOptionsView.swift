import SwiftUI
import UIKit
import LinkPresentation

@MainActor
final class StartOptionsViewModel: ObservableObject {
    @Published var inputURLText: String = ""
    @Published var isURLValid: Bool = false
    @Published var validationHint: String? = nil
    @Published var previewData: TinyPreviewData? = nil
    @Published var showHowItWorksDetails: Bool = false

    private var previewTask: Task<Void, Never>?

    deinit {
        previewTask?.cancel()
    }

    func updateInput(_ text: String) {
        inputURLText = text
        updateValidation(for: text)
        schedulePreview(for: text)
    }

    func clearInput() {
        updateInput("")
    }

    func applyPastedContent(_ text: String) {
        updateInput(text)
        validationHint = nil
    }

    func isAnalyzeEnabled(for state: ViewState) -> Bool {
        state != .processing && resolveVideoURL(from: inputURLText) != nil
    }

    func analyze(using mainViewModel: MainViewModel, dismissKeyboard: () -> Void) {
        guard mainViewModel.viewState != .processing else { return }
        guard let url = resolveVideoURL(from: inputURLText) else {
            validationHint = "Please paste a valid YouTube link or 11-character video ID."
            isURLValid = false
            return
        }
        dismissKeyboard()
        Logger.shared.info("Manual analyze triggered from main app UI: \(url.absoluteString)", category: .ui)
        AnalyticsService.shared.logEvent("manual_paste_analyze", parameters: ["source": "main_app", "url": url.absoluteString])
        mainViewModel.processSharedURL(url)
    }

    // MARK: - Private helpers
    private func updateValidation(for input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isURLValid = false
            validationHint = nil
            return
        }
        if resolveVideoURL(from: trimmed) != nil {
            isURLValid = true
            validationHint = nil
        } else {
            isURLValid = false
            validationHint = "We need a YouTube link like https://www.youtube.com/watch?v=abc123 or a video ID."
        }
    }

    private func schedulePreview(for input: String) {
        previewTask?.cancel()
        guard let url = resolveVideoURL(from: input) else {
            previewData = nil
            return
        }
        let metadataURL = canonicalYouTubeURL(from: url) ?? url
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let metadata = await fetchLPMetadata(for: metadataURL)
            if Task.isCancelled { return }

            var title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty, let fallbackTitle = await fetchYouTubeOEmbedTitle(for: metadataURL) {
                title = fallbackTitle
            }
            if Task.isCancelled { return }
            if title.isEmpty {
                title = metadataURL.host ?? "YouTube video"
            }

            var image: UIImage?
            if let provider = metadata?.iconProvider {
                image = try? await provider.loadImage()
            }
            if Task.isCancelled { return }
            if image == nil, let provider = metadata?.imageProvider {
                image = try? await provider.loadImage()
            }
            await MainActor.run {
                previewData = TinyPreviewData(title: title, image: image)
            }
        }
    }

    private func fetchLPMetadata(for url: URL) async -> LPLinkMetadata? {
        await withCheckedContinuation { continuation in
            let provider = LPMetadataProvider()
            provider.timeout = 3
            provider.startFetchingMetadata(for: url) { metadata, _ in
                continuation.resume(returning: metadata)
            }
        }
    }

    private func fetchYouTubeOEmbedTitle(for url: URL) async -> String? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let oembedURL = components?.url else { return nil }

        var request = URLRequest(url: oembedURL)
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            struct OEmbedResponse: Decodable { let title: String }
            let decoded = try JSONDecoder().decode(OEmbedResponse.self, from: data)
            let trimmed = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            Logger.shared.debug("oEmbed title fetch failed: \(error.localizedDescription)", category: .parsing)
            return nil
        }
    }

    private func resolveVideoURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let urlFromText = URLParser.firstSupportedVideoURL(in: trimmed) {
            return urlFromText
        }
        if isValidVideoId(trimmed) {
            return URL(string: "https://www.youtube.com/watch?v=\(trimmed)")
        }
        return nil
    }

    private func canonicalYouTubeURL(from url: URL) -> URL? {
        guard let videoID = try? URLParser.extractVideoID(from: url) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url
    }

    private func isValidVideoId(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 11 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return trimmed.rangeOfCharacter(from: allowed.inverted) == nil
    }
}

struct StartOptionsView: View {
    @EnvironmentObject private var mainViewModel: MainViewModel
    @ObservedObject var viewModel: StartOptionsViewModel

    let borderGradient: LinearGradient
    let isRunningInExtension: Bool
    let pasteFieldFocus: FocusState<Bool>.Binding
    let dismissKeyboard: () -> Void

    @State private var ctaPulse = false

    private let controlHeight: CGFloat = 44
    private let optionControlHeight: CGFloat = 40
    @State private var pasteFieldFrame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            startHeader

            if !isRunningInExtension {
                optionHeader(
                    number: 1,
                    title: "Paste a YouTube link",
                    icon: "link"
                )
                pasteAnalyzeSection
            }

            separator

            optionHeader(
                number: 2,
                title: "Share from YouTube",
                icon: "square.and.arrow.up"
            )
            sharePill

            DisclosureGroup(isExpanded: $viewModel.showHowItWorksDetails) {
                howItWorksSection
                    .padding(.top, 6)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(Theme.Color.accent)
                    Text("See how")
                        .font(Theme.Font.subheadline)
                        .foregroundColor(Theme.Color.secondaryText.opacity(0.92))
                    Spacer()
                }
            }
            .tint(Theme.Color.secondaryText.opacity(0.88))
        }
        .coordinateSpace(name: "StartOptionsArea")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { gesture in
                    guard pasteFieldFocus.wrappedValue else { return }
                    if !pasteFieldFrame.contains(gesture.location) {
                        dismissKeyboard()
                    }
                }
        )
    }

    private var startHeader: some View {
        HStack(spacing: 16) {
            startPowerBadge
            Text("Start here")
                .font(Theme.Font.title3.weight(.bold))
                .foregroundColor(Theme.Color.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startPowerBadge: some View {
        ZStack {
            Circle()
                .fill(Theme.Gradient.appBluePurple)
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Theme.Color.accent.opacity(0.08), radius: 4, y: 2)

            Image(systemName: "power")
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.white)
        }
    }

    private var separator: some View {
        HStack {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            Text("or")
                .font(Theme.Font.caption)
                .foregroundColor(Theme.Color.secondaryText)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .padding(.vertical, 6)
    }

    private var pasteAnalyzeSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.Color.sectionBackground.opacity(0.28))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.03))
                            .blur(radius: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.Color.accent.opacity(pasteFieldFocus.wrappedValue ? 0.3 : 0.0), lineWidth: 1.8)
                            .animation(.easeInOut(duration: 0.2), value: pasteFieldFocus.wrappedValue)
                    )

                HStack(spacing: 12) {
                    TextField(
                        "Paste a YouTube link here",
                        text: Binding(
                            get: { viewModel.inputURLText },
                            set: { viewModel.updateInput($0) }
                        )
                    )
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .font(Theme.Font.subheadline)
                    .foregroundColor(Theme.Color.primaryText)
                    .submitLabel(.go)
                    .focused(pasteFieldFocus)
                    .onSubmit { analyze() }
                    .frame(maxHeight: .infinity)

                    if !viewModel.inputURLText.isEmpty {
                        Button(action: { viewModel.clearInput() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.Color.secondaryText.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: handlePasteFromClipboard) {
                            Text("Paste")
                                .font(Theme.Font.captionBold)
                                .foregroundColor(Theme.Color.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Theme.Color.sectionBackground.opacity(0.45))
                                        .overlay(
                                            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(borderGradient.opacity(0.55), lineWidth: 0.8)
                                        .blendMode(.overlay)
                                )
                        }
                        .accessibilityLabel("Paste from Clipboard")
                    }
                }
                .padding(.horizontal, 12)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                pasteFieldFrame = proxy.frame(in: .named("StartOptionsArea"))
                            }
                            .onChange(of: proxy.size) { _ in
                                pasteFieldFrame = proxy.frame(in: .named("StartOptionsArea"))
                            }
                    }
                )
            }
            .frame(maxWidth: .infinity, minHeight: optionControlHeight, maxHeight: optionControlHeight)

            if let hint = viewModel.validationHint, !viewModel.isURLValid, !viewModel.inputURLText.isEmpty {
                Text(hint)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }

            if let preview = viewModel.previewData, viewModel.isURLValid {
                TinyLinkPreview(preview: preview)
            }

            HStack {
                Spacer(minLength: 0)
                Button(action: analyze) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Analyze Video")
                            .font(Theme.Font.subheadline)
                    }
                    .frame(maxWidth: .infinity, minHeight: controlHeight)
                    .foregroundColor(Theme.Color.primaryText)
                    .padding(.horizontal, 14)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.Color.sectionBackground.opacity(0.85))
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    Theme.Gradient.brand(startPoint: .topLeading, endPoint: .bottomTrailing)
                                        .opacity(viewModel.isAnalyzeEnabled(for: mainViewModel.viewState) ? 0.15 : 0.05)
                                )
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderGradient, lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if viewModel.isAnalyzeEnabled(for: mainViewModel.viewState) {
                                Theme.Gradient.brand(startPoint: .topLeading, endPoint: .bottomTrailing)
                                .opacity(ctaPulse ? 0.4 : 0.2)
                                .mask(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(style: StrokeStyle(lineWidth: ctaPulse ? 3.5 : 2.0))
                                )
                                .scaleEffect(ctaPulse ? 1.02 : 1.0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.6, blendDuration: 0).repeatForever(autoreverses: true), value: ctaPulse)
                                .onAppear { ctaPulse = true }
                            }
                        }
                    )
                    .shadow(color: Theme.Color.accent.opacity(ctaPulse ? 0.25 : 0.1), radius: ctaPulse ? 8 : 4, y: ctaPulse ? 4 : 2)
                    .opacity(viewModel.isAnalyzeEnabled(for: mainViewModel.viewState) ? 1.0 : 0.5)
                }
                .disabled(!viewModel.isAnalyzeEnabled(for: mainViewModel.viewState))
                Spacer(minLength: 0)
            }
        }
    }

    private var sharePill: some View {
        let background = RoundedRectangle(cornerRadius: 12)
        return HStack(spacing: 12) {
            Text("Share from YouTube")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.Color.accent.opacity(0.25), lineWidth: 0.5))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: optionControlHeight, maxHeight: optionControlHeight)
        .background(
            background
                .fill(Theme.Color.sectionBackground.opacity(0.28))
                .background(
                    background
                        .fill(Color.white.opacity(0.03))
                        .blur(radius: 4)
                )
        )
        .overlay(
            background.stroke(Color.white.opacity(0.1), lineWidth: 0.6)
        )
        .overlay(
            background
                .stroke(Theme.Color.accent.opacity(0.0), lineWidth: 1.8)
        )
    }

    private func optionHeader(number: Int, title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            optionIconCircle(systemName: icon)
                .frame(width: 28, height: 28)
            Text("Option \(number) - \(title)")
                .font(Theme.Font.subheadlineBold)
                .foregroundColor(Theme.Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.95)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var howItWorksSection: some View {
        VStack(spacing: 10) {
            StepGuideRow(
                number: "1",
                icon: "play.rectangle.fill",
                title: "Open a YouTube video",
                description: "Choose any video you want to summarize."
            )
            StepGuideRow(
                number: "2",
                icon: "square.and.arrow.up",
                title: "Tap Share → WorthIt",
                description: "If it's missing, tap More (…) once and add WorthIt to Favorites.",
                titleSymbol: "square.and.arrow.up"
            )
            StepGuideRow(
                number: "3",
                icon: "sparkles",
                title: "Get instant insights",
                description: "WorthIt pulls the transcript and returns the recap."
            )
        }
    }
    
    private func optionIconCircle(systemName: String, accent: Color = Theme.Color.accent) -> some View {
        ZStack {
            Circle()
                .fill(Theme.Color.sectionBackground.opacity(0.45))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.15), Theme.Color.accent.opacity(0.35)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                        .blendMode(.overlay)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(accent)
        }
    }

    private func analyze() {
        guard viewModel.isAnalyzeEnabled(for: mainViewModel.viewState) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.analyze(using: mainViewModel, dismissKeyboard: dismissKeyboard)
    }

    private func handlePasteFromClipboard() {
        guard mainViewModel.viewState != .processing else { return }
        if let url = UIPasteboard.general.url {
            viewModel.applyPastedContent(url.absoluteString)
        } else if let string = UIPasteboard.general.string {
            viewModel.applyPastedContent(string)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Supporting Views
private struct StepGuideRow: View {
    let number: String
    let icon: String
    let title: String
    let description: String
    let titleSymbol: String?

    init(number: String, icon: String, title: String, description: String, titleSymbol: String? = nil) {
        self.number = number
        self.icon = icon
        self.title = title
        self.description = description
        self.titleSymbol = titleSymbol
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(number)
                .font(Theme.Font.title3.weight(.bold))
                .foregroundColor(Theme.Color.accent)
                .frame(width: 32)
                .accessibilityHidden(true)

            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.Color.primaryText)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.Font.subheadline.weight(.semibold))
                        .foregroundColor(Theme.Color.primaryText)
                    if let symbol = titleSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.Color.primaryText)
                            .accessibilityHidden(true)
                    }
                }
                Text(description)
                    .font(Theme.Font.caption)
                    .foregroundColor(Theme.Color.secondaryText)
            }
            Spacer()
        }
    }
}

// MARK: - Tiny Link Preview Helpers
struct TinyPreviewData {
    let title: String
    let image: UIImage?
}

struct TinyLinkPreview: View {
    let preview: TinyPreviewData

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let img = preview.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "link.circle.fill")
                        .resizable()
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(Theme.Color.secondaryText)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(preview.title)
                .font(Theme.Font.subheadline)
                .foregroundColor(Theme.Color.primaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.Color.sectionBackground.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.Color.accent.opacity(0.15), lineWidth: 1)
        )
    }
}

// Async helper to load UIImage from an NSItemProvider if available
private extension NSItemProvider {
    func loadImage() async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            if self.canLoadObject(ofClass: UIImage.self) {
                self.loadObject(ofClass: UIImage.self) { obj, err in
                    if let err = err {
                        continuation.resume(throwing: err)
                        return
                    }
                    continuation.resume(returning: obj as? UIImage)
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}

#if DEBUG
private struct StartOptionsPreviewContainer: View {
    @StateObject private var mainViewModel = MainViewModel(
        apiManager: APIManager(),
        cacheManager: CacheManager.shared,
        subscriptionManager: SubscriptionManager(),
        usageTracker: UsageTracker.shared
    )
    @StateObject private var startOptionsViewModel = StartOptionsViewModel()
    @FocusState private var isPasteFocused: Bool

    var body: some View {
        StartOptionsView(
            viewModel: startOptionsViewModel,
            borderGradient: Theme.Gradient.appBluePurple,
            isRunningInExtension: false,
            pasteFieldFocus: $isPasteFocused,
            dismissKeyboard: { isPasteFocused = false }
        )
        .environmentObject(mainViewModel)
        .onAppear {
            mainViewModel.viewState = .showingInitialOptions
            startOptionsViewModel.updateInput("https://www.youtube.com/watch?v=5MgBikgcWnY")
        }
        .padding()
        .background(Theme.Color.darkBackground.ignoresSafeArea())
    }
}

struct StartOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        StartOptionsPreviewContainer()
            .preferredColorScheme(.dark)
    }
}
#endif

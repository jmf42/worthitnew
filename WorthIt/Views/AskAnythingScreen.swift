//
//  AskAnythingScreen.swift
//  WorthIt
//
import SwiftUI
import UIKit // Keep for UIPasteboard if you add copy functionality

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct AskAnythingScreen: View {
    @EnvironmentObject var viewModel: MainViewModel
    @FocusState private var isTextFieldFocused: Bool
    @State private var showSuggestions = true
    @State private var textFieldHeight: CGFloat = 24 // Reduced from 36 to make it more compact
    @State private var inputFieldUsableWidth: CGFloat = UIScreen.main.bounds.width - 100
    // Derived: whether user has asked at least one question for this video
    private var hasAskedFirstQuestion: Bool {
        viewModel.qaMessages.contains(where: { $0.isUser })
    }

    var body: some View {
        VStack(spacing: 0) {
            messageListView

            if viewModel.isQaLoading {
                TypingIndicatorView().padding(.vertical, 10)
            }

            if showSuggestions && !hasAskedFirstQuestion && !viewModel.suggestedQuestions.isEmpty && viewModel.qaInputText.isEmpty && !viewModel.isQaLoading {
                suggestedQuestionsView
            }

            inputFieldView
        }
        .enableSwipeBack()
        .background(
            Theme.Color.darkBackground
                .ignoresSafeArea()
                .overlay(Theme.Gradient.neonGlow.opacity(0.1).ignoresSafeArea()) // Slightly stronger glow
        )
        .onTapGesture { // Dismiss keyboard on tap outside
            isTextFieldFocused = false
        }
        .onAppear {
            Logger.shared.debug("AskAnythingScreen appeared.", category: .ui)
            viewModel.requestAskAnything()
            showSuggestions = !hasAskedFirstQuestion && !viewModel.suggestedQuestions.isEmpty
            viewModel.currentScreenOverride = .showingAskAnything
        }
        .onDisappear {
            viewModel.currentScreenOverride = nil
        }
        .navigationBarBackButtonHidden(false)
    }

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.qaMessages.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { message in
                        ChatMessageView(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 15)
                .padding(.bottom, 5)
            }
            .onChange(of: viewModel.qaMessages.count) { _ in // Corrected for older iOS if needed
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var suggestedQuestionsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.suggestedQuestions, id: \.self) { question in
                    Button {
                        viewModel.selectSuggestedQuestion(question)
                        withAnimation { showSuggestions = false }
                    } label: {
                        Text(question)
                            .font(Theme.Font.caption)
                            .lineLimit(1)
                    }
                    .buttonStyle(Theme.ButtonStyle.Secondary())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .frame(height: 50)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var inputFieldView: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ZStack(alignment: .leading) {
                if viewModel.qaInputText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(Theme.Color.accent.opacity(0.9))
                            .font(.system(size: 13, weight: .semibold))
                        Text("Ask anything about the video…")
                            .foregroundColor(Theme.Color.secondaryText.opacity(0.75))
                            .font(Theme.Font.body)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2) // Further reduced vertical padding
                    .allowsHitTesting(false)
                }

                TextEditor(text: $viewModel.qaInputText)
                    .frame(minHeight: max(18, textFieldHeight - 6), maxHeight: 68)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                    .font(Theme.Font.body)
                    .foregroundColor(Theme.Color.primaryText)
                    .scrollContentBackground(.hidden)
                    .focused($isTextFieldFocused)
                    .onChange(of: viewModel.qaInputText) { newValue in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            showSuggestions = newValue.isEmpty && !hasAskedFirstQuestion && !viewModel.suggestedQuestions.isEmpty && !viewModel.isQaLoading
                        }
                        let width = max(inputFieldUsableWidth - 40, 120)
                        let newSize = viewModel.qaInputText.boundingRect(
                            with: CGSize(width: width, height: .greatestFiniteMagnitude),
                            options: .usesLineFragmentOrigin,
                            attributes: [.font: UIFont.systemFont(ofSize: 17)],
                            context: nil
                        ).height
                        textFieldHeight = max(24, newSize + 12) // Adjusted height calculation
                    }
                    .onChange(of: viewModel.suggestedQuestions) { newQuestions in
                        showSuggestions = viewModel.qaInputText.isEmpty && !hasAskedFirstQuestion && !newQuestions.isEmpty && !viewModel.isQaLoading
                    }
                    .submitLabel(.send)
                    .onSubmit(sendQuestion)
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.Color.sectionBackground.opacity(0.38))
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.white.opacity(0.04))
                            .blur(radius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                    )
                    .shadow(color: (isTextFieldFocused ? Theme.Color.accent.opacity(0.28) : Theme.Color.accent.opacity(0.14)), radius: 6, y: 2)
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { inputFieldUsableWidth = geo.size.width }
                        .onChange(of: geo.size.width) { inputFieldUsableWidth = $0 }
                }
            )

            Button(action: sendQuestion) {
                ZStack {
                    Circle()
                        .fill(Theme.Gradient.appBluePurple)
                        .frame(width: 40, height: 40)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: Theme.Color.accent.opacity(0.3), radius: 4, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.qaInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isQaLoading)
            .opacity(viewModel.qaInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isQaLoading ? 0.5 : 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Theme.Color.sectionBackground.opacity(0.2))
    }

    private func sendQuestion() {
        viewModel.sendQAQuestion()
        withAnimation {
            showSuggestions = false
        }
        isTextFieldFocused = false
        viewModel.qaInputText = ""
        textFieldHeight = 24 // Reset to new base height
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let lastMessageId = viewModel.qaMessages.last?.id else { return }
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                proxy.scrollTo(lastMessageId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastMessageId, anchor: .bottom)
        }
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    @State private var showCopyConfirmation = false

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                messageContent
                    .background(
                        LinearGradient(
                            colors: [
                                Color(white: 0.25),  // Darker grey
                                Color(white: 0.22)   // Even darker grey
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(18, corners: [.topLeft, .topRight, .bottomLeft])
                    .shadow(color: Color.black.opacity(0.15), radius: 3, y: 2)
            } else {
                messageContent
                    .background(Theme.Color.sectionBackground.opacity(0.95))
                    .foregroundColor(Theme.Color.primaryText)
                    .cornerRadius(18, corners: [.topLeft, .topRight, .bottomRight])
                    .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                Spacer()
            }
        }
        .transition(.move(edge: message.isUser ? .trailing : .leading).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.id)
    }

    private var messageContent: some View {
        let segments = parsedSegments()

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .heading(let text):
                    Text(text)
                        .font(Theme.Font.subheadlineBold)
                        .foregroundColor(message.isUser ? .white : Theme.Color.primaryText)
                case .paragraph(let text):
                    Text(text)
                        .font(Theme.Font.body)
                        .foregroundColor(message.isUser ? .white : Theme.Color.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(Theme.Font.body)
                            .foregroundColor(message.isUser ? .white : Theme.Color.primaryText)
                            .padding(.top, 1)
                        Text(text)
                            .font(Theme.Font.body)
                            .foregroundColor(message.isUser ? .white : Theme.Color.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .textSelection(.enabled)
        .contentShape(Rectangle())
        .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .leading)
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                withAnimation { showCopyConfirmation = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showCopyConfirmation = false }
                }
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
        .overlay(
            GeometryReader { geo in
                Text("Copied!")
                    .font(Theme.Font.captionBold)
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Capsule())
                    .position(x: geo.size.width / 2, y: -10)
                    .opacity(showCopyConfirmation ? 1 : 0)
                    .allowsHitTesting(false)
            }
        )
    }

    private enum MessageSegment: Hashable {
        case heading(String)
        case paragraph(String)
        case bullet(String)
    }

    private func parsedSegments() -> [MessageSegment] {
        var normalized = message.content
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Normalize inline bullet lists like "Practical steps: - Do X - Do Y"
        let inlineBulletPatterns: [String] = [
            ": - ",
            ". - ",
            "? - ",
            "! - "
        ]
        for pattern in inlineBulletPatterns {
            let replacement = "\(pattern.prefix(1))\n- "
            normalized = normalized.replacingOccurrences(of: pattern, with: replacement)
        }
        // Fallback: any remaining " - " that likely indicates bullet gets own line
        normalized = normalized.replacingOccurrences(of: " - ", with: "\n- ")

        if message.isUser {
            return normalized
                .components(separatedBy: "\n\n")
                .compactMap {
                    let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : MessageSegment.paragraph(trimmed)
                }
        }

        var segments: [MessageSegment] = []
        var paragraphBuffer: String = ""

        func flushParagraph() {
            let trimmed = paragraphBuffer.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                segments.append(.paragraph(trimmed))
            }
            paragraphBuffer = ""
        }

        let headingLookup: [(String, String)] = [
            ("quick context:", "Quick Context"),
            ("main answer:", "Main Answer"),
            ("conclusion:", "Conclusion")
        ]

        let lines = normalized.components(separatedBy: "\n")
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            let lower = trimmed.lowercased()
            if let heading = headingLookup.first(where: { lower.hasPrefix($0.0) }) {
                flushParagraph()
                segments.append(.heading(heading.1))
                let remainder = trimmed.dropFirst(heading.0.count).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty {
                    paragraphBuffer = remainder
                }
                continue
            }

            if trimmed.hasPrefix("- ") {
                flushParagraph()
                let bulletText = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !bulletText.isEmpty {
                    segments.append(.bullet(String(bulletText)))
                }
                continue
            }

            if paragraphBuffer.isEmpty {
                paragraphBuffer = trimmed
            } else {
                paragraphBuffer += " \(trimmed)"
            }
        }

        flushParagraph()

        if segments.isEmpty {
            return [ .paragraph(normalized) ]
        }

        return segments
    }
}

struct TypingIndicatorView: View {
    @State private var scales: [CGFloat] = [0.5, 0.5, 0.5]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.Color.secondaryText.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .scaleEffect(scales[i])
            }
        }
        .padding(.horizontal)
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    Animation.easeInOut(duration: 0.7)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.25)
                ) {
                    scales[i] = 1.0
                }
            }
        }
    }
}

#if DEBUG
struct AskAnythingScreen_Previews: PreviewProvider {
    static var previews: some View {
        let apiManager = APIManager()
        let cacheManager = CacheManager.shared
        let subscriptionManager = SubscriptionManager()
        let usageTracker = UsageTracker()
        let viewModel = MainViewModel(
            apiManager: apiManager,
            cacheManager: cacheManager,
            subscriptionManager: subscriptionManager,
            usageTracker: usageTracker
        )

        viewModel.qaMessages = [
            ChatMessage(content: "Hi there! I'm ready to answer your questions about the video. What's on your mind?", isUser: false),
            ChatMessage(content: "What were the main arguments presented for the new policy?", isUser: true),
            ChatMessage(content: "The video highlighted three main arguments for the new policy: increased efficiency in resource allocation, improved public safety through proactive measures, and long-term economic benefits outweighing initial investment costs. It also touched upon potential challenges during implementation.", isUser: false),
            ChatMessage(content: "Thanks!", isUser: true)
        ]
        viewModel.suggestedQuestions = ["Summarize the video's conclusion.", "What data supports these claims?", "Are there counter-arguments?"]

        return AskAnythingScreen()
            .environmentObject(viewModel)
            .environmentObject(subscriptionManager)
            .preferredColorScheme(.dark)
    }
}
#endif

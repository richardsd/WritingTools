import SwiftUI
import MarkdownView
import Observation

// MARK: - String Extension for Markdown Processing

extension String {
    /// Normalizes LaTeX delimiters to markdown-friendly versions
    /// Converts \[...\] to $$...$$ and \(...\) to $...$
    func normalizedLatex() -> String {
        var result = self

        // Convert \[...\] to $$...$$
        result = result.replacingOccurrences(of: #"\\\["#, with: "\n$$", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\\\]"#, with: "$$\n", options: .regularExpression)

        // Convert \(...\) to $...$
        result = result.replacingOccurrences(of: #"\\\("#, with: "$", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\\\)"#, with: "$", options: .regularExpression)

        return result
    }

    /// Strips outer code block wrapper if the entire response is wrapped in one.
    /// Some AI models wrap their entire response in ```markdown or ``` fences.
    func strippingOuterCodeBlock() -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern to match content wrapped in a single outer code block
        // Matches: ```<optional language>\n<content>\n```
        let pattern = #"^```(?:\w+)?\s*\n([\s\S]*?)\n```$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(
                in: trimmed,
                options: [],
                range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              let contentRange = Range(match.range(at: 1), in: trimmed) else {
            return self
        }

        return String(trimmed[contentRange])
    }

    /// Applies all markdown normalizations for AI responses.
    func normalizedForMarkdown() -> String {
        self
            .strippingOuterCodeBlock()
            .normalizedLatex()
    }
}

// MARK: - Chat Message Model

enum ChatMessageStatus: Equatable, Sendable {
    case pending
    case complete
    case error
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: String
    var content: String
    let timestamp: Date
    var status: ChatMessageStatus
    var coachResponse: WritingCoachResponse?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = Date(),
        status: ChatMessageStatus = .complete,
        coachResponse: WritingCoachResponse? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.status = status
        self.coachResponse = coachResponse
    }
}

struct ResponseReviewContext {
    let commandName: String
    let originalText: String
    let canPreserveFormatting: Bool
    let applyAction: @MainActor (String) -> Void
}

private enum ReviewDisplayMode: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case diff = "Diff"

    var id: String { rawValue }
}

// MARK: - Response View

struct ResponseView: View {
    @State private var viewModel: ResponseViewModel
    @Bindable private var settings = AppSettings.shared
    @State private var inputText: String = ""
    @State private var reviewDisplayMode: ReviewDisplayMode = .preview
    let onClose: () -> Void

    init(
        viewModel: ResponseViewModel,
        onClose: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onClose = onClose
    }

    init(
        content: String,
        selectedText: String,
        option: WritingOption? = nil,
        provider: any AIProvider,
        conversationImages: [Data] = [],
        reviewContext: ResponseReviewContext? = nil,
        responsePresentation: CommandResponsePresentation = .standard,
        onClose: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: ResponseViewModel(
            content: content,
            selectedText: selectedText,
            option: option,
            provider: provider,
            conversationImages: conversationImages,
            reviewContext: reviewContext,
            responsePresentation: responsePresentation
        ))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if viewModel.showsReviewControls {
                    Button(action: applyReviewedText) {
                        Label("Accept", systemImage: "checkmark")
                            .frame(minWidth: 78)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canApplyReviewedResult)

                    Button(action: { viewModel.retryInitialResponse() }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRequestInFlight)

                    Button(action: onClose) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.showsReviewControls {
                    Button(action: { viewModel.copyContent() }) {
                        Label(
                            viewModel.showCopyConfirmation ? "Copied!" : "Copy All",
                            systemImage: viewModel.showCopyConfirmation ? "checkmark" : "doc.on.doc"
                        )
                        .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .animation(.easeInOut, value: viewModel.showCopyConfirmation)
                } else {
                    Button(action: { viewModel.copyContent() }) {
                        Label(
                            viewModel.showCopyConfirmation ? "Copied!" : "Copy All",
                            systemImage: viewModel.showCopyConfirmation ? "checkmark" : "doc.on.doc"
                        )
                        .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .animation(.easeInOut, value: viewModel.showCopyConfirmation)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { viewModel.fontSize -= 1 }) {
                        Label("Decrease text size", systemImage: "textformat.size.smaller")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.fontSize <= 10)
                    .keyboardShortcut("-", modifiers: .command)

                    Button(action: { viewModel.fontSize += 1 }) {
                        Label("Increase text size", systemImage: "textformat.size.larger")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.fontSize >= 20)
                    .keyboardShortcut("+", modifiers: .command)

                    Button(action: {
                        viewModel.fontSize = 14
                    }) {
                        Label("Reset Font Size", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .padding()
            .background(Color.clear)

            if let reviewContext = viewModel.reviewContext, viewModel.shouldShowReviewPanel {
                ReviewPanel(
                    context: reviewContext,
                    candidateText: viewModel.currentReviewText,
                    isPending: viewModel.isRequestInFlight,
                    displayMode: $reviewDisplayMode,
                    fontSize: viewModel.fontSize
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageView(
                                message: message,
                                fontSize: viewModel.fontSize,
                                responsePresentation: viewModel.responsePresentation,
                                onSuggestedPromptTap: viewModel.canSendFollowUps
                                    ? sendSuggestedPrompt
                                    : nil
                            )
                                .id(message.id)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: message.role == "user" ? .trailing : .leading
                                )
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages, initial: true) { _, newValue in
                    if let lastID = newValue.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                Divider()

                HStack(spacing: 8) {
                    TextField("Ask a follow-up question...", text: $inputText)
                        .textFieldStyle(.plain)
                        .appleStyleTextField(
                            text: inputText,
                            isLoading: viewModel.isRequestInFlight,
                            onSubmit: sendMessage
                        )
                        .disabled(!viewModel.canSendFollowUps)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .opacity(viewModel.canSendFollowUps ? 1 : 0.7)
            }
            .background(Color(.windowBackgroundColor))
        }
        .windowBackground(useGradient: settings.useGradientTheme)
    }

    private func sendMessage() {
        guard viewModel.canSendFollowUps, !inputText.isEmpty else { return }
        let question = inputText
        inputText = ""
        viewModel.processFollowUpQuestion(question)
    }

    private func sendSuggestedPrompt(_ prompt: String) {
        guard viewModel.canSendFollowUps else { return }
        inputText = ""
        viewModel.processFollowUpQuestion(prompt)
    }

    private func applyReviewedText() {
        guard viewModel.applyReviewedResult() else { return }
        onClose()
    }
}

private struct ReviewPanel: View {
    let context: ResponseReviewContext
    let candidateText: String
    let isPending: Bool
    @Binding var displayMode: ReviewDisplayMode
    let fontSize: CGFloat

    private var formattingSummary: String {
        context.canPreserveFormatting
            ? "Will preserve rich-text formatting when applied."
            : "Will paste back as plain text."
    }

    private var safeCandidateText: String {
        let trimmed = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No response yet." : candidateText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(context.commandName) Review")
                        .font(.headline)
                    Text(formattingSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Display", selection: $displayMode) {
                    ForEach(ReviewDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            if isPending {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Regenerating response…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if displayMode == .preview {
                HStack(alignment: .top, spacing: 12) {
                    ReviewTextBox(
                        title: "Original",
                        text: context.originalText,
                        fontSize: fontSize
                    )
                    ReviewTextBox(
                        title: "Suggested",
                        text: safeCandidateText,
                        fontSize: fontSize
                    )
                }
            } else {
                GroupBox("Diff") {
                    ScrollView {
                        Text(buildDiff())
                            .font(.system(size: fontSize))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                }
            }
        }
        .padding(14)
        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func buildDiff() -> AttributedString {
        let inputWords = context.originalText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let outputWords = candidateText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        let diff = outputWords.difference(from: inputWords)

        var removedInputIndices = Set<Int>()
        var insertedOutputIndices = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _):
                removedInputIndices.insert(offset)
            case .insert(let offset, _, _):
                insertedOutputIndices.insert(offset)
            }
        }

        enum Span {
            case unchanged(String)
            case removed(String)
            case inserted(String)
        }

        var spans: [Span] = []
        var inputIndex = 0
        var outputIndex = 0

        while inputIndex < inputWords.count || outputIndex < outputWords.count {
            if inputIndex < inputWords.count, removedInputIndices.contains(inputIndex) {
                spans.append(.removed(inputWords[inputIndex]))
                inputIndex += 1
            } else if outputIndex < outputWords.count, insertedOutputIndices.contains(outputIndex) {
                spans.append(.inserted(outputWords[outputIndex]))
                outputIndex += 1
            } else {
                if inputIndex < inputWords.count {
                    spans.append(.unchanged(inputWords[inputIndex]))
                }
                inputIndex += 1
                outputIndex += 1
            }
        }

        var result = AttributedString()
        for (index, span) in spans.enumerated() {
            if index > 0 {
                result += AttributedString(" ")
            }

            switch span {
            case .unchanged(let word):
                result += AttributedString(word)
            case .removed(let word):
                var piece = AttributedString(word)
                piece.foregroundColor = Color(nsColor: .systemRed)
                piece.strikethroughStyle = Text.LineStyle(pattern: .solid)
                result += piece
            case .inserted(let word):
                var piece = AttributedString(word)
                piece.foregroundColor = Color(nsColor: .systemGreen)
                result += piece
            }
        }

        return result
    }
}

private struct ReviewTextBox: View {
    let title: String
    let text: String
    let fontSize: CGFloat

    var body: some View {
        GroupBox(title) {
            ScrollView {
                Text(text)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .frame(minHeight: 120, maxHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    let fontSize: CGFloat
    let responsePresentation: CommandResponsePresentation
    let onSuggestedPromptTap: ((String) -> Void)?
    @State private var isHovering = false
    @State private var showCopiedFeedback = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == "assistant" {
                bubbleView(role: message.role).transition(.move(edge: .leading))
                Spacer(minLength: 15)
            } else {
                Spacer(minLength: 15)
                bubbleView(role: message.role).transition(.move(edge: .trailing))
            }
        }
        .padding(.top, 4)
        .animation(.spring(), value: message.role)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private func bubbleView(role: String) -> some View {
        VStack(alignment: role == "assistant" ? .leading : .trailing, spacing: 2) {
            messageBody
                .padding()
                .background(backgroundFill)
                .overlay(backgroundStroke)
                .clipShape(ChatBubble(isFromUser: message.role == "user"))
                .textSelection(.enabled)
                .accessibilityLabel(message.role == "user" ? "Your message" : "Assistant's response")
                .accessibilityValue(displayContent)
                .contextMenu {
                    Button("Copy Selection") {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    }
                    Button("Copy Message") {
                        copyEntireMessage()
                    }
                }

            HStack(spacing: 8) {
                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(action: copyEntireMessage) {
                    if showCopiedFeedback {
                        Text("Copied")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(showCopiedFeedback ? "" : "Copy Message")
            }
            .padding(.bottom, 2)
        }
        .frame(maxWidth: 500, alignment: role == "assistant" ? .leading : .trailing)
    }

    @ViewBuilder
    private var messageBody: some View {
        if message.role == "assistant"
            && responsePresentation == .writingCoach
            && message.status == .pending {
            HStack(alignment: .top, spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("Analyzing writing...")
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if message.role == "assistant" && message.status == .pending {
            HStack(alignment: .top, spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(displayContent)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if message.status == .error {
            Text(displayContent)
                .font(.system(size: fontSize))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        } else if message.role == "assistant",
                  responsePresentation == .writingCoach,
                  let coachResponse = message.coachResponse {
            WritingCoachMessageView(
                response: coachResponse,
                fontSize: fontSize,
                onPromptTap: onSuggestedPromptTap
            )
        } else {
            RichMarkdownView(text: displayContent, fontSize: fontSize)
        }
    }

    private var displayContent: String {
        if let coachResponse = message.coachResponse {
            return coachResponse.renderedText
        }

        if message.status == .pending && message.content.isEmpty {
            return "Thinking..."
        }

        return message.content
    }

    private var backgroundFill: some View {
        ChatBubble(isFromUser: message.role == "user")
            .fill(
                message.role == "user"
                    ? Color.blue.opacity(0.15)
                    : (message.status == .error
                        ? Color.red.opacity(0.12)
                        : Color(.controlBackgroundColor))
            )
    }

    private var backgroundStroke: some View {
        ChatBubble(isFromUser: message.role == "user")
            .stroke(
                message.status == .error ? Color.red.opacity(0.35) : Color.clear,
                lineWidth: 1
            )
    }

    private func copyEntireMessage() {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: [])
        pasteboard.writeObjects([displayContent as NSString])

        showCopiedFeedback = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            showCopiedFeedback = false
        }
    }
}

// MARK: - View Model

@MainActor
@Observable
final class ResponseViewModel {
    private static let fontSizeKey = "ResponseView.fontSize"
    private static let defaultFontSize: CGFloat = 14
    typealias InitialResponseSuccessHandler = @MainActor (String, WritingCoachResponse?) -> Void

    private struct InitialRequest {
        let systemPrompt: String?
        let userPrompt: String
        let images: [Data]
    }

    var messages: [ChatMessage]
    var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
        }
    }
    var showCopyConfirmation = false
    private(set) var isInitialResponsePending = false
    private(set) var isFollowUpPending = false

    let selectedText: String
    let option: WritingOption?
    let conversationImages: [Data]
    let reviewContext: ResponseReviewContext?
    let responsePresentation: CommandResponsePresentation

    private let provider: any AIProvider
    private var baseSystemPrompt: String?
    private var conversationHistory: [(role: String, content: String)]
    private var initialAssistantMessageID: UUID?
    private var initialRequest: InitialRequest?
    private var activeRequestID: UUID?
    private var activeRequestTask: Task<Void, Never>?
    private var onInitialRequestFinished: (() -> Void)?
    private var onInitialResponseSuccess: InitialResponseSuccessHandler?
    private var isClosed = false

    var isRequestInFlight: Bool {
        activeRequestID != nil
    }

    var canSendFollowUps: Bool {
        !isRequestInFlight && !isClosed
    }

    var isReviewMode: Bool {
        reviewContext != nil
    }

    var showsReviewControls: Bool {
        guard reviewContext != nil else { return false }
        if responsePresentation == .writingCoach {
            return shouldShowReviewPanel
        }
        return true
    }

    var shouldShowReviewPanel: Bool {
        reviewContext != nil
            && !currentReviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentReviewText: String {
        let latestAssistantMessage = messages.last(where: {
            $0.role == "assistant" && $0.status != .error
        })

        if responsePresentation == .writingCoach {
            return latestAssistantMessage?.coachResponse?.trimmedSuggestedRevision ?? ""
        }

        return latestAssistantMessage?.content ?? ""
    }

    var canApplyReviewedResult: Bool {
        isReviewMode
            && !isRequestInFlight
            && !currentReviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        initialMessages: [ChatMessage] = [],
        selectedText: String,
        option: WritingOption? = nil,
        provider: any AIProvider,
        conversationImages: [Data] = [],
        baseSystemPrompt: String? = nil,
        reviewContext: ResponseReviewContext? = nil,
        responsePresentation: CommandResponsePresentation = .standard
    ) {
        self.messages = initialMessages
        self.selectedText = selectedText
        self.option = option
        self.provider = provider
        self.conversationImages = conversationImages
        self.baseSystemPrompt = baseSystemPrompt
        self.reviewContext = reviewContext
        self.responsePresentation = responsePresentation
        self.conversationHistory = initialMessages
            .filter { $0.status == .complete }
            .map { ($0.role, $0.content) }

        let savedFontSize = UserDefaults.standard.object(forKey: Self.fontSizeKey) as? CGFloat
        self.fontSize = savedFontSize ?? Self.defaultFontSize
    }

    convenience init(
        content: String,
        selectedText: String,
        option: WritingOption? = nil,
        provider: any AIProvider,
        conversationImages: [Data] = [],
        baseSystemPrompt: String? = nil,
        reviewContext: ResponseReviewContext? = nil,
        responsePresentation: CommandResponsePresentation = .standard
    ) {
        let normalizedContent: String
        let coachResponse: WritingCoachResponse?
        if responsePresentation == .writingCoach {
            normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            coachResponse = WritingCoachResponse.parse(from: normalizedContent)
        } else {
            normalizedContent = content.isEmpty ? "" : content.normalizedForMarkdown()
            coachResponse = nil
        }
        let initialMessages = normalizedContent.isEmpty
            ? []
            : [ChatMessage(
                role: "assistant",
                content: normalizedContent,
                coachResponse: coachResponse
            )]

        self.init(
            initialMessages: initialMessages,
            selectedText: selectedText,
            option: option,
            provider: provider,
            conversationImages: conversationImages,
            baseSystemPrompt: baseSystemPrompt,
            reviewContext: reviewContext,
            responsePresentation: responsePresentation
        )
    }

    func startInitialResponse(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        onSuccess: InitialResponseSuccessHandler? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        guard !isClosed else {
            onFinish?()
            return
        }

        cancelInFlightWork()

        baseSystemPrompt = systemPrompt
        initialRequest = InitialRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images
        )
        if let onSuccess {
            onInitialResponseSuccess = onSuccess
        }
        onInitialRequestFinished = onFinish
        isInitialResponsePending = true

        beginAssistantPlaceholder()

        let requestID = UUID()
        activeRequestID = requestID
        activeRequestTask = Task { [weak self] in
            await self?.consumeInitialResponse(
                requestID: requestID,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: images
            )
        }
    }

    func retryInitialResponse() {
        guard let initialRequest, !isClosed else { return }

        cancelInFlightWork()
        messages.removeAll()
        conversationHistory.removeAll()
        initialAssistantMessageID = nil

        startInitialResponse(
            systemPrompt: initialRequest.systemPrompt,
            userPrompt: initialRequest.userPrompt,
            images: initialRequest.images
        )
    }

    @discardableResult
    func applyReviewedResult() -> Bool {
        guard let reviewContext, canApplyReviewedResult else { return false }

        reviewContext.applyAction(currentReviewText)
        return true
    }

    func beginAssistantPlaceholder() {
        initialAssistantMessageID = appendAssistantPlaceholder()
    }

    func completeAssistantMessage(_ content: String) {
        guard let messageID = initialAssistantMessageID else {
            let normalizedContent = normalizeAssistantContent(content)
            messages.append(
                ChatMessage(
                    role: "assistant",
                    content: normalizedContent,
                    coachResponse: parseCoachResponse(from: normalizedContent)
                )
            )
            return
        }

        completeAssistantMessage(content, id: messageID)
        initialAssistantMessageID = nil
    }

    func failInitialRequest(_ message: String) {
        guard let messageID = initialAssistantMessageID else {
            messages.append(ChatMessage(role: "assistant", content: message, status: .error))
            return
        }

        completeAssistantMessage(message, id: messageID, status: .error)
        initialAssistantMessageID = nil
    }

    func appendAssistantDelta(_ delta: String) {
        guard let messageID = initialAssistantMessageID else { return }
        appendAssistantDelta(delta, id: messageID)
    }

    func processFollowUpQuestion(_ question: String) {
        guard canSendFollowUps, !question.isEmpty else { return }

        cancelInFlightWork()

        messages.append(ChatMessage(role: "user", content: question))
        isFollowUpPending = true

        let placeholderID = appendAssistantPlaceholder()
        let requestID = UUID()
        activeRequestID = requestID
        activeRequestTask = Task { [weak self] in
            await self?.consumeFollowUpResponse(
                requestID: requestID,
                question: question,
                placeholderID: placeholderID
            )
        }
    }

    func copyContent() {
        let conversationText = messages.compactMap { message -> String? in
            if message.status == .pending && message.content.isEmpty {
                return nil
            }

            return "\(message.role.capitalized): \(displayContent(for: message))"
        }
        .joined(separator: "\n\n")

        guard !conversationText.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: [])
        pasteboard.writeObjects([conversationText as NSString])

        showCopyConfirmation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.showCopyConfirmation = false
        }
    }

    func markClosed() {
        guard !isClosed else { return }
        isClosed = true
        cancelInFlightWork()
    }

    private func consumeInitialResponse(
        requestID: UUID,
        systemPrompt: String?,
        userPrompt: String,
        images: [Data]
    ) async {
        do {
            var response = ""

            for try await delta in provider.processTextStream(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: images
            ) {
                guard shouldApplyUpdates(for: requestID) else { return }
                response += delta
                appendAssistantDelta(delta)
            }

            guard shouldApplyUpdates(for: requestID) else { return }

            completeAssistantMessage(response)
            let normalizedResponse = normalizeAssistantContent(response)
            let coachResponse = parseCoachResponse(from: normalizedResponse)
            onInitialResponseSuccess?(normalizedResponse, coachResponse)
            if !normalizedResponse.isEmpty {
                conversationHistory.append((role: "assistant", content: normalizedResponse))
            }
            finishActiveRequest(initialRequest: true)
        } catch is CancellationError {
            guard activeRequestID == requestID || isClosed else { return }
            finishActiveRequest(initialRequest: true)
        } catch {
            guard shouldApplyUpdates(for: requestID) else { return }
            failInitialRequest(Self.errorMessage(for: error))
            finishActiveRequest(initialRequest: true)
        }
    }

    private func consumeFollowUpResponse(
        requestID: UUID,
        question: String,
        placeholderID: UUID
    ) async {
        do {
            var response = ""

            for try await delta in provider.processTextStream(
                systemPrompt: buildFollowUpSystemPrompt(),
                userPrompt: buildContextualPrompt(for: question),
                images: conversationImages
            ) {
                guard shouldApplyUpdates(for: requestID) else { return }
                response += delta
                appendAssistantDelta(delta, id: placeholderID)
            }

            guard shouldApplyUpdates(for: requestID) else { return }

            completeAssistantMessage(response, id: placeholderID)
            conversationHistory.append((role: "user", content: question))

            let normalizedResponse = normalizeAssistantContent(response)
            if !normalizedResponse.isEmpty {
                conversationHistory.append((role: "assistant", content: normalizedResponse))
            }
            finishActiveRequest(initialRequest: false)
        } catch is CancellationError {
            guard activeRequestID == requestID || isClosed else { return }
            finishActiveRequest(initialRequest: false)
        } catch {
            guard shouldApplyUpdates(for: requestID) else { return }
            completeAssistantMessage(
                Self.errorMessage(for: error),
                id: placeholderID,
                status: .error
            )
            finishActiveRequest(initialRequest: false)
        }
    }

    private func buildFollowUpSystemPrompt() -> String {
        if responsePresentation == .writingCoach,
           let baseSystemPrompt,
           !baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return """
            \(baseSystemPrompt)

            Continue the writing-coach session using the same JSON schema and response rules. Incorporate the previous coaching context and the user's follow-up request. Return valid JSON only.
            """
        }

        if let baseSystemPrompt,
           !baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return """
            You are continuing a conversation about a prior AI response.

            Original instruction:
            \(baseSystemPrompt)

            The user may ask follow-up questions or request revisions. Respond helpfully while maintaining the existing context. Use Markdown formatting where appropriate.
            """
        }

        if let option {
            return """
            You are a helpful AI assistant continuing a conversation about text modification.

            Original task: \(option.systemPrompt)

            The user may ask follow-up questions or request revisions. Respond helpfully while maintaining the existing context. Use Markdown formatting where appropriate.
            """
        }

        return """
        You are a helpful AI assistant. Answer the user's questions thoughtfully and comprehensively while maintaining context from the previous conversation. Use Markdown formatting where appropriate.
        """
    }

    private func buildContextualPrompt(for question: String) -> String {
        let recentHistory = conversationHistory.suffix(10)
        let historyText = recentHistory
            .map { entry in
                "\(entry.role == "user" ? "User" : "Assistant"): \(entry.content)"
            }
            .joined(separator: "\n\n")

        let originalContext: String
        if selectedText.isEmpty {
            originalContext = ""
        } else {
            originalContext = """
            Original selected text:
            \(selectedText)

            """
        }

        return """
        \(originalContext)Previous conversation:
        \(historyText.isEmpty ? "No previous conversation." : historyText)

        User's follow-up question: \(question)

        Respond to the user's question while maintaining context from the previous conversation.
        """
    }

    private func appendAssistantPlaceholder() -> UUID {
        let placeholder = ChatMessage(
            role: "assistant",
            content: "",
            status: .pending
        )
        messages.append(placeholder)
        return placeholder.id
    }

    private func completeAssistantMessage(
        _ content: String,
        id: UUID,
        status: ChatMessageStatus = .complete
    ) {
        updateMessage(id: id) { message in
            let normalizedContent = status == .complete
                ? normalizeAssistantContent(content)
                : content
            message.content = normalizedContent
            message.status = status
            message.coachResponse = status == .complete
                ? parseCoachResponse(from: normalizedContent)
                : nil
        }
    }

    private func appendAssistantDelta(_ delta: String, id: UUID) {
        updateMessage(id: id) { message in
            message.content += delta
            message.status = .pending
        }
    }

    private func updateMessage(id: UUID, update: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }

        var message = messages[index]
        update(&message)
        messages[index] = message
    }

    private func cancelInFlightWork() {
        activeRequestID = nil
        activeRequestTask?.cancel()
        activeRequestTask = nil
        provider.cancel()

        if isInitialResponsePending {
            let callback = onInitialRequestFinished
            onInitialRequestFinished = nil
            isInitialResponsePending = false
            callback?()
        }

        isFollowUpPending = false
        initialAssistantMessageID = nil
    }

    private func finishActiveRequest(initialRequest: Bool) {
        activeRequestID = nil
        activeRequestTask = nil
        isFollowUpPending = false

        if initialRequest {
            isInitialResponsePending = false
            let callback = onInitialRequestFinished
            onInitialRequestFinished = nil
            callback?()
        }
    }

    private func shouldApplyUpdates(for requestID: UUID) -> Bool {
        activeRequestID == requestID && !isClosed
    }

    private func displayContent(for message: ChatMessage) -> String {
        if let coachResponse = message.coachResponse {
            return coachResponse.renderedText
        }

        if message.status == .pending {
            if responsePresentation == .writingCoach && message.role == "assistant" {
                return "Analyzing writing..."
            }

            if message.content.isEmpty {
                return "Thinking..."
            }
        }

        return message.content
    }

    private func normalizeAssistantContent(_ content: String) -> String {
        guard !content.isEmpty else { return content }
        if responsePresentation == .writingCoach {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content.normalizedForMarkdown()
    }

    private func parseCoachResponse(from content: String) -> WritingCoachResponse? {
        guard responsePresentation == .writingCoach else { return nil }
        return WritingCoachResponse.parse(from: content)
    }

    private static func errorMessage(for error: Error) -> String {
        let message = (error as NSError).localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if message.isEmpty {
            return "Failed to get a response."
        }

        return "Failed to get a response.\n\n\(message)"
    }
}

// MARK: - Rich Markdown View

struct RichMarkdownView: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        MarkdownView(text)
            .markdownMathRenderingEnabled()
            .font(.system(size: fontSize), for: .body)
            .font(.system(size: fontSize * 1.4, weight: .bold), for: .h1)
            .font(.system(size: fontSize * 1.25, weight: .bold), for: .h2)
            .font(.system(size: fontSize * 1.15, weight: .semibold), for: .h3)
            .font(.system(size: fontSize * 1.1, weight: .semibold), for: .h4)
            .font(.system(size: fontSize * 1.05, weight: .medium), for: .h5)
            .font(.system(size: fontSize, weight: .medium), for: .h6)
            .font(.system(size: fontSize, design: .monospaced), for: .codeBlock)
            .font(.system(size: fontSize), for: .blockQuote)
            .font(.system(size: fontSize, weight: .semibold), for: .tableHeader)
            .font(.system(size: fontSize), for: .tableBody)
            .font(.system(size: fontSize), for: .inlineMath)
            .font(.system(size: fontSize + 2), for: .displayMath)
            .tint(.primary, for: .inlineCodeBlock)
    }
}

import XCTest
@testable import WritingTools

@MainActor
final class ResponseStreamingTests: XCTestCase {
    func testActivityTrackerKeepsProviderActiveUntilLastRequestFinishes() {
        let tracker = AITextStreamActivityTracker()
        let first = UUID()
        let second = UUID()
        tracker.begin(first)
        tracker.begin(second)

        XCTAssertTrue(tracker.finish(first))
        XCTAssertFalse(tracker.finish(second))
    }

    func testDefaultProviderStreamKeepsProcessingTrueUntilLastRequestFinishes() async throws {
        let provider = DefaultStreamingProvider()
        let first = provider.processTextStream(
            systemPrompt: nil,
            userPrompt: "first",
            images: []
        )
        let second = provider.processTextStream(
            systemPrompt: nil,
            userPrompt: "second",
            images: []
        )
        let firstConsumer = consume(first)
        let secondConsumer = consume(second)

        await waitUntil { provider.pendingCount == 2 }
        provider.finishRequest(named: "first", with: "first-result")
        let firstResult = try await firstConsumer.value
        XCTAssertEqual(firstResult, "first-result")
        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertTrue(provider.isProcessing)

        provider.finishRequest(named: "second", with: "second-result")
        let secondResult = try await secondConsumer.value
        XCTAssertEqual(secondResult, "second-result")
        await waitUntil { !provider.isProcessing }
    }

    func testBurstIsByteExactAndProducesBoundedUIUpdates() async {
        let provider = FakeStreamingProvider()
        let viewModel = makeViewModel(provider: provider)
        viewModel.startInitialResponse(systemPrompt: nil, userPrompt: "burst", images: [])

        let source = provider.source(at: 0)
        let deltas = (0..<1_000).map { "\($0)," }
        deltas.forEach(source.yield)
        source.finish()

        await waitUntil { !viewModel.isRequestInFlight }

        XCTAssertEqual(viewModel.messages.last?.content, deltas.joined())
        XCTAssertEqual(viewModel.messages.last?.status, .complete)
        XCTAssertLessThanOrEqual(viewModel.streamUpdateRevision, 4)
    }

    func testNormalCompletionFlushesBufferedText() async throws {
        let source = ControlledTextStream()
        let configuration = ResponseStreamPumpConfiguration(
            batchInterval: .seconds(60),
            initialTimeout: .seconds(60),
            idleTimeout: .seconds(60),
            sleep: { duration in try await Task.sleep(for: duration) }
        )
        let values = ResponseStreamPump.batchedValues(
            from: source.request,
            configuration: configuration
        )

        let consumer = Task { () throws -> [String] in
            var batches: [String] = []
            for try await batch in values {
                batches.append(batch)
            }
            return batches
        }

        source.yield("first")
        source.yield("-buffered")
        source.finish()

        let batches = try await consumer.value
        XCTAssertEqual(batches.joined(), "first-buffered")
        XCTAssertEqual(batches, ["first", "-buffered"])
    }

    func testStopCancelsOncePreservesPartialAndIgnoresLateDeltas() async {
        let provider = FakeStreamingProvider()
        let viewModel = makeViewModel(provider: provider)
        viewModel.startInitialResponse(systemPrompt: nil, userPrompt: "stop", images: [])

        let source = provider.source(at: 0)
        source.yield("partial")
        await waitUntil { viewModel.messages.last?.content == "partial" }

        viewModel.stopActiveRequest()
        source.yield("-late")
        source.finish()
        await Task.yield()

        XCTAssertEqual(source.cancellationCount, 1)
        XCTAssertEqual(viewModel.messages.last?.content, "partial")
        XCTAssertEqual(viewModel.messages.last?.status, .interrupted(.cancelled))
        XCTAssertFalse(viewModel.isRequestInFlight)
        XCTAssertTrue(viewModel.canSendFollowUps)
    }

    func testInitialIdleTimeoutCancelsAndRecovers() async {
        let provider = FakeStreamingProvider()
        let viewModel = makeViewModel(
            provider: provider,
            configuration: timeoutConfiguration(trigger: .milliseconds(1), initial: true)
        )
        viewModel.startInitialResponse(systemPrompt: nil, userPrompt: "timeout", images: [])

        let source = provider.source(at: 0)
        await waitUntil { !viewModel.isRequestInFlight }

        XCTAssertEqual(source.cancellationCount, 1)
        XCTAssertEqual(viewModel.messages.last?.status, .interrupted(.timedOut))
        XCTAssertTrue(viewModel.messages.last?.content.isEmpty == true)
        XCTAssertTrue(viewModel.canSendFollowUps)
    }

    func testMidstreamIdleTimeoutPreservesPartialAndRecovers() async {
        let provider = FakeStreamingProvider()
        let viewModel = makeViewModel(
            provider: provider,
            configuration: timeoutConfiguration(trigger: .milliseconds(1), initial: false)
        )
        viewModel.startInitialResponse(systemPrompt: nil, userPrompt: "timeout", images: [])

        let source = provider.source(at: 0)
        source.yield("partial")
        await waitUntil { !viewModel.isRequestInFlight }

        XCTAssertEqual(source.cancellationCount, 1)
        XCTAssertEqual(viewModel.messages.last?.content, "partial")
        XCTAssertEqual(viewModel.messages.last?.status, .interrupted(.timedOut))
        XCTAssertTrue(viewModel.canSendFollowUps)
    }

    func testConcurrentViewModelsDoNotCancelOrClearEachOther() async {
        let provider = FakeStreamingProvider()
        let first = makeViewModel(provider: provider)
        let second = makeViewModel(provider: provider)

        first.startInitialResponse(systemPrompt: nil, userPrompt: "first", images: [])
        second.startInitialResponse(systemPrompt: nil, userPrompt: "second", images: [])
        let firstSource = provider.source(at: 0)
        let secondSource = provider.source(at: 1)

        first.stopActiveRequest()

        XCTAssertEqual(firstSource.cancellationCount, 1)
        XCTAssertEqual(secondSource.cancellationCount, 0)
        XCTAssertFalse(first.isRequestInFlight)
        XCTAssertTrue(second.isRequestInFlight)

        secondSource.yield("second-result")
        secondSource.finish()
        await waitUntil { !second.isRequestInFlight }

        XCTAssertEqual(second.messages.last?.content, "second-result")
        XCTAssertEqual(second.messages.last?.status, .complete)
    }

    func testRetryCancelsOnlyPriorGenerationAndRejectsItsLateEvents() async {
        let provider = FakeStreamingProvider()
        let viewModel = makeViewModel(provider: provider)
        viewModel.startInitialResponse(systemPrompt: nil, userPrompt: "retry", images: [])

        let firstSource = provider.source(at: 0)
        firstSource.yield("old")
        await waitUntil { viewModel.messages.last?.content == "old" }

        viewModel.retryInitialResponse()
        let secondSource = provider.source(at: 1)
        firstSource.yield("-late")
        firstSource.finish()
        secondSource.yield("new")
        secondSource.finish()
        await waitUntil { !viewModel.isRequestInFlight }

        XCTAssertEqual(firstSource.cancellationCount, 1)
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.last?.content, "new")
        XCTAssertEqual(viewModel.messages.last?.status, .complete)
    }

    func testCloseAndTutorModeChangeCancelOnlyOwningRequests() async {
        let originalPreset = AppSettings.shared.writingCoachPreset
        defer { AppSettings.shared.writingCoachPreset = originalPreset }

        let provider = FakeStreamingProvider()
        let closing = makeViewModel(provider: provider)
        let concurrent = makeViewModel(provider: provider)
        closing.startInitialResponse(systemPrompt: nil, userPrompt: "close", images: [])
        concurrent.startInitialResponse(systemPrompt: nil, userPrompt: "keep", images: [])
        let closingSource = provider.source(at: 0)
        let concurrentSource = provider.source(at: 1)

        closing.markClosed()
        XCTAssertEqual(closingSource.cancellationCount, 1)
        XCTAssertEqual(concurrentSource.cancellationCount, 0)
        XCTAssertTrue(concurrent.isRequestInFlight)

        let coach = ResponseViewModel(
            selectedText: "draft",
            provider: provider,
            responsePresentation: .writingCoach,
            writingCoachPreset: .general
        )
        coach.startInitialResponse(
            systemPrompt: WritingCoachPromptBuilder.systemPrompt(for: .general),
            userPrompt: "draft",
            images: [],
            writingCoachPreset: .general
        )
        let originalCoachSource = provider.source(at: 2)
        coach.changeWritingCoachPreset(to: .esl)

        XCTAssertEqual(originalCoachSource.cancellationCount, 1)
        XCTAssertEqual(concurrentSource.cancellationCount, 0)
        XCTAssertTrue(concurrent.isRequestInFlight)
        XCTAssertEqual(provider.sourceCount, 4)

        concurrent.stopActiveRequest()
        coach.stopActiveRequest()
    }

    func testInterruptedReviewCannotApplyOrEnterCompletedHistory() async {
        let provider = FakeStreamingProvider()
        var appliedText: String?
        let context = ResponseReviewContext(
            commandName: "Review",
            originalText: "original",
            canPreserveFormatting: false,
            applyAction: { appliedText = $0 }
        )
        let viewModel = ResponseViewModel(
            selectedText: "original",
            provider: provider,
            reviewContext: context
        )
        viewModel.startInitialResponse(systemPrompt: nil, userPrompt: "review", images: [])

        let source = provider.source(at: 0)
        source.yield("partial-response")
        await waitUntil { viewModel.messages.last?.content == "partial-response" }
        viewModel.stopActiveRequest()

        XCTAssertFalse(viewModel.canApplyReviewedResult)
        XCTAssertFalse(viewModel.applyReviewedResult())
        XCTAssertNil(appliedText)

        viewModel.processFollowUpQuestion("continue")
        let followUp = provider.source(at: 1)
        XCTAssertFalse(followUp.userPrompt.contains("partial-response"))
        viewModel.stopActiveRequest()
    }

    private func makeViewModel(
        provider: FakeStreamingProvider,
        configuration: ResponseStreamPumpConfiguration = .production
    ) -> ResponseViewModel {
        ResponseViewModel(
            selectedText: "original",
            provider: provider,
            streamPumpConfiguration: configuration
        )
    }

    private func timeoutConfiguration(
        trigger: Duration,
        initial: Bool
    ) -> ResponseStreamPumpConfiguration {
        ResponseStreamPumpConfiguration(
            batchInterval: .seconds(60),
            initialTimeout: initial ? trigger : .seconds(60),
            idleTimeout: initial ? .seconds(60) : trigger,
            sleep: { duration in
                if duration == trigger {
                    await Task.yield()
                    return
                }
                try await Task.sleep(for: duration)
            }
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !condition(), clock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertTrue(condition(), "Timed out waiting for asynchronous state")
    }

    private func consume(_ request: AITextStreamRequest) -> Task<String, Error> {
        Task {
            var response = ""
            for try await value in request.values {
                response += value
            }
            return response
        }
    }
}

private final class DefaultStreamingProvider: AIProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [String: CheckedContinuation<String, Never>] = [:]
    private var processingStorage = false

    var isProcessing: Bool {
        get { lock.withLock { processingStorage } }
        set { lock.withLock { processingStorage = newValue } }
    }

    var pendingCount: Int {
        lock.withLock { continuations.count }
    }

    func processText(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        streaming: Bool
    ) async throws -> String {
        await withCheckedContinuation { continuation in
            lock.withLock {
                continuations[userPrompt] = continuation
            }
        }
    }

    func finishRequest(named name: String, with response: String) {
        let continuation = lock.withLock { continuations[name]! }
        continuation.resume(returning: response)
    }

    func cancel() {}
}

private final class FakeStreamingProvider: AIProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [ControlledTextStream] = []

    var isProcessing = false

    var sourceCount: Int {
        lock.withLock { sources.count }
    }

    func source(at index: Int) -> ControlledTextStream {
        lock.withLock { sources[index] }
    }

    func processText(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        streaming: Bool
    ) async throws -> String {
        ""
    }

    func processTextStream(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data]
    ) -> AITextStreamRequest {
        let source = ControlledTextStream(userPrompt: userPrompt)
        lock.withLock {
            sources.append(source)
        }
        return source.request
    }

    func cancel() {}
}

private final class ControlledTextStream: @unchecked Sendable {
    let userPrompt: String
    let request: AITextStreamRequest

    private let lock = NSLock()
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private var cancellationCountStorage = 0

    var cancellationCount: Int {
        lock.withLock { cancellationCountStorage }
    }

    init(userPrompt: String = "") {
        self.userPrompt = userPrompt

        var capturedContinuation: AsyncThrowingStream<String, Error>.Continuation!
        let values = AsyncThrowingStream<String, Error> { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation

        let cancellation = AITextStreamCancellation()
        request = AITextStreamRequest(
            id: UUID(),
            values: values,
            cancellation: cancellation
        )
        cancellation.install { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                self.cancellationCountStorage += 1
            }
        }
    }

    func yield(_ value: String) {
        continuation.yield(value)
    }

    func finish() {
        continuation.finish()
    }
}

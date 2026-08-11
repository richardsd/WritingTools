import Foundation

enum ResponseStreamInterruptionReason: Equatable, Sendable {
    case cancelled
    case timedOut

    var message: String {
        switch self {
        case .cancelled:
            return "Generation stopped."
        case .timedOut:
            return "Generation timed out. Please try again."
        }
    }
}

enum ResponseStreamPumpError: Error, Equatable {
    case initialTimeout
    case idleTimeout
}

struct ResponseStreamPumpConfiguration: Sendable {
    let batchInterval: Duration
    let initialTimeout: Duration
    let idleTimeout: Duration
    let sleep: @Sendable (Duration) async throws -> Void

    static let production = ResponseStreamPumpConfiguration(
        batchInterval: .milliseconds(50),
        initialTimeout: .seconds(120),
        idleTimeout: .seconds(60),
        sleep: { duration in
            try await Task.sleep(for: duration)
        }
    )
}

enum ResponseStreamPump {
    static func batchedValues(
        from request: AITextStreamRequest,
        configuration: ResponseStreamPumpConfiguration = .production
    ) -> AsyncThrowingStream<String, Error> {
        let cancellation = AITextStreamCancellation()

        return AsyncThrowingStream { continuation in
            let state = ResponseStreamPumpState(
                continuation: continuation,
                configuration: configuration
            )

            let sourceTask = Task {
                await state.startInitialTimeout()

                do {
                    for try await delta in request.values {
                        try Task.checkCancellation()
                        await state.receive(delta)
                    }
                    await state.finish()
                } catch is CancellationError {
                    await state.cancel()
                } catch {
                    await state.fail(error)
                }
            }

            cancellation.install {
                sourceTask.cancel()
                request.cancel()
                Task {
                    await state.cancel()
                }
            }

            continuation.onTermination = { _ in
                cancellation.cancel()
            }
        }
    }
}

private actor ResponseStreamPumpState {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let configuration: ResponseStreamPumpConfiguration

    private var buffer = ""
    private var hasReceivedContent = false
    private var isTerminated = false
    private var flushTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        configuration: ResponseStreamPumpConfiguration
    ) {
        self.continuation = continuation
        self.configuration = configuration
    }

    func startInitialTimeout() {
        scheduleTimeout(
            after: configuration.initialTimeout,
            error: .initialTimeout
        )
    }

    func receive(_ delta: String) {
        guard !isTerminated, !delta.isEmpty else { return }

        if !hasReceivedContent {
            hasReceivedContent = true
            continuation.yield(delta)
            scheduleFlush()
        } else {
            buffer += delta
        }

        scheduleTimeout(
            after: configuration.idleTimeout,
            error: .idleTimeout
        )
    }

    func finish() {
        guard !isTerminated else { return }
        flushBuffer()
        terminate()
        continuation.finish()
    }

    func fail(_ error: Error) {
        guard !isTerminated else { return }
        flushBuffer()
        terminate()
        continuation.finish(throwing: error)
    }

    func cancel() {
        guard !isTerminated else { return }
        terminate()
        continuation.finish()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let interval = configuration.batchInterval
        let sleep = configuration.sleep

        flushTask = Task { [weak self] in
            do {
                try await sleep(interval)
            } catch {
                return
            }
            await self?.flushAndReschedule()
        }
    }

    private func flushAndReschedule() {
        guard !isTerminated else { return }
        flushBuffer()
        scheduleFlush()
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = ""
        continuation.yield(batch)
    }

    private func scheduleTimeout(
        after duration: Duration,
        error: ResponseStreamPumpError
    ) {
        timeoutTask?.cancel()
        let sleep = configuration.sleep

        timeoutTask = Task { [weak self] in
            do {
                try await sleep(duration)
            } catch {
                return
            }
            await self?.timeout(with: error)
        }
    }

    private func timeout(with error: ResponseStreamPumpError) {
        guard !isTerminated else { return }
        flushBuffer()
        terminate()
        continuation.finish(throwing: error)
    }

    private func terminate() {
        isTerminated = true
        flushTask?.cancel()
        flushTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

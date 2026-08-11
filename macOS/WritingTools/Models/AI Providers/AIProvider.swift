import Foundation

final class AITextStreamCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?
    private var isCancelled = false

    func install(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            action()
            return
        }

        self.action = action
        lock.unlock()
    }

    func cancel() {
        let actionToRun: (@Sendable () -> Void)?

        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        actionToRun = action
        action = nil
        lock.unlock()

        actionToRun?()
    }
}

struct AITextStreamRequest: @unchecked Sendable {
    let id: UUID
    let values: AsyncThrowingStream<String, Error>
    private let cancellation: AITextStreamCancellation

    init(
        id: UUID,
        values: AsyncThrowingStream<String, Error>,
        cancellation: AITextStreamCancellation
    ) {
        self.id = id
        self.values = values
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation.cancel()
    }
}

final class AITextStreamActivityTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var activeRequestIDs: Set<UUID> = []

    func begin(_ requestID: UUID) {
        lock.lock()
        activeRequestIDs.insert(requestID)
        lock.unlock()
    }

    @discardableResult
    func finish(_ requestID: UUID) -> Bool {
        lock.lock()
        activeRequestIDs.remove(requestID)
        let hasActiveRequests = !activeRequestIDs.isEmpty
        lock.unlock()
        return hasActiveRequests
    }
}

private final class AITextStreamActivityRegistry: @unchecked Sendable {
    static let shared = AITextStreamActivityRegistry()

    private let lock = NSLock()
    private var activeRequestIDs: [ObjectIdentifier: Set<UUID>] = [:]

    func begin(ownerID: ObjectIdentifier, requestID: UUID) {
        lock.lock()
        activeRequestIDs[ownerID, default: []].insert(requestID)
        lock.unlock()
    }

    func finish(ownerID: ObjectIdentifier, requestID: UUID) -> Bool {
        lock.lock()
        activeRequestIDs[ownerID]?.remove(requestID)
        let hasActiveRequests = activeRequestIDs[ownerID]?.isEmpty == false
        if !hasActiveRequests {
            activeRequestIDs.removeValue(forKey: ownerID)
        }
        lock.unlock()
        return hasActiveRequests
    }
}

protocol AIProvider: AnyObject {

    // Indicates if provider is processing a request
    var isProcessing: Bool { get set }

    /// Human-readable model identifier recorded in history, e.g. "gpt-4o", "gemini-flash-latest".
    var modelDisplayName: String { get }

    // Process text with optional system prompt and images
    func processText(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String

    // Process text as a stream of response deltas.
    func processTextStream(systemPrompt: String?, userPrompt: String, images: [Data]) -> AITextStreamRequest

    // Cancel ongoing requests
    func cancel()
}

extension AIProvider {
    var modelDisplayName: String { "" }

    func processTextStream(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data]
    ) -> AITextStreamRequest {
        let requestID = UUID()
        let ownerID = ObjectIdentifier(self)
        let cancellation = AITextStreamCancellation()
        let activity = AITextStreamActivityRegistry.shared
        activity.begin(ownerID: ownerID, requestID: requestID)
        isProcessing = true

        let values = AsyncThrowingStream<String, Error> { continuation in
            let task = Task { [weak self] in
                defer {
                    let hasActiveRequests = activity.finish(
                        ownerID: ownerID,
                        requestID: requestID
                    )
                    self?.isProcessing = hasActiveRequests
                }

                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    let response = try await self.processText(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        images: images,
                        streaming: false
                    )

                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(response)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            cancellation.install {
                task.cancel()
            }
            continuation.onTermination = { _ in
                cancellation.cancel()
            }
        }

        return AITextStreamRequest(
            id: requestID,
            values: values,
            cancellation: cancellation
        )
    }
}

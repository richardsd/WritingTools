import Foundation

protocol AIProvider: AnyObject {

    // Indicates if provider is processing a request
    var isProcessing: Bool { get set }

    /// Human-readable model identifier recorded in history, e.g. "gpt-4o", "gemini-flash-latest".
    var modelDisplayName: String { get }

    // Process text with optional system prompt and images
    func processText(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String

    // Process text as a stream of response deltas.
    func processTextStream(systemPrompt: String?, userPrompt: String, images: [Data]) -> AsyncThrowingStream<String, Error>

    // Cancel ongoing requests
    func cancel()
}

extension AIProvider {
    var modelDisplayName: String { "" }

    func processTextStream(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
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

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

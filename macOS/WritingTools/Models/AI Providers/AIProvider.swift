import Foundation

protocol AIProvider {

    // Indicates if provider is processing a request
    var isProcessing: Bool { get set }

    /// Human-readable model identifier recorded in history, e.g. "gpt-4o", "gemini-flash-latest".
    var modelDisplayName: String { get }

    // Process text with optional system prompt and images
    func processText(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String

    // Cancel ongoing requests
    func cancel()
}

extension AIProvider {
    var modelDisplayName: String { "" }
}

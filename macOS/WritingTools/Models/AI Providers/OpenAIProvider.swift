import Foundation
import AIProxy
import Observation
import AppKit

private let logger = AppLogger.logger("OpenAIProvider")

enum OpenAIAuthMode: String, Codable, CaseIterable {
    case apiKey = "apiKey"
    case oauth = "oauth"
    
    var displayName: String {
        switch self {
        case .apiKey: return "API Key"
        case .oauth: return "ChatGPT OAuth"
        }
    }
}

struct OpenAIConfig: Codable {
    var apiKey: String
    var baseURL: String
    var model: String
    var authMode: OpenAIAuthMode
    
    static let defaultBaseURL = "https://api.openai.com"
    static let defaultModel = "gpt-5.3-codex"
}

// MARK: - Model Metadata

enum SubscriptionTier: String {
    case plus = "Plus"
    case pro = "Pro"
    case api = "API"
    
    var displayName: String {
        return rawValue
    }
}

enum ModelStatus: String {
    case current = "Current"
    case preview = "Preview"
    case legacy = "Legacy"
    case deprecated = "Deprecated"
}

struct ModelMetadata {
    let displayName: String
    let description: String
    let tier: SubscriptionTier
    let isRecommended: Bool
    let releaseDate: String
    let status: ModelStatus
    let documentationURL: String
}

enum OpenAIModel: String, CaseIterable {
    // Latest Codex models (GPT-5.3)
    case gpt53Codex = "gpt-5.3-codex"
    case gpt53CodexSpark = "gpt-5.3-codex-spark"
    
    // GPT-5.2 models
    case gpt52Codex = "gpt-5.2-codex"
    case gpt52 = "gpt-5.2"
    
    // GPT-5.1 models
    case gpt51CodexMax = "gpt-5.1-codex-max"
    case gpt51Codex = "gpt-5.1-codex"
    case gpt51CodexMini = "gpt-5.1-codex-mini"
    case gpt51 = "gpt-5.1"
    
    // GPT-5.0 models (legacy)
    case gpt5Codex = "gpt-5-codex"
    case gpt5CodexMini = "gpt-5-codex-mini"
    case gpt5 = "gpt-5"
    
    var displayName: String {
        return metadata.displayName
    }
    
    var description: String {
        return metadata.description
    }
    
    var metadata: ModelMetadata {
        switch self {
        case .gpt53Codex:
            return ModelMetadata(
                displayName: "GPT-5.3-Codex",
                description: "Most capable agentic coding model to date",
                tier: .plus,
                isRecommended: true,
                releaseDate: "2026-01",
                status: .current,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-3-codex"
            )
        case .gpt53CodexSpark:
            return ModelMetadata(
                displayName: "GPT-5.3-Codex-Spark",
                description: "Research preview for near-instant, real-time coding iteration",
                tier: .pro,
                isRecommended: false,
                releaseDate: "2026-01",
                status: .preview,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-3-codex-spark"
            )
        case .gpt52Codex:
            return ModelMetadata(
                displayName: "GPT-5.2-Codex",
                description: "Advanced coding model for real-world engineering",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-11",
                status: .current,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-2-codex"
            )
        case .gpt52:
            return ModelMetadata(
                displayName: "GPT-5.2",
                description: "Best general agentic model for tasks across domains",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-11",
                status: .current,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-2"
            )
        case .gpt51CodexMax:
            return ModelMetadata(
                displayName: "GPT-5.1-Codex-Max",
                description: "Optimized for long-horizon agentic coding tasks",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-08",
                status: .current,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-1-codex-max"
            )
        case .gpt51Codex:
            return ModelMetadata(
                displayName: "GPT-5.1-Codex",
                description: "Optimized for long-running agentic coding tasks",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-08",
                status: .current,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-1-codex"
            )
        case .gpt51CodexMini:
            return ModelMetadata(
                displayName: "GPT-5.1-Codex-Mini",
                description: "Smaller, more cost-effective version",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-08",
                status: .current,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-1-codex-mini"
            )
        case .gpt51:
            return ModelMetadata(
                displayName: "GPT-5.1",
                description: "Great for coding and agentic tasks across domains",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-08",
                status: .current,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-1"
            )
        case .gpt5Codex:
            return ModelMetadata(
                displayName: "GPT-5-Codex",
                description: "Older version, succeeded by GPT-5.1-Codex",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-05",
                status: .legacy,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-codex"
            )
        case .gpt5CodexMini:
            return ModelMetadata(
                displayName: "GPT-5-Codex-Mini",
                description: "Older smaller version, succeeded by GPT-5.1-Codex-Mini",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-05",
                status: .legacy,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5-codex-mini"
            )
        case .gpt5:
            return ModelMetadata(
                displayName: "GPT-5",
                description: "Reasoning model for coding, succeeded by GPT-5.1",
                tier: .plus,
                isRecommended: false,
                releaseDate: "2025-05",
                status: .legacy,
                documentationURL: "https://developers.openai.com/codex/models#gpt-5"
            )
        }
    }
}

@Observable
final class OpenAIProvider: AIProvider {
    var isProcessing = false
    private var config: OpenAIConfig
    private var aiProxyService: OpenAIService?
    private var currentTask: Task<Void, Never>?
    
    // OAuth state
    private var callbackServer: CodexCallbackServer?
    private var pkceVerifier: String?
    private var oauthState: String?
    
    init(config: OpenAIConfig) {
        self.config = config
        setupAIProxyService()
    }
    
    private func setupAIProxyService() {
        // Only setup AIProxy for API key mode
        guard config.authMode == .apiKey, !config.apiKey.isEmpty else { return }
        
        // Use custom base URL if provided, otherwise use default
        let baseURL = config.baseURL.isEmpty ? OpenAIConfig.defaultBaseURL : config.baseURL
        
        aiProxyService = AIProxy.openAIDirectService(
            unprotectedAPIKey: config.apiKey,
            baseURL: baseURL
        )
    }
    
    // MARK: - OAuth Flow
    
    @MainActor
    func initiateOAuthFlow() async throws {
        logger.debug("Initiating OAuth flow")
        
        // Generate PKCE and state
        let pkce = CodexAuth.generatePkce()
        let state = CodexAuth.generateState()
        
        self.pkceVerifier = pkce.verifier
        self.oauthState = state
        
        // Start callback server
        let server = CodexCallbackServer()
        self.callbackServer = server
        
        // Open browser
        let authorizeUrl = CodexAuth.buildAuthorizeUrl(pkce: pkce, state: state)
        NSWorkspace.shared.open(authorizeUrl)
        
        // Wait for callback
        do {
            let code = try await self.callbackServer!.start(expectedState: state)
            logger.debug("Received authorization code")
            
            // Exchange code for tokens
            try await completeOAuthFlow(code: code)
        } catch {
            self.callbackServer = nil
            self.pkceVerifier = nil
            self.oauthState = nil
            throw error
        }
    }
    
    private func completeOAuthFlow(code: String) async throws {
        guard let pkceVerifier = pkceVerifier else {
            throw CodexAuthError.invalidState
        }
        
        logger.debug("Exchanging code for tokens")
        let tokens = try await CodexAuth.exchangeCodeForTokens(code: code, pkceVerifier: pkceVerifier)
        
        // Save tokens to keychain
        try await AppSettings.shared.saveOAuthTokens(tokens)
        
        logger.debug("OAuth flow completed successfully")
        
        // Cleanup
        self.callbackServer = nil
        self.pkceVerifier = nil
        self.oauthState = nil
    }
    
    @MainActor
    func signOutOAuth() throws {
        try AppSettings.shared.deleteOAuthTokens()
        logger.debug("Signed out from OAuth")
    }
    
    private func ensureValidOAuthToken() async throws -> String {
        guard var tokens = try await AppSettings.shared.retrieveOAuthTokens() else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in with OAuth"])
        }
        
        // Check if token needs refresh
        if tokens.isExpiringSoon {
            logger.debug("Access token expiring soon, refreshing...")
            tokens = try await CodexAuth.refreshAccessToken(refreshToken: tokens.refreshToken)
            try await AppSettings.shared.saveOAuthTokens(tokens)
            logger.debug("Token refreshed successfully")
        }
        
        return tokens.accessToken
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = [], streaming: Bool = false) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        // Route to appropriate handler based on auth mode
        switch config.authMode {
        case .apiKey:
            return try await processTextWithApiKey(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images, streaming: streaming)
        case .oauth:
            return try await processTextWithOAuth(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images, streaming: streaming)
        }
    }
    
    // MARK: - API Key Processing
    
    private func processTextWithApiKey(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }
            
        // Check for custom Base URL
        if !config.baseURL.isEmpty && config.baseURL != OpenAIConfig.defaultBaseURL {
            return try await performCustomOpenAIRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images, streaming: streaming)
        }
        
        if aiProxyService == nil {
            setupAIProxyService()
        }
        
        guard let openAIService = aiProxyService else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AIProxy service."])
        }
        
        var messages: [OpenAIChatCompletionRequestBody.Message] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(.system(content: .text(systemPrompt)))
        }
        
        // Handle text and images
        if images.isEmpty {
            messages.append(.user(content: .text(userPrompt)))
        } else {
            var parts: [OpenAIChatCompletionRequestBody.Message.ContentPart] = [.text(userPrompt)]
            
            for imageData in images {
                let dataString = "data:image/jpeg;base64," + imageData.base64EncodedString()
                if let dataURL = URL(string: dataString) {
                    parts.append(.imageURL(dataURL, detail: .auto))
                }
            }
            
            messages.append(.user(content: .parts(parts)))
        }
        
        do {
            if streaming {
                var compiledResponse = ""
                let stream = try await openAIService.streamingChatCompletionRequest(body: .init(
                    model: config.model,
                    messages: messages
                ), secondsToWait: 60)
                
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let content = chunk.choices.first?.delta.content {
                        compiledResponse += content
                    }
                }
                return compiledResponse
                
            } else {
                let response = try await openAIService.chatCompletionRequest(body: .init(
                    model: config.model,
                    messages: messages
                ), secondsToWait: 60)
                
                return response.choices.first?.message.content ?? ""
            }
            
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("Received non-200 status code: \(statusCode) with response body: \(responseBody)")
            throw NSError(domain: "OpenAIAPI",
                          code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            logger.error("Could not create OpenAI chat completion: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - OAuth Processing
    
    private func processTextWithOAuth(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String {
        // Ensure we have a valid OAuth token
        let accessToken = try await ensureValidOAuthToken()
        
        // OAuth mode uses Codex Responses API endpoint
        let url = URL(string: CodexConstants.responsesEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build input array (Codex format uses "input" not "messages")
        var input: [[String: Any]] = []
        
        // Add user message to input
        if images.isEmpty {
            input.append([
                "role": "user",
                "content": [[
                    "type": "input_text",
                    "text": userPrompt
                ]]
            ])
        } else {
            var contentParts: [[String: Any]] = [
                ["type": "input_text", "text": userPrompt]
            ]
            
            for imageData in images {
                let base64 = imageData.base64EncodedString()
                contentParts.append([
                    "type": "input_image",
                    "image_url": "data:image/jpeg;base64,\(base64)",
                    "detail": "auto"
                ])
            }
            
            input.append([
                "role": "user",
                "content": contentParts
            ])
        }
        
        // Codex Responses API format
        var body: [String: Any] = [
            "model": config.model,
            "input": input,
            "stream": true,  // Required by Codex
            "store": false   // Required by Codex
        ]
        
        // Add instructions if provided (optional system prompt)
        if let instructions = systemPrompt, !instructions.isEmpty {
            body["instructions"] = instructions
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Handle streaming response (Codex-specific SSE format)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type."])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Read error response
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            logger.error("OAuth Codex Request Failed: \(httpResponse.statusCode) - \(errorBody)")
            throw NSError(domain: "OpenAIAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }
        
        // Parse Codex streaming response (different from standard OpenAI SSE)
        var compiledResponse = ""
        
        for try await line in bytes.lines {
            // Skip empty lines
            guard !line.isEmpty else { continue }
            
            // SSE format: "data: {json}"
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                
                // Check for [DONE] marker
                if jsonString == "[DONE]" {
                    break
                }
                
                // Parse JSON chunk
                guard let jsonData = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continue
                }
                
                // Extract event type
                guard let eventType = json["type"] as? String else {
                    continue
                }
                
                // Codex event: "response.output_text.delta"
                if eventType == "response.output_text.delta" {
                    if let delta = json["delta"] as? String {
                        compiledResponse += delta
                    }
                }
                
                // Codex event: "response.completed" or "response.incomplete"
                else if eventType == "response.completed" || eventType == "response.incomplete" {
                    // Extract final text if available
                    if let responseObj = json["response"] as? [String: Any],
                       let outputText = responseObj["output_text"] as? String {
                        // Use output_text if we didn't get deltas
                        if compiledResponse.isEmpty {
                            compiledResponse = outputText
                        }
                    }
                    break
                }
                
                // Codex event: "error"
                else if eventType == "error" {
                    if let message = json["message"] as? String {
                        throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Codex error: \(message)"])
                    }
                }
            }
        }
        
        return compiledResponse
    }
    
    // MARK: - Custom Request Implementation
    
    private func performCustomOpenAIRequest(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String {
        // Construct URL
        var urlString = config.baseURL
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        // Append /chat/completions if not present (simple heuristic, can be improved)
        if !urlString.hasSuffix("/chat/completions") {
             urlString += "/chat/completions"
        }
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Base URL."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Construct Body
        var messages: [[String: Any]] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        
        if images.isEmpty {
            messages.append(["role": "user", "content": userPrompt])
        } else {
            var content: [[String: Any]] = [
                ["type": "text", "text": userPrompt]
            ]
            
            for imageData in images {
                let base64 = imageData.base64EncodedString()
                content.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64)"
                    ]
                ])
            }
            messages.append(["role": "user", "content": content])
        }
        
        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": false // Forcing non-streaming for custom providers for now to ensure compatibility
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type."])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Custom OpenAI Request Failed: \(httpResponse.statusCode) - \(errorBody)")
            throw NSError(domain: "OpenAIAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }
        
        // Parse Response
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            return decoded.choices.first?.message.content ?? ""
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
             throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response."])
        }
    }

    
    func cancel() {
        isProcessing = false
        currentTask = nil
    }
}


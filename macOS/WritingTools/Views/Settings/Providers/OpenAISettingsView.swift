//
//  OpenAISettingsView.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import AppKit

struct OpenAISettingsView: View {
    @Bindable var settings = AppSettings.shared
    @Binding var needsSaving: Bool
    @State private var isAuthenticating = false
    @State private var authError: String?
    @State private var showingErrorAlert = false
    
    private var authMode: OpenAIAuthMode {
        OpenAIAuthMode(rawValue: settings.openAIAuthMode) ?? .apiKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Auth Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Authentication Method")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("", selection: $settings.openAIAuthMode) {
                    ForEach(OpenAIAuthMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.openAIAuthMode) { _, _ in
                    needsSaving = true
                }
            }
            
            Divider()
            
            // Show different UI based on auth mode
            if authMode == .apiKey {
                apiKeyView
            } else {
                oauthView
            }
        }
        .alert("OAuth Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = authError {
                Text(error)
            }
        }
    }
    
    // MARK: - API Key View
    
    private var apiKeyView: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Configuration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("API Key", text: $settings.openAIApiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.openAIApiKey) { _, _ in
                        needsSaving = true
                    }
                
                TextField("Base URL", text: $settings.openAIBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.openAIBaseURL) { _, _ in
                        needsSaving = true
                    }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Model Configuration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Model", selection: $settings.openAIModel) {
                    ForEach(OpenAIModel.allCases, id: \.rawValue) { model in
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            if !model.description.isEmpty {
                                Text(model.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(model.rawValue)
                    }
                }
                .onChange(of: settings.openAIModel) { _, _ in
                    needsSaving = true
                }
                
                Text("Select the model you want to use for text processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button("Get OpenAI API Key") {
                if let url = URL(string: "https://platform.openai.com/account/api-keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .help("Open OpenAI dashboard to create an API key.")
        }
    }
    
    // MARK: - OAuth View
    
    private var oauthView: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                Text("ChatGPT Subscription")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if settings.isOpenAISignedInWithOAuth {
                    // Signed in state
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in")
                                .font(.subheadline)
                            if let accountId = settings.openAIOAuthAccountId {
                                Text(accountId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Sign Out") {
                            signOutOAuth()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isAuthenticating)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                } else {
                    // Not signed in state
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sign in with your ChatGPT subscription to use OpenAI models without an API key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button(action: signInWithOAuth) {
                            HStack {
                                if isAuthenticating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                }
                                Text("Sign in with ChatGPT")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAuthenticating)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Model Configuration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Model", selection: $settings.openAIModel) {
                    ForEach(OpenAIModel.allCases, id: \.rawValue) { model in
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            if !model.description.isEmpty {
                                Text(model.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(model.rawValue)
                    }
                }
                .onChange(of: settings.openAIModel) { _, _ in
                    needsSaving = true
                }
                
                Text("Select the model you want to use for text processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - OAuth Actions
    
    private func signInWithOAuth() {
        isAuthenticating = true
        authError = nil
        
        Task {
            do {
                let config = OpenAIConfig(
                    apiKey: "",
                    baseURL: settings.openAIBaseURL,
                    model: settings.openAIModel,
                    authMode: .oauth
                )
                let provider = OpenAIProvider(config: config)
                try await provider.initiateOAuthFlow()
                
                await MainActor.run {
                    isAuthenticating = false
                    needsSaving = true
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    authError = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func signOutOAuth() {
        do {
            try settings.deleteOAuthTokens()
            needsSaving = true
        } catch {
            authError = error.localizedDescription
            showingErrorAlert = true
        }
    }
}

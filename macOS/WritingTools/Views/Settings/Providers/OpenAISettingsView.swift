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
    @State private var showingModelInfo = false
    @State private var selectedModelForInfo: CodexOAuthModel?
    
    private var authMode: OpenAIAuthMode {
        OpenAIAuthMode(rawValue: settings.openAIAuthMode) ?? .apiKey
    }
    
    private var selectedOAuthModel: CodexOAuthModel {
        CodexOAuthModel(rawValue: settings.openAIOAuthModel) ?? .defaultModel
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
        .sheet(isPresented: $showingModelInfo) {
            if let model = selectedModelForInfo {
                ModelInfoSheet(model: model)
            }
        }
    }
    
    // MARK: - Model Picker Row
    
    @ViewBuilder
    private func oauthModelPickerRow(for model: CodexOAuthModel) -> some View {
        HStack(spacing: 8) {
            if model == .defaultModel {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.metadata.displayName)
                        .font(.body)
                    
                    Text(model.metadata.availability)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model == .gpt53CodexSpark ? Color.purple : Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(4)

                    if model.metadata.status != .current {
                        Text(model.metadata.status.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusBadgeColor(model.metadata.status))
                            .foregroundStyle(.white)
                            .cornerRadius(4)
                    }
                }
                
                Text(model.metadata.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
    
    private func statusBadgeColor(_ status: CodexOAuthModelStatus) -> Color {
        switch status {
        case .current: return .green
        case .preview: return .orange
        case .older: return .gray
        }
    }
    
    // MARK: - API Key View
    
    private var apiKeyView: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Configuration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                SecureField("API Key", text: $settings.openAIApiKey)
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

            if let migrationNotice = settings.openAIOAuthMigrationNotice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.blue)

                    Text(migrationNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Dismiss") {
                        settings.openAIOAuthMigrationNotice = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                .padding(10)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Model Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        selectedModelForInfo = selectedOAuthModel
                        showingModelInfo = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .help("Show model information")
                }
                
                Picker("Model", selection: $settings.openAIOAuthModel) {
                    ForEach(CodexOAuthModelGroup.allCases) { group in
                        Section(group.rawValue) {
                            ForEach(CodexOAuthModel.models(in: group)) { model in
                                oauthModelPickerRow(for: model)
                                    .tag(model.rawValue)
                            }
                        }
                    }
                }
                .onChange(of: settings.openAIOAuthModel) { _, newModelID in
                    let model = CodexOAuthModel(rawValue: newModelID) ?? .defaultModel
                    let currentEffort = CodexReasoningEffort(
                        rawValue: settings.openAIOAuthReasoningEffort
                    ) ?? CodexOAuthModel.defaultEffort
                    settings.openAIOAuthReasoningEffort = currentEffort
                        .normalized(for: model)
                        .rawValue
                    needsSaving = true
                }
                
                Text("Select the model you want to use for text processing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let retirementNotice = selectedOAuthModel.metadata.retirementNotice {
                    Label(retirementNotice, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !selectedOAuthModel.supportsImages {
                    Label("This model accepts text only.", systemImage: "textformat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Reasoning Effort")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Reasoning", selection: $settings.openAIOAuthReasoningEffort) {
                    ForEach(selectedOAuthModel.supportedReasoningEfforts) { effort in
                        Text(effort.displayName).tag(effort.rawValue)
                    }
                }
                .onChange(of: settings.openAIOAuthReasoningEffort) { _, _ in
                    needsSaving = true
                }

                let selectedEffort = CodexReasoningEffort(
                    rawValue: settings.openAIOAuthReasoningEffort
                ) ?? selectedOAuthModel.recommendedReasoningEffort
                Text(selectedEffort.description)
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
                    model: settings.openAIOAuthModel,
                    authMode: .oauth,
                    oauthReasoningEffort: CodexReasoningEffort(
                        rawValue: settings.openAIOAuthReasoningEffort
                    ) ?? CodexOAuthModel.defaultEffort
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

// MARK: - Model Info Sheet

struct ModelInfoSheet: View {
    let model: CodexOAuthModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.metadata.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(model.metadata.availability)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(model == .gpt53CodexSpark ? Color.purple : Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(6)
                    }
                    
                    if model.metadata.status != .current {
                        HStack(spacing: 4) {
                            Image(systemName: statusIcon(model.metadata.status))
                                .font(.caption2)
                            Text(model.metadata.status.rawValue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusBadgeColor(model.metadata.status))
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
            }
            
            Divider()
            
            // Description
            VStack(alignment: .leading, spacing: 12) {
                Text("About")
                    .font(.headline)
                
                Text(model.metadata.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.headline)
                
                DetailRow(label: "Model ID", value: model.rawValue)
                DetailRow(label: "Status", value: model.metadata.status.rawValue)
                DetailRow(label: "Available with", value: model.metadata.availability)
                DetailRow(label: "Images", value: model.supportsImages ? "Supported" : "Text only")
                DetailRow(
                    label: "Reasoning",
                    value: model.supportedReasoningEfforts.map(\.displayName).joined(separator: ", ")
                )

                if model == .defaultModel {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("Default model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let retirementNotice = model.metadata.retirementNotice {
                Label(retirementNotice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            Spacer()
            
            // Learn More button
            Button(action: {
                if let url = URL(string: model.metadata.documentationURL) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("Learn More", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 450, height: 400)
    }

    private func statusBadgeColor(_ status: CodexOAuthModelStatus) -> Color {
        switch status {
        case .current: return .green
        case .preview: return .orange
        case .older: return .gray
        }
    }

    private func statusIcon(_ status: CodexOAuthModelStatus) -> String {
        switch status {
        case .current: return "checkmark.circle.fill"
        case .preview: return "sparkles"
        case .older: return "clock"
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
        }
    }
}

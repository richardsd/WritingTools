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
    @State private var selectedModelForInfo: OpenAIModel?
    
    private var authMode: OpenAIAuthMode {
        OpenAIAuthMode(rawValue: settings.openAIAuthMode) ?? .apiKey
    }
    
    // Sorted models: Recommended → Current (newest) → Preview → Legacy
    private var sortedModels: [OpenAIModel] {
        OpenAIModel.allCases.sorted { model1, model2 in
            let meta1 = model1.metadata
            let meta2 = model2.metadata
            
            // Recommended first
            if meta1.isRecommended != meta2.isRecommended {
                return meta1.isRecommended
            }
            
            // Then by status priority: current > preview > legacy > deprecated
            let statusPriority: [ModelStatus: Int] = [
                .current: 3,
                .preview: 2,
                .legacy: 1,
                .deprecated: 0
            ]
            let priority1 = statusPriority[meta1.status] ?? 0
            let priority2 = statusPriority[meta2.status] ?? 0
            if priority1 != priority2 {
                return priority1 > priority2
            }
            
            // Then by release date (newest first)
            return meta1.releaseDate > meta2.releaseDate
        }
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
    private func modelPickerRow(for model: OpenAIModel) -> some View {
        HStack(spacing: 8) {
            // Recommended star
            if model.metadata.isRecommended {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.metadata.displayName)
                        .font(.body)
                    
                    // Tier badge
                    Text(model.metadata.tier.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tierBadgeColor(model.metadata.tier))
                        .foregroundStyle(.white)
                        .cornerRadius(4)
                    
                    // Status badge (only for preview/legacy)
                    if model.metadata.status == .preview || model.metadata.status == .legacy {
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
    
    private func tierBadgeColor(_ tier: SubscriptionTier) -> Color {
        switch tier {
        case .plus: return .blue
        case .pro: return .purple
        case .api: return .gray
        }
    }
    
    private func statusBadgeColor(_ status: ModelStatus) -> Color {
        switch status {
        case .current: return .green
        case .preview: return .orange
        case .legacy: return .gray
        case .deprecated: return .red
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
                HStack {
                    Text("Model Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        selectedModelForInfo = OpenAIModel(rawValue: settings.openAIModel)
                        showingModelInfo = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .help("Show model information")
                }
                
                Picker("Model", selection: $settings.openAIModel) {
                    ForEach(sortedModels, id: \.rawValue) { model in
                        modelPickerRow(for: model)
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

// MARK: - Model Info Sheet

struct ModelInfoSheet: View {
    let model: OpenAIModel
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
                        
                        // Tier badge
                        Text(model.metadata.tier.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tierBadgeColor(model.metadata.tier))
                            .foregroundStyle(.white)
                            .cornerRadius(6)
                    }
                    
                    // Status badge if not current
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
            
            // Details
            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.headline)
                
                DetailRow(label: "Status", value: model.metadata.status.rawValue)
                DetailRow(label: "Required", value: "ChatGPT \(model.metadata.tier.displayName) subscription")
                DetailRow(label: "Released", value: formatReleaseDate(model.metadata.releaseDate))
                
                if model.metadata.isRecommended {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("Recommended model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
    
    private func tierBadgeColor(_ tier: SubscriptionTier) -> Color {
        switch tier {
        case .plus: return .blue
        case .pro: return .purple
        case .api: return .gray
        }
    }
    
    private func statusBadgeColor(_ status: ModelStatus) -> Color {
        switch status {
        case .current: return .green
        case .preview: return .orange
        case .legacy: return .gray
        case .deprecated: return .red
        }
    }
    
    private func statusIcon(_ status: ModelStatus) -> String {
        switch status {
        case .current: return "checkmark.circle.fill"
        case .preview: return "sparkles"
        case .legacy: return "clock"
        case .deprecated: return "exclamationmark.triangle"
        }
    }
    
    private func formatReleaseDate(_ date: String) -> String {
        // Format "2026-01" to "January 2026"
        let components = date.split(separator: "-")
        guard components.count == 2,
              let year = components.first,
              let monthNum = Int(components.last ?? "") else {
            return date
        }
        
        let months = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        let monthName = (monthNum >= 1 && monthNum <= 12) ? months[monthNum - 1] : ""
        return "\(monthName) \(year)"
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


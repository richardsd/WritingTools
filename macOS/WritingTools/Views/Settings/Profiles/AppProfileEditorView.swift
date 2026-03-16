import SwiftUI
import AppKit

/// Right-panel editor for a single AppProfile.
struct AppProfileEditorView: View {
    @Binding var profile: AppProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: General
                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Name")
                                .frame(width: 100, alignment: .leading)
                            TextField("Profile name", text: $profile.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Enabled")
                                .frame(width: 100, alignment: .leading)
                            Toggle("", isOn: $profile.isEnabled)
                                .labelsHidden()
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Formatting Preset
                GroupBox("Formatting Preset") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Preset", selection: $profile.formattingPreset) {
                            ForEach(FormattingPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(profile.formattingPreset.instructionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Additional Instructions
                GroupBox("Additional Instructions") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Appended after the preset instructions when this profile matches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $profile.additionalInstructions)
                            .font(.system(size: 12))
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.vertical, 4)
                }

                // MARK: App Matching Rules
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($profile.matchers) { $matcher in
                            AppMatcherRowView(matcher: $matcher) {
                                profile.matchers.removeAll { $0.id == matcher.id }
                            }
                            if matcher.id != profile.matchers.last?.id {
                                Divider()
                            }
                        }

                        if profile.matchers.isEmpty {
                            Text("No matching rules. Add a rule or this profile will never match.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }

                        HStack {
                            Button {
                                profile.matchers.append(AppMatcher())
                            } label: {
                                Label("Add Rule", systemImage: "plus")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                populateFromFrontmostApp()
                            } label: {
                                Label("Use Frontmost App", systemImage: "arrow.up.left.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .help("Detect the last-triggered app and pre-fill a new matching rule.")

                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text("App Matching Rules")
                }
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func populateFromFrontmostApp() {
        // AppState.previousApplication captures the last app writing-tools was triggered from.
        // Using it here is deliberate: Settings is currently frontmost, so reading the live
        // frontmost application would always return Settings/Xcode itself.
        guard let app = AppState.shared.previousApplication else { return }

        var matcher = AppMatcher()
        matcher.bundleIdentifierEquals = app.bundleIdentifier ?? ""
        matcher.appNameContains = app.localizedName ?? ""
        profile.matchers.append(matcher)
    }
}

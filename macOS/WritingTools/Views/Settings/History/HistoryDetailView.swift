import SwiftUI
import AppKit

/// Full detail view for a selected history entry, shown in the right panel.
struct HistoryDetailView: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    @State private var rerunFailed = false
    @State private var showRerunUnavailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.commandName)
                        .font(.title3.bold())

                    HStack(spacing: 12) {
                        Label(entry.timestamp.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "clock")

                        if let appName = entry.sourceAppName {
                            Label(appName, systemImage: "app.badge")
                        }

                        if let modelName = entry.modelName {
                            Label(modelName, systemImage: "cpu")
                        }

                        if let profileName = entry.matchedProfileName {
                            Label(profileName, systemImage: "person.crop.rectangle.stack")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()

                // MARK: Action Buttons
                HStack(spacing: 8) {
                    Button {
                        copyToClipboard(entry.inputText)
                    } label: {
                        Label("Copy Input", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help("Copy the original selected text to the clipboard.")

                    Button {
                        copyToClipboard(entry.outputText)
                    } label: {
                        Label("Copy Output", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Copy the LLM response to the clipboard.")

                    Button {
                        let success = HistoryManager.shared.rerun(entry)
                        if !success { showRerunUnavailable = true }
                    } label: {
                        Label("Re-run", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Re-run this command on the same input text using the current command prompt.")
                    .alert("Command Unavailable", isPresented: $showRerunUnavailable) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("The command '\(entry.commandName)' no longer exists and cannot be re-run.")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Remove this entry from history.")
                }

                // MARK: Input
                GroupBox("Input") {
                    ScrollView {
                        Text(entry.inputText)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(minHeight: 80, maxHeight: 180)
                }

                // MARK: Output
                GroupBox("Output") {
                    ScrollView {
                        Text(entry.outputText)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(minHeight: 80, maxHeight: 240)
                }
            }
            .padding(16)
        }
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

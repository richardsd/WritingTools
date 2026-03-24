import SwiftUI
import AppKit

/// Full detail view for a selected history entry, shown in the right panel.
struct HistoryDetailView: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    private enum ViewMode: String, CaseIterable {
        case split = "Split"
        case diff  = "Diff"
    }

    @State private var showRerunUnavailable = false
    @State private var viewMode: ViewMode = .split

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

                    Picker("", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    Spacer()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Remove this entry from history.")
                }

                // MARK: Content Panels
                if viewMode == .split {
                    // MARK: Input
                    CopyableContentBox(title: "Input", textToCopy: entry.inputText) {
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
                    CopyableContentBox(title: "Output", textToCopy: entry.outputText) {
                        ScrollView {
                            Text(entry.outputText)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                        .frame(minHeight: 80, maxHeight: 240)
                    }
                } else {
                    // MARK: Diff — copy button copies the final output
                    CopyableContentBox(title: "Changes", textToCopy: entry.outputText) {
                        ScrollView {
                            Text(buildDiff())
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4)
                        }
                        .frame(minHeight: 80)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Word-level diff

    private func buildDiff() -> AttributedString {
        let inputWords  = entry.inputText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let outputWords = entry.outputText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        let diff = outputWords.difference(from: inputWords)

        var removedInputIndices   = Set<Int>()
        var insertedOutputIndices = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removedInputIndices.insert(offset)
            case .insert(let offset, _, _): insertedOutputIndices.insert(offset)
            }
        }

        enum Span { case unchanged(String), removed(String), inserted(String) }
        var spans: [Span] = []
        var iIdx = 0   // cursor into inputWords
        var oIdx = 0   // cursor into outputWords

        while iIdx < inputWords.count || oIdx < outputWords.count {
            if iIdx < inputWords.count && removedInputIndices.contains(iIdx) {
                spans.append(.removed(inputWords[iIdx]))
                iIdx += 1
            } else if oIdx < outputWords.count && insertedOutputIndices.contains(oIdx) {
                spans.append(.inserted(outputWords[oIdx]))
                oIdx += 1
            } else {
                // Unchanged word present in both sequences
                if iIdx < inputWords.count {
                    spans.append(.unchanged(inputWords[iIdx]))
                }
                iIdx += 1
                oIdx += 1
            }
        }

        var result = AttributedString()
        for (i, span) in spans.enumerated() {
            if i > 0 { result += AttributedString(" ") }
            switch span {
            case .unchanged(let w):
                result += AttributedString(w)
            case .removed(let w):
                var piece = AttributedString(w)
                piece.foregroundColor = Color(nsColor: .systemRed)
                piece.strikethroughStyle = Text.LineStyle(pattern: .solid)
                result += piece
            case .inserted(let w):
                var piece = AttributedString(w)
                piece.foregroundColor = Color(nsColor: .systemGreen)
                result += piece
            }
        }
        return result
    }
}

// MARK: - CopyableContentBox

/// A GroupBox whose label row contains a title on the left and a copy-to-clipboard
/// icon button on the right, keeping the action close to the relevant content.
private struct CopyableContentBox<Content: View>: View {
    let title: String
    let textToCopy: String
    @ViewBuilder let content: () -> Content

    @State private var showCopied = false

    var body: some View {
        GroupBox {
            content()
        } label: {
            HStack {
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(textToCopy, forType: .string)
                    showCopied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2))
                        showCopied = false
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .frame(width: 12, height: 12)
                }
                .font(.caption2)
                .buttonStyle(.borderless)
                .help(showCopied ? "" : "Copy to clipboard")
            }
        }
    }
}

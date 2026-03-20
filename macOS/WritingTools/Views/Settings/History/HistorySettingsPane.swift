import SwiftUI

/// Full-width split-view settings pane for browsing and managing command history.
struct HistorySettingsPane<SaveButton: View>: View {
    let saveButton: SaveButton

    @State private var historyManager = HistoryManager.shared
    @State private var selectedEntryId: UUID?
    @State private var searchText = ""
    @State private var filterCommandName = "All"
    @State private var filterAppName = "All"
    @State private var showingClearConfirm = false

    // MARK: - Derived data

    private var allCommandNames: [String] {
        let names = Set(historyManager.entries.map { $0.commandName }).sorted()
        return ["All"] + names
    }

    private var allAppNames: [String] {
        let names = Set(historyManager.entries.compactMap { $0.sourceAppName }).sorted()
        return ["All"] + names
    }

    private var filteredEntries: [HistoryEntry] {
        historyManager.entries.filter { entry in
            let matchesSearch = searchText.isEmpty
                || entry.inputText.localizedCaseInsensitiveContains(searchText)
                || entry.outputText.localizedCaseInsensitiveContains(searchText)
                || entry.commandName.localizedCaseInsensitiveContains(searchText)

            let matchesCommand = filterCommandName == "All"
                || entry.commandName == filterCommandName

            let matchesApp = filterAppName == "All"
                || entry.sourceAppName == filterAppName

            return matchesSearch && matchesCommand && matchesApp
        }
    }

    private var selectedEntry: HistoryEntry? {
        guard let id = selectedEntryId else { return nil }
        return historyManager.entries.first { $0.id == id }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {

                // MARK: Left — List & Filters
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(.bar)

                    Divider()

                    // Filter row
                    if !historyManager.entries.isEmpty {
                        HStack(spacing: 6) {
                            Picker("Command", selection: $filterCommandName) {
                                ForEach(allCommandNames, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)

                            Picker("App", selection: $filterAppName) {
                                ForEach(allAppNames, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.bar)

                        Divider()
                    }

                    // List
                    List(selection: $selectedEntryId) {
                        ForEach(filteredEntries) { entry in
                            HistoryRowView(entry: entry)
                                .tag(entry.id)
                        }
                    }
                    .listStyle(.inset)
                    .overlay {
                        if historyManager.entries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No history yet")
                                    .foregroundStyle(.secondary)
                                Text("Run a command to start recording")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if filteredEntries.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("No matching entries")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Bottom toolbar
                    HStack(spacing: 4) {
                        Text("\(historyManager.entries.count) / \(HistoryManager.maxEntries)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)

                        Spacer()

                        Button {
                            showingClearConfirm = true
                        } label: {
                            Text("Clear All")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .disabled(historyManager.entries.isEmpty)
                        .padding(.trailing, 8)
                        .confirmationDialog(
                            "Clear all history?",
                            isPresented: $showingClearConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Clear All", role: .destructive) {
                                historyManager.clearAll()
                                selectedEntryId = nil
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will permanently delete all \(historyManager.entries.count) history entries.")
                        }
                    }
                    .frame(height: 32)
                    .background(.bar)
                }
                .frame(maxWidth: 260)

                Divider()

                // MARK: Right — Detail or Placeholder
                Group {
                    if let entry = selectedEntry {
                        HistoryDetailView(entry: entry) {
                            deleteEntry(entry)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("Select an entry to view details")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                if !AppSettings.shared.isHistoryEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Text("History recording is disabled. Enable it in General settings.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Spacer()
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        // Keep selectedEntryId valid if list changes
        .onChange(of: historyManager.entries) { _, newEntries in
            if let id = selectedEntryId, !newEntries.contains(where: { $0.id == id }) {
                selectedEntryId = nil
            }
        }
    }

    // MARK: - Helpers

    private func deleteEntry(_ entry: HistoryEntry) {
        let idx = historyManager.entries.firstIndex(where: { $0.id == entry.id })
        historyManager.delete(entry)

        if !historyManager.entries.isEmpty, let idx {
            let newIdx = min(idx, historyManager.entries.count - 1)
            selectedEntryId = historyManager.entries[newIdx].id
        } else {
            selectedEntryId = nil
        }
    }
}

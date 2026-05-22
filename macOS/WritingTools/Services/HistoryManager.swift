import Foundation
import Observation
import AppKit

/// Manages the persistent command history log.
@Observable
@MainActor
final class HistoryManager {

    static let shared = HistoryManager()

    // MARK: - State

    /// All entries, sorted newest-first.
    private(set) var entries: [HistoryEntry] = []

    static let maxEntries = 100

    private var storageURL: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = appSupport.appendingPathComponent("WritingTools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("command_history.json")
    }

    // MARK: - Init

    private init() {
        loadFromDisk()
    }

    // MARK: - Recording

    /// Records a completed command execution. No-op when history is disabled.
    func record(
        commandName: String,
        commandId: UUID?,
        inputText: String,
        outputText: String,
        modelName: String?,
        sourceApp: NSRunningApplication?,
        matchedProfileName: String?,
        writingCoachPreset: WritingCoachPreset? = nil
    ) {
        guard AppSettings.shared.isHistoryEnabled else { return }
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let entry = HistoryEntry(
            commandName: commandName,
            commandId: commandId,
            inputText: inputText,
            outputText: outputText,
            modelName: modelName,
            sourceAppName: sourceApp?.localizedName,
            sourceAppBundleId: sourceApp?.bundleIdentifier,
            matchedProfileName: matchedProfileName,
            writingCoachPreset: writingCoachPreset
        )

        entries.insert(entry, at: 0)

        // Auto-prune to max capacity
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }

        saveToDisk()
    }

    // MARK: - Deletion

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveToDisk()
    }

    func clearAll() {
        entries.removeAll()
        saveToDisk()
    }

    // MARK: - Re-run

    /// Re-runs the command from a history entry using the current prompt text.
    /// Returns false if the command no longer exists in CommandManager.
    @discardableResult
    func rerun(_ entry: HistoryEntry) -> Bool {
        let appState = AppState.shared

        // Find the command by saved ID
        guard let commandId = entry.commandId,
              let command = appState.commandManager.commands.first(where: { $0.id == commandId }) else {
            return false
        }

        // Restore selected text and trigger the command
        if command.responsePresentation == .writingCoach {
            AppSettings.shared.writingCoachPreset = entry.writingCoachPreset ?? .general
        }
        appState.selectedText = entry.inputText
        appState.selectedAttributedText = nil
        appState.processCommand(command)
        return true
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let url = storageURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func saveToDisk() {
        guard let url = storageURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

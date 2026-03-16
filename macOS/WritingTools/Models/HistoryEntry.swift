import Foundation

/// A single recorded command execution, stored in the local history log.
struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let commandName: String
    /// The UUID of the CommandModel that was run, used to re-run the command later.
    let commandId: UUID?
    let inputText: String
    let outputText: String
    let sourceAppName: String?
    let sourceAppBundleId: String?
    /// The name of the matched AppProfile at execution time, if any.
    let matchedProfileName: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        commandName: String,
        commandId: UUID? = nil,
        inputText: String,
        outputText: String,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil,
        matchedProfileName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.commandName = commandName
        self.commandId = commandId
        self.inputText = inputText
        self.outputText = outputText
        self.sourceAppName = sourceAppName
        self.sourceAppBundleId = sourceAppBundleId
        self.matchedProfileName = matchedProfileName
    }
}

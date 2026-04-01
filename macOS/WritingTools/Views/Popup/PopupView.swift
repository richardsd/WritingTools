import SwiftUI
import ApplicationServices
import Observation

private let logger = AppLogger.logger("PopupView")

@Observable
final class PopupViewModel {
  var isEditMode: Bool = false
}

private struct PopupPaletteSection: Identifiable {
  let title: String
  let items: [PopupPaletteItem]

  var id: String { title }
}

private struct PopupPaletteItem: Identifiable {
  enum Kind {
    case command(CommandModel)
    case history(HistoryEntry)
    case customInstruction(String)
  }

  let id: String
  let title: String
  let subtitle: String
  let icon: String
  let kind: Kind
  let isDisabled: Bool
  let isFavorite: Bool
}

struct PopupView: View {
  @Bindable var appState: AppState
  @Bindable var viewModel: PopupViewModel
  @Environment(\.colorScheme) var colorScheme
  @AppStorage("use_gradient_theme") private var useGradientTheme = false
  @FocusState private var isCustomInputFocused: Bool

  @State private var customText: String = ""
  @State private var isCustomLoading: Bool = false
  @State private var processingCommandId: UUID? = nil
  @State private var historyManager = HistoryManager.shared
  @State private var selectedPaletteItemID: String? = nil

  @State private var showingCommandsView = false
  @State private var editingCommand: CommandModel? = nil

  // Error handling
  @State private var showingErrorAlert = false
  @State private var errorMessage = ""

  let closeAction: () -> Void

  // Grid layout for two columns
  private let columns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
  ]

  private var hasCapturedContent: Bool {
    !appState.selectedText.isEmpty || !appState.selectedImages.isEmpty
  }

  private var popupChromeShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: PopupChrome.cornerRadius, style: .continuous)
  }

  var body: some View {
    VStack(spacing: 12) {
      // Top bar with buttons
      HStack {
        Button(action: {
          if viewModel.isEditMode {
            viewModel.isEditMode = false
          } else {
            closeAction()
          }
        }) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Color(.controlBackgroundColor))
            .clipShape(.circle)
        }
        .buttonStyle(.plain)
        .help(viewModel.isEditMode ? "Exit Edit Mode" : "Close")

        Spacer()

        Button(action: {
          viewModel.isEditMode.toggle()
          NotificationCenter.default.post(
            name: NSNotification.Name("EditModeChanged"),
            object: nil
          )
        }) {
          Image(
            systemName: viewModel.isEditMode ? "checkmark" : "square.and.pencil"
          )
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .background(Color(.controlBackgroundColor))
          .clipShape(.circle)
        }
        .buttonStyle(.plain)
        .help(viewModel.isEditMode ? "Save Changes" : "Edit Commands")
      }
      .padding(.horizontal, 10)
      .padding(.top, 10)

      if !viewModel.isEditMode {
        TextField(
          "Search commands or type a custom instruction...",
          text: $customText
        )
        .focused($isCustomInputFocused)
        .textFieldStyle(.plain)
        .appleStyleTextField(
          text: customText,
          isLoading: isCustomLoading,
          onSubmit: executeSelectedPaletteItem
        )
        .padding(.horizontal, 10)
        popupContextHeader
          .padding(.horizontal, 16)
        popupSelectionStatusView
          .padding(.horizontal, 16)
        paletteListView
      }

      if viewModel.isEditMode {
        Divider()
          .padding(.horizontal, 10)

        LazyVGrid(columns: columns, spacing: 8) {
          ForEach(appState.commandManager.commands) { command in
            CommandButton(
              command: command,
              isEditing: viewModel.isEditMode,
              isLoading: processingCommandId == command.id,
              onTap: {
                processingCommandId = command.id
                Task {
                  await processCommandAndCloseWhenDone(command)
                }
              },
              onEdit: {
                editingCommand = command
              },
              onDelete: {
                logger.debug("Deleting command: \(command.name)")
                appState.commandManager.deleteCommand(command)
              }
            )
          }
        }
        .padding(.horizontal, 16)

        Button(action: { showingCommandsView = true }) {
          HStack {
            Image(systemName: "plus.circle.fill")
            Text("Manage Commands")
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color(.controlBackgroundColor))
          .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
      }
    }
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, alignment: .top)
    .background {
      popupChromeShape
        .fill(Color.clear)
        .windowBackground(
          useGradient: useGradientTheme,
          cornerRadius: PopupChrome.cornerRadius
        )
        .overlay {
          popupChromeShape
            .strokeBorder(
              Color.primary.opacity(PopupChrome.borderOpacity),
              lineWidth: 1
            )
        }
        .shadow(
          color: Color.black.opacity(PopupChrome.shadowOpacity),
          radius: PopupChrome.shadowRadius,
          y: PopupChrome.shadowYOffset
        )
    }
    .padding(PopupChrome.chromeInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background {
      if !viewModel.isEditMode {
        PopupKeyMonitor(
          onMoveUp: { moveSelection(delta: -1) },
          onMoveDown: { moveSelection(delta: 1) },
          onReturn: { executeSelectedPaletteItem() },
          onEscape: { closeAction() }
        )
      }
    }
    // Sheet for editing individual command
    .sheet(item: $editingCommand) { command in
      let binding = Binding(
        get: { command },
        set: { updatedCommand in
          appState.commandManager.updateCommand(updatedCommand)
          editingCommand = nil
        }
      )

      CommandEditor(
        command: binding,
        onSave: {
          editingCommand = nil
        },
        onCancel: {
          editingCommand = nil
        },
        commandManager: appState.commandManager
      )
    }
    // Sheet for managing all commands
    .sheet(isPresented: $showingCommandsView) {
      CommandsView(commandManager: appState.commandManager)
        .onDisappear {
          NotificationCenter.default.post(
            name: NSNotification.Name("CommandsChanged"),
            object: nil
          )
        }
    }
    .alert("Error", isPresented: $showingErrorAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
    .task {
      focusCustomInputIfNeeded()
      ensurePaletteSelection()
    }
    .onChange(of: viewModel.isEditMode) { _, isEditMode in
      if isEditMode {
        isCustomInputFocused = false
      } else {
        focusCustomInputIfNeeded()
        ensurePaletteSelection()
      }
    }
    .onChange(of: customText) { _, _ in
      ensurePaletteSelection()
    }
    .onChange(of: paletteSignature) { _, _ in
      ensurePaletteSelection()
    }
  }

  @ViewBuilder
  private var popupSelectionStatusView: some View {
    switch appState.popupSelectionState {
    case .loading:
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("Capturing selection...")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(Color(.controlBackgroundColor))
      .clipShape(.rect(cornerRadius: 10))
    case .empty:
      HStack(spacing: 10) {
        Image(systemName: "text.cursor")
          .foregroundStyle(.secondary)
        Text("No selection detected. You can still type a custom instruction.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .font(.callout)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(Color(.controlBackgroundColor))
      .clipShape(.rect(cornerRadius: 10))
    case .failed(let message):
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(message ?? "Could not capture the current selection.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .font(.callout)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(Color(.controlBackgroundColor))
      .clipShape(.rect(cornerRadius: 10))
    case .idle, .ready:
      EmptyView()
    }
  }

  @ViewBuilder
  private var popupContextHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        ContextChip(
          icon: "app.badge",
          text: appState.previousApplication?.localizedName ?? "No app"
        )

        if let matchedProfileName {
          ContextChip(
            icon: "person.crop.rectangle.stack",
            text: matchedProfileName
          )
        }

        ContextChip(
          icon: "cpu",
          text: providerSummary
        )
      }

      HStack(spacing: 8) {
        ContextChip(
          icon: hasCapturedContent ? "selection.pin.in.out" : "text.cursor",
          text: selectionSummary
        )

        if !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContextChip(
            icon: "magnifyingglass",
            text: "\(visiblePaletteItems.count) results"
          )
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var matchedProfileName: String? {
    guard let app = appState.previousApplication else { return nil }
    return AppProfileService.shared
      .resolveProfile(for: ActiveAppContext(from: app))?
      .name
  }

  private var providerSummary: String {
    let providerName = friendlyProviderName(appState.currentProvider)
    let modelName = appState.activeProvider.modelDisplayName
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return modelName.isEmpty ? providerName : "\(providerName) · \(modelName)"
  }

  private var selectionSummary: String {
    if !appState.selectedText.isEmpty && !appState.selectedImages.isEmpty {
      return "\(appState.selectedText.count) chars + \(appState.selectedImages.count) image(s)"
    }

    if !appState.selectedText.isEmpty {
      return "\(appState.selectedText.count) characters selected"
    }

    if !appState.selectedImages.isEmpty {
      return "\(appState.selectedImages.count) image(s) selected"
    }

    switch appState.popupSelectionState {
    case .loading:
      return "Capturing selection"
    case .failed:
      return "Selection capture failed"
    default:
      return "No selection"
    }
  }

  @ViewBuilder
  private var paletteListView: some View {
    if visiblePaletteItems.isEmpty {
      VStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.title3)
          .foregroundStyle(.secondary)
        Text(
          customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No commands available."
            : "No matching commands."
        )
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: 120)
      .padding(.horizontal, 16)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(paletteSections) { section in
              VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .textCase(.uppercase)

                VStack(spacing: 4) {
                  ForEach(section.items) { item in
                    PopupPaletteRow(
                      item: item,
                      isSelected: item.id == selectedPaletteItemID
                    ) {
                      executePaletteItem(item)
                    }
                    .id(item.id)
                  }
                }
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
        }
        .frame(minHeight: 180, maxHeight: 320)
        .onChange(of: selectedPaletteItemID) { _, newValue in
          guard let newValue else { return }
          withAnimation(.easeInOut(duration: 0.12)) {
            proxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
    }
  }

  private var paletteSections: [PopupPaletteSection] {
    let query = customText.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let commands = appState.commandManager.commands
    let rankedCommands = commands
      .filter { matches(command: $0, query: query) }
      .sorted { lhs, rhs in
        rankedScore(for: lhs, query: query) > rankedScore(for: rhs, query: query)
      }

    var sections: [PopupPaletteSection] = []
    var seenCommandIDs = Set<UUID>()

    func appendCommandSection(
      title: String,
      commands: [CommandModel]
    ) {
      let items = commands.compactMap { command -> PopupPaletteItem? in
        guard !seenCommandIDs.contains(command.id) else { return nil }
        seenCommandIDs.insert(command.id)
        return paletteItem(for: command)
      }

      if !items.isEmpty {
        sections.append(PopupPaletteSection(title: title, items: items))
      }
    }

    appendCommandSection(
      title: "Suggested",
      commands: Array(rankedCommands.prefix(query.isEmpty ? 4 : 6))
    )
    appendCommandSection(
      title: "Favorites",
      commands: rankedCommands.filter(\.isFavorite)
    )
    appendCommandSection(
      title: "Recent",
      commands: recentCommands(from: rankedCommands)
    )
    appendCommandSection(
      title: "All Commands",
      commands: rankedCommands
    )

    let historyItems = recentHistoryItems(query: query)
    if !historyItems.isEmpty {
      sections.append(PopupPaletteSection(title: "Recent History", items: historyItems))
    }

    if !query.isEmpty {
      sections.append(
        PopupPaletteSection(
          title: "Custom Instruction",
          items: [customInstructionItem(for: customText)]
        )
      )
    }

    return sections
  }

  private var visiblePaletteItems: [PopupPaletteItem] {
    paletteSections.flatMap(\.items)
  }

  private var paletteSignature: String {
    visiblePaletteItems.map(\.id).joined(separator: "|")
  }

  private func recentCommands(
    from rankedCommands: [CommandModel]
  ) -> [CommandModel] {
    let rankedByID = Dictionary(uniqueKeysWithValues: rankedCommands.map { ($0.id, $0) })
    var recent: [CommandModel] = []
    var seen = Set<UUID>()

    for entry in historyManager.entries {
      guard let commandId = entry.commandId,
            let command = rankedByID[commandId],
            !seen.contains(commandId) else {
        continue
      }

      seen.insert(commandId)
      recent.append(command)

      if recent.count == 4 {
        break
      }
    }

    return recent
  }

  private func recentHistoryItems(query: String) -> [PopupPaletteItem] {
    let currentBundleID = appState.previousApplication?.bundleIdentifier
    let filteredEntries = historyManager.entries.filter { entry in
      let matchesQuery = query.isEmpty
        || entry.commandName.localizedCaseInsensitiveContains(query)
        || entry.inputText.localizedCaseInsensitiveContains(query)
        || entry.outputText.localizedCaseInsensitiveContains(query)

      return matchesQuery
    }

    let prioritizedEntries = filteredEntries.sorted { lhs, rhs in
      let lhsMatchesApp = lhs.sourceAppBundleId == currentBundleID
      let rhsMatchesApp = rhs.sourceAppBundleId == currentBundleID

      if lhsMatchesApp != rhsMatchesApp {
        return lhsMatchesApp
      }

      return lhs.timestamp > rhs.timestamp
    }

    return Array(prioritizedEntries.prefix(3)).map { entry in
      PopupPaletteItem(
        id: "history-\(entry.id.uuidString)",
        title: entry.commandName,
        subtitle: entry.inputText,
        icon: "clock.arrow.circlepath",
        kind: .history(entry),
        isDisabled: false,
        isFavorite: false
      )
    }
  }

  private func paletteItem(for command: CommandModel) -> PopupPaletteItem {
    let modeLabel: String
    let effectiveExecutionMode = appState.resolvedExecutionMode(for: command)

    switch effectiveExecutionMode {
    case .instantApply:
      if command.executionMode == .reviewBeforeApply {
        modeLabel = "Instant apply (Preview off)"
      } else {
        modeLabel = "Instant apply"
      }
    case .reviewBeforeApply:
      modeLabel = "Review first"
    case .responseWindow:
      modeLabel = "Response window"
    }

    let providerLabel =
      command.providerOverride.map(friendlyProviderName)
      ?? friendlyProviderName(appState.currentProvider)

    return PopupPaletteItem(
      id: "command-\(command.id.uuidString)",
      title: command.name,
      subtitle: "\(modeLabel) · \(providerLabel)",
      icon: command.icon,
      kind: .command(command),
      isDisabled: command.requiresSelectedText
        ? appState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
        : !hasCapturedContent,
      isFavorite: command.isFavorite
    )
  }

  private func customInstructionItem(for instruction: String) -> PopupPaletteItem {
    let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    return PopupPaletteItem(
      id: "custom-\(trimmed)",
      title: "Run custom instruction",
      subtitle: trimmed,
      icon: "text.bubble",
      kind: .customInstruction(trimmed),
      isDisabled: trimmed.isEmpty,
      isFavorite: false
    )
  }

  private func matches(command: CommandModel, query: String) -> Bool {
    guard !query.isEmpty else { return true }

    return command.name.localizedCaseInsensitiveContains(query)
      || command.prompt.localizedCaseInsensitiveContains(query)
  }

  private func rankedScore(for command: CommandModel, query: String) -> Int {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let normalizedName = command.name.lowercased()
    let currentBundleID = appState.previousApplication?.bundleIdentifier

    var score = 0

    if command.isFavorite {
      score += 250
    }

    if normalizedQuery.isEmpty {
      score += command.isBuiltIn ? 10 : 0
    } else if normalizedName == normalizedQuery {
      score += 300
    } else if normalizedName.hasPrefix(normalizedQuery) {
      score += 220
    } else if normalizedName.contains(normalizedQuery) {
      score += 140
    } else if command.prompt.lowercased().contains(normalizedQuery) {
      score += 40
    }

    if let providerOverride = command.providerOverride {
      if providerOverride == appState.currentProvider {
        score += 20
      }
    } else {
      score += 10
    }

    if let matchedProfileName {
      if matchedProfileName.localizedCaseInsensitiveContains("Code"),
         command.preserveFormatting {
        score += 10
      }

      if matchedProfileName.localizedCaseInsensitiveContains("Mail")
        || matchedProfileName.localizedCaseInsensitiveContains("Teams")
        || matchedProfileName.localizedCaseInsensitiveContains("Slack") {
        let lowercaseName = command.name.lowercased()
        if lowercaseName.contains("professional")
          || lowercaseName.contains("friendly")
          || lowercaseName.contains("proofread") {
          score += 16
        }
      }
    }

    if let entryIndex = historyManager.entries.firstIndex(where: { $0.commandId == command.id }) {
      score += max(120 - (entryIndex * 12), 20)
    }

    if let currentBundleID,
       historyManager.entries.contains(where: {
         $0.commandId == command.id && $0.sourceAppBundleId == currentBundleID
       }) {
      score += 110
    }

    return score
  }

  private func friendlyProviderName(_ provider: String) -> String {
    switch provider {
    case "openai":
      return "OpenAI"
    case "gemini":
      return "Gemini"
    case "anthropic":
      return "Anthropic"
    case "ollama":
      return "Ollama"
    case "mistral":
      return "Mistral"
    case "openrouter":
      return "OpenRouter"
    case "local":
      return "Local LLM"
    case "custom":
      return "Custom"
    default:
      return provider.capitalized
    }
  }

  @MainActor
  private func ensurePaletteSelection() {
    guard !viewModel.isEditMode else { return }

    if let selectedPaletteItemID,
       let currentItem = visiblePaletteItems.first(where: {
         $0.id == selectedPaletteItemID
       }),
       !currentItem.isDisabled {
      return
    }

    selectedPaletteItemID =
      visiblePaletteItems.first(where: { !$0.isDisabled })?.id
      ?? visiblePaletteItems.first?.id
  }

  private func moveSelection(delta: Int) {
    guard !visiblePaletteItems.isEmpty else { return }

    var nextIndex = visiblePaletteItems.firstIndex(where: {
      $0.id == selectedPaletteItemID
    }) ?? 0

    while true {
      let proposedIndex = min(
        max(nextIndex + delta, 0),
        visiblePaletteItems.count - 1
      )

      if proposedIndex == nextIndex {
        break
      }

      nextIndex = proposedIndex
      if !visiblePaletteItems[nextIndex].isDisabled {
        selectedPaletteItemID = visiblePaletteItems[nextIndex].id
        return
      }
    }

    selectedPaletteItemID = visiblePaletteItems[nextIndex].id
  }

  @MainActor
  private func executeSelectedPaletteItem() {
    if let selectedItem = visiblePaletteItems.first(where: {
      $0.id == selectedPaletteItemID
    }) {
      if selectedItem.isDisabled,
         let fallbackCustomInstruction = visiblePaletteItems.first(where: { item in
           if case .customInstruction = item.kind {
             return !item.isDisabled
           }
           return false
         }) {
        executePaletteItem(fallbackCustomInstruction)
      } else {
        executePaletteItem(selectedItem)
      }
    } else if !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      processCustomChange()
    }
  }

  @MainActor
  private func executePaletteItem(_ item: PopupPaletteItem) {
    guard !item.isDisabled else { return }

    switch item.kind {
    case .command(let command):
      processingCommandId = command.id
      Task {
        await processCommandAndCloseWhenDone(command)
      }
    case .history(let entry):
      let success = HistoryManager.shared.rerun(entry)
      if success {
        closeAction()
      } else {
        errorMessage = "The command '\(entry.commandName)' no longer exists and cannot be re-run."
        showingErrorAlert = true
      }
    case .customInstruction(let instruction):
      customText = instruction
      processCustomChange()
    }
  }

  @MainActor
  private func focusCustomInputIfNeeded() {
    guard !viewModel.isEditMode else { return }

    // Delay focus until the popup window is on screen and key.
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(100))
      isCustomInputFocused = true
    }
  }

  // Process a command asynchronously and only close the popup when done
  private func processCommandAndCloseWhenDone(
    _ command: CommandModel
  ) async {
    await appState.executeCommand(command, closePopup: closeAction)
    await MainActor.run {
      processingCommandId = nil
    }
  }

  @MainActor
  private func processCustomChange() {
    guard !customText.isEmpty, !isCustomLoading else { return }
    let instruction = customText
    isCustomLoading = true

    Task { @MainActor in
      await processCustomInstruction(instruction)
    }
  }

  @MainActor
  private func processCustomInstruction(_ instruction: String) async {
    guard !instruction.isEmpty else {
      isCustomLoading = false
      return
    }

    if let requestID = appState.popupCaptureRequestID,
      appState.popupSelectionState == .loading
    {
      let captureState = await appState.waitForPopupSelectionCaptureCompletion(
        for: requestID
      )

      if captureState == .idle {
        isCustomLoading = false
        return
      }
    }

    appState.isProcessing = true

    // Capture setting value once at the start
    let openInResponseWindow = AppSettings.shared.openCustomCommandsInResponseWindow

    let systemPrompt = """
    You are a writing and coding assistant. Your sole task is to respond \
    to the user's instruction thoughtfully and comprehensively.
    If the instruction is a question, provide a detailed answer. But \
    always return the best and most accurate answer and not different \
    options.
    If it's a request for help, provide clear guidance and examples where \
    appropriate. Make sure to use the language used or specified by the \
    user instruction.
    Use Markdown formatting to make your response more readable.
    """

    let selectedText = appState.selectedText
    let images = appState.selectedImages
    let userPrompt = selectedText.isEmpty
      ? instruction
      : """
        User's instruction: \(instruction)

        Text:
        \(selectedText)
        """

    if openInResponseWindow {
      let initialMessages = selectedText.isEmpty
        ? [ChatMessage(role: "user", content: instruction)]
        : []

      presentResponseWindow(
        title: "AI Response",
        initialMessages: initialMessages,
        selectedText: selectedText,
        option: .proofread,
        provider: appState.activeProvider,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        images: images
      )

      customText = ""
      isCustomLoading = false
      return
    }

    // Close popup and show HUD
    closeAction()
    WindowManager.shared.showProcessingHUD(
      commandName: "Custom Instruction",
      commandIcon: "text.bubble",
      onCancel: { [weak appState] in
        appState?.activeProvider.cancel()
        appState?.isProcessing = false
      }
    )

    Task {
      do {
        let result = try await appState.activeProvider.processText(
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          images: images,
          streaming: false
        )

        await MainActor.run {
          WindowManager.shared.dismissProcessingHUD()

          appState.replaceSelectedText(with: result)

          customText = ""
          isCustomLoading = false
        }
      } catch {
        logger.error("Error processing text: \(error.localizedDescription)")
        await MainActor.run {
          WindowManager.shared.dismissProcessingHUD()
          errorMessage = error.localizedDescription
          showingErrorAlert = true
          isCustomLoading = false
        }
      }

      appState.isProcessing = false
    }
  }

  @MainActor
  private func presentResponseWindow(
    title: String,
    initialMessages: [ChatMessage],
    selectedText: String,
    option: WritingOption?,
    provider: any AIProvider,
    systemPrompt: String?,
    userPrompt: String,
    images: [Data]
  ) {
    let viewModel = ResponseViewModel(
      initialMessages: initialMessages,
      selectedText: selectedText,
      option: option,
      provider: provider,
      conversationImages: images,
      baseSystemPrompt: systemPrompt
    )

    let window = ResponseWindow(title: title, viewModel: viewModel)
    NSApp.activate(ignoringOtherApps: true)
    WindowManager.shared.addResponseWindow(window)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()

    closeAction()

    Task { @MainActor in
      await Task.yield()
      viewModel.startInitialResponse(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        images: images,
        onFinish: {
        appState.isProcessing = false
        }
      )
    }
  }
}

private struct ContextChip: View {
  let icon: String
  let text: String

  var body: some View {
    Label(text, systemImage: icon)
      .font(.caption)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color(.controlBackgroundColor), in: Capsule())
  }
}

private struct PopupPaletteRow: View {
  let item: PopupPaletteItem
  let isSelected: Bool
  let onActivate: () -> Void

  var body: some View {
    Button(action: onActivate) {
      HStack(spacing: 10) {
        Image(systemName: item.icon)
          .foregroundStyle(item.isDisabled ? .secondary : Color.accentColor)
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(item.title)
              .foregroundStyle(item.isDisabled ? .secondary : .primary)
              .lineLimit(1)

            if item.isFavorite {
              Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            }
          }

          Text(item.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        if isSelected {
          Image(systemName: "return")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(.controlBackgroundColor))
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            isSelected ? Color.accentColor.opacity(0.35) : Color.clear,
            lineWidth: 1
          )
      }
      .opacity(item.isDisabled ? 0.55 : 1)
    }
    .buttonStyle(.plain)
    .disabled(item.isDisabled)
  }
}

private struct PopupKeyMonitor: NSViewRepresentable {
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onReturn: () -> Void
  let onEscape: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.startMonitoring()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.parent = self
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.stopMonitoring()
  }

  final class Coordinator {
    var parent: PopupKeyMonitor
    private var monitor: Any?

    init(_ parent: PopupKeyMonitor) {
      self.parent = parent
    }

    func startMonitoring() {
      guard monitor == nil else { return }

      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }
        guard NSApp.keyWindow is PopupWindow else { return event }

        switch event.keyCode {
        case 126:
          self.parent.onMoveUp()
          return nil
        case 125:
          self.parent.onMoveDown()
          return nil
        case 36:
          self.parent.onReturn()
          return nil
        case 53:
          self.parent.onEscape()
          return nil
        default:
          return event
        }
      }
    }

    func stopMonitoring() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
    }

    deinit {
      stopMonitoring()
    }
  }
}

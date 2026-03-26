import SwiftUI
import ApplicationServices
import Observation

private let logger = AppLogger.logger("PopupView")

@Observable
final class PopupViewModel {
  var isEditMode: Bool = false
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

      // Custom input with send button
      if !viewModel.isEditMode {
        TextField(
          "Describe your change...",
          text: $customText
        )
        .focused($isCustomInputFocused)
        .textFieldStyle(.plain)
        .appleStyleTextField(
          text: customText,
          isLoading: isCustomLoading,
          onSubmit: processCustomChange
        )
        .padding(.horizontal, 10)
      }

      if !appState.selectedText.isEmpty || !appState.selectedImages.isEmpty {
        Divider()
          .padding(.horizontal, 10)

        // Command buttons grid
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
      }

      if viewModel.isEditMode {
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
    .windowBackground(useGradient: useGradientTheme)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
    )
    .clipShape(.rect(cornerRadius: 12))
    .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
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
    }
    .onChange(of: viewModel.isEditMode) { _, isEditMode in
      if isEditMode {
        isCustomInputFocused = false
      } else {
        focusCustomInputIfNeeded()
      }
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
    guard !appState.selectedText.isEmpty else {
      processingCommandId = nil
      return
    }

    appState.isProcessing = true

    let provider = appState.getProvider(for: command)
    let systemPrompt = command.prompt
    let userText = appState.selectedText
    let images = appState.selectedImages

    if command.useResponseWindow {
      await MainActor.run {
        processingCommandId = nil
        presentResponseWindow(
          title: command.name,
          initialMessages: [],
          selectedText: userText,
          option: .proofread,
          provider: provider,
          systemPrompt: systemPrompt,
          userPrompt: userText,
          images: images
        )
      }
      return
    }

    closeAction()

    await MainActor.run {
      WindowManager.shared.showProcessingHUD(
        commandName: command.name,
        commandIcon: command.icon,
        onCancel: { [weak appState] in
          provider.cancel()
          appState?.isProcessing = false
        }
      )
    }

    do {
      let result = try await provider.processText(
        systemPrompt: systemPrompt,
        userPrompt: userText,
        images: images,
        streaming: false
      )

      await MainActor.run {
        WindowManager.shared.dismissProcessingHUD()

        if command.preserveFormatting {
          appState.replaceSelectedTextPreservingAttributes(with: result)
        } else {
          appState.replaceSelectedText(with: result)
        }

        processingCommandId = nil
      }
    } catch {
      logger.error("Error processing command: \(error.localizedDescription)")
      await MainActor.run {
        WindowManager.shared.dismissProcessingHUD()
        errorMessage = error.localizedDescription
        showingErrorAlert = true
        processingCommandId = nil
      }
    }

    await MainActor.run {
      appState.isProcessing = false
    }
  }

  @MainActor
  private func processCustomChange() {
    guard !customText.isEmpty else { return }
    isCustomLoading = true
    processCustomInstruction(customText)
  }

  @MainActor
  private func processCustomInstruction(_ instruction: String) {
    guard !instruction.isEmpty else { return }
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
        images: images
      ) {
        appState.isProcessing = false
      }
    }
  }
}

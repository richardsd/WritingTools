import SwiftUI
import KeyboardShortcuts
import Carbon.HIToolbox
import UniformTypeIdentifiers
import ImageIO

private let logger = AppLogger.logger("AppDelegate")

private struct PopupSelectionCaptureResult {
    let richText: NSAttributedString?
    let plainText: String
    let images: [Data]
}

private struct PopupSelectionContext {
    let previousApplication: NSRunningApplication?
    let selectedTextScreenBounds: NSRect?
    let accessibilitySelectedText: String
}

private enum PopupSelectionCaptureError: LocalizedError {
    case copyEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .copyEventCreationFailed:
            return "Failed to trigger copy for the current selection."
        }
    }
}

private final class PopupSelectionCaptureHandle {
    var isCancelled = false
    var task: Task<Void, Never>? {
        didSet {
            if isCancelled {
                task?.cancel()
            }
        }
    }

    func cancel() {
        isCancelled = true
        task?.cancel()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Static status item to prevent deallocation
    private static var sharedStatusItem: NSStatusItem?

    // Property to track service-triggered popups
    private var isServiceTriggered: Bool = false

    // Computed property to manage the menu bar status item
    var statusBarItem: NSStatusItem! {
        get {
            if AppDelegate.sharedStatusItem == nil {
                AppDelegate.sharedStatusItem =
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                configureStatusBarItem()
            }
            return AppDelegate.sharedStatusItem
        }
        set {
            AppDelegate.sharedStatusItem = newValue
        }
    }

    let appState = AppState.shared
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsHostingView: NSHostingView<SettingsView>?
    private var aboutHostingView: NSHostingView<AboutView>?

    // Pasteboard monitoring
    private var pasteboardObserver: NSObjectProtocol?
    @objc private func toggleHotkeys() {
        AppSettings.shared.hotkeysPaused.toggle()
        setupMenuBar()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self

        if CommandLine.arguments.contains("--reset") {
            Task { @MainActor [weak self] in
                self?.performRecoveryReset()
            }
            return
        }

        Task { @MainActor [weak self] in
            self?.setupMenuBar()

            if self?.statusBarItem == nil {
                self?.recreateStatusBarItem()
            }

            if !UserDefaults.standard.bool(forKey: "has_completed_onboarding") {
                self?.showOnboarding()
            }
        }

        // Register the main popup shortcut
        KeyboardShortcuts.onKeyUp(for: .showPopup) { [weak self] in
            if !AppSettings.shared.hotkeysPaused {
                self?.showPopup()
            } else {
                logger.info("Hotkeys are paused")
            }
        }

        // Set up command-specific shortcuts
        setupCommandShortcuts()

        // Register for command changes to update shortcuts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(setupCommandShortcuts),
            name: NSNotification.Name("CommandsChanged"),
            object: nil
        )
    }

    @objc private func setupCommandShortcuts() {
        for command in appState.commandManager.commands.filter({ !$0.hasShortcut }) {
            KeyboardShortcuts.reset(.commandShortcut(for: command.id))
        }

        for command in appState.commandManager.commands.filter({ $0.hasShortcut }) {
            KeyboardShortcuts.onKeyUp(for: .commandShortcut(for: command.id)) {
                [weak self] in
                guard let self = self, !AppSettings.shared.hotkeysPaused else {
                    return
                }
                self.executeCommandDirectly(command)
            }
        }
    }

    private func executeCommandDirectly(_ command: CommandModel) {
        appState.activeProvider.cancel()

        Task { @MainActor in
            // Check accessibility permissions first
            let hasAccessibility = AXIsProcessTrusted()
            if !hasAccessibility {
                logger.error("Accessibility permissions not granted! Cannot simulate Cmd+C. Please grant accessibility permissions in System Settings.")
                
                // Show alert to user
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Writing Tools needs accessibility permission to capture selected text. Please enable it in System Settings > Privacy & Security > Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                return
            }
            
            // Store the previous app BEFORE any operations
            let previousApp = NSWorkspace.shared.frontmostApplication

            // Capture selection bounds before we touch the clipboard
            self.appState.selectedTextScreenBounds = self.selectedTextScreenBounds()

            let pb = NSPasteboard.general
            let oldChangeCount = pb.changeCount

            // IMPORTANT: Capture the ENTIRE clipboard state before copying
            let clipboardSnapshot = pb.createSnapshot()
            logger.debug("Captured clipboard snapshot with \(clipboardSnapshot.itemCount) items")

            // Create and post Cmd+C event
            let src = CGEventSource(stateID: .hidSystemState)
            let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            kd?.flags = .maskCommand
            ku?.flags = .maskCommand

            kd?.post(tap: .cgSessionEventTap)
            ku?.post(tap: .cgSessionEventTap)

            // Give the system a tiny moment to process the copy event
            try? await Task.sleep(for: .milliseconds(50)) // 50ms - increased for reliability

            // Wait for the pasteboard to actually change
            let pasteboardChanged =
                (try? await waitForPasteboardChange(pb, initialChangeCount: oldChangeCount))
                ?? false

            // Only proceed if the pasteboard actually changed (new content was copied)
            guard pasteboardChanged, pb.changeCount > oldChangeCount else {
                logger.warning("No new content was copied for command: \(command.name) - change count didn't increase (old: \(oldChangeCount), new: \(pb.changeCount))")
                return
            }

            // Read the newly copied content IMMEDIATELY after detecting the change
            var foundImages: [Data] = []

            let classes = [NSURL.self]
            let imageTypeIdentifiers = [
                UTType.image,
                UTType.png,
                UTType.jpeg,
                UTType.tiff,
                UTType.gif,
            ].map(\.identifier)

            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: imageTypeIdentifiers,
            ]

            if let urls = pb.readObjects(forClasses: classes, options: options) as? [URL] {
                let loadedImages = await loadImageData(from: urls)
                if !loadedImages.isEmpty {
                    foundImages.append(contentsOf: loadedImages)
                }
            }

            if foundImages.isEmpty {
                let supportedImageTypes: [NSPasteboard.PasteboardType] = [
                    NSPasteboard.PasteboardType(UTType.png.identifier),
                    NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                    NSPasteboard.PasteboardType(UTType.tiff.identifier),
                    NSPasteboard.PasteboardType(UTType.gif.identifier),
                    NSPasteboard.PasteboardType(UTType.image.identifier),
                ]

                for type in supportedImageTypes {
                    if let data = pb.data(forType: type) {
                        foundImages.append(data)
                        logger.debug("Found direct image data of type: \(type.rawValue)")
                        break
                    }
                }
            }

            // Read rich text BEFORE clearing
            let rich = pb.readAttributedSelection()
            let selectedText = rich?.string ?? pb.string(forType: .string) ?? ""

            guard !selectedText.isEmpty else {
                logger.info("No text selected for command: \(command.name) - pasteboard contained no text")
                // Restore original clipboard using snapshot
                pb.restore(snapshot: clipboardSnapshot)
                return
            }

            logger.debug("Successfully captured text for command \(command.name) (length: \(selectedText.count) characters)")

            // Store data in appState BEFORE restoring clipboard
            self.appState.selectedImages = foundImages
            self.appState.selectedAttributedText = rich
            self.appState.selectedText = selectedText

            // Set previous app AFTER we've successfully copied
            if let previousApp = previousApp {
                self.appState.previousApplication = previousApp
            }

            // NOW restore original clipboard using the snapshot
            pb.restore(snapshot: clipboardSnapshot)
            logger.debug("Restored original clipboard after capturing selection")

            // Process the command with the captured data
            await self.processCommandWithUI(command)
        }
    }

    private func processCommandWithUI(_ command: CommandModel) async {
        if appState.isProcessing {
            return
        }

        appState.isProcessing = true

        // Get the appropriate provider for this command (respects per-command overrides)
        let provider = appState.getProvider(for: command)

        // Show processing HUD for visual feedback
        WindowManager.shared.showProcessingHUD(
            commandName: command.name,
            commandIcon: command.icon,
            onCancel: { [weak self] in
                provider.cancel()
                self?.appState.isProcessing = false
            }
        )

        defer {
            appState.isProcessing = false
            WindowManager.shared.dismissProcessingHUD()
        }

        do {
            var result = try await provider.processText(
                systemPrompt: AppProfileService.shared.enrichSystemPrompt(command.prompt, for: appState.previousApplication),
                userPrompt: appState.selectedText,
                images: appState.selectedImages,
                streaming: false
            )

            // Preserve trailing newlines from the original selection
            // This is important for triple-click selections which include the trailing newline
            let originalText = appState.selectedText
            if originalText.hasSuffix("\n") && !result.hasSuffix("\n") {
                result += "\n"
                logger.debug("Added trailing newline to match input")
            }

            // Record to history
            let capturedApp = appState.previousApplication
            let matchedProfile = capturedApp.map {
                AppProfileService.shared.resolveProfile(for: ActiveAppContext(from: $0))
            } ?? nil
            await MainActor.run {
                HistoryManager.shared.record(
                    commandName: command.name,
                    commandId: command.id,
                    inputText: originalText,
                    outputText: result,
                    modelName: provider.modelDisplayName.isEmpty ? nil : provider.modelDisplayName,
                    sourceApp: capturedApp,
                    matchedProfileName: matchedProfile?.name
                )
            }

            await MainActor.run {
                if command.useResponseWindow {
                    let window = ResponseWindow(
                        title: command.name,
                        content: result,
                        selectedText: appState.selectedText,
                        option: nil,
                        provider: provider
                    )

                    NSApp.activate(ignoringOtherApps: true)
                    WindowManager.shared.addResponseWindow(window)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                } else {
                    if command.preserveFormatting, appState.selectedAttributedText != nil {
                        appState.replaceSelectedTextPreservingAttributes(with: result)
                    } else {
                        appState.replaceSelectedText(with: result)
                    }
                }
            }
        } catch {
            logger.error("Error processing command \(command.name): \(error.localizedDescription)")

            // Show error alert
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Command Error"
                alert.informativeText = "Failed to process '\(command.name)': \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // MARK: - Fixed: Clipboard Monitoring (Replace polling)

    private func waitForPasteboardChange(
        _ pb: NSPasteboard,
        initialChangeCount: Int
    ) async throws -> Bool {
        let startTime = Date()
        let timeout: TimeInterval = 2.0 // Increased timeout
        let pollInterval: Duration = .milliseconds(5)

        while pb.changeCount == initialChangeCount && Date().timeIntervalSince(startTime) < timeout {
            try Task.checkCancellation()
            try await Task.sleep(for: pollInterval)
        }

        try Task.checkCancellation()

        if pb.changeCount == initialChangeCount {
            logger.warning("Clipboard update timeout after \(timeout)s - no change detected")
            return false
        } else {
            let elapsed = Date().timeIntervalSince(startTime)
            let formattedElapsed = elapsed.formatted(.number.precision(.fractionLength(3)))
            logger.debug("Clipboard changed after \(formattedElapsed)s")
            return true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = pasteboardObserver {
            NotificationCenter.default.removeObserver(observer)
            pasteboardObserver = nil
        }
        WindowManager.shared.cleanupWindows()
    }

    private func recreateStatusBarItem() {
        AppDelegate.sharedStatusItem = nil
        _ = self.statusBarItem
    }

    private func configureStatusBarItem() {
        guard let button = statusBarItem?.button else { return }
        button.image = NSImage(
            systemSymbolName: "pencil.circle",
            accessibilityDescription: "Writing Tools"
        )
    }

    private func setupMenuBar() {
        guard let statusBarItem = self.statusBarItem else {
            logger.error("Failed to create status bar item")
            return
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        )
        menu.addItem(
            NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "i")
        )
        let hotkeyTitle = AppSettings.shared.hotkeysPaused ? "Resume" : "Pause"
        menu.addItem(
            NSMenuItem(title: hotkeyTitle, action: #selector(toggleHotkeys), keyEquivalent: "p")
        )
        menu.addItem(
            NSMenuItem(title: "Reset App", action: #selector(resetApp), keyEquivalent: "r")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        statusBarItem.menu = menu
    }

    @objc private func resetApp() {
        WindowManager.shared.cleanupWindows()

        recreateStatusBarItem()
        setupMenuBar()

        let alert = NSAlert()
        alert.messageText = "App Reset Complete"
        alert.informativeText =
            "The app has been reset. If you're still experiencing issues, try restarting the app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func performRecoveryReset() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)

        WindowManager.shared.cleanupWindows()

        recreateStatusBarItem()
        setupMenuBar()

        let alert = NSAlert()
        alert.messageText = "Recovery Complete"
        alert.informativeText =
            "The app has been reset to its default state."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showSettings() {
        settingsWindow?.close()
        closePopupWindow()
        settingsWindow = nil
        settingsHostingView = nil

        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow?.isReleasedWhenClosed = false
        settingsWindow?.minSize = NSSize(width: 540, height: 460)

        let settingsView =
            SettingsView(appState: appState, showOnlyApiSetup: false)
        settingsHostingView = NSHostingView(rootView: settingsView)
        settingsWindow?.contentView = settingsHostingView
        settingsWindow?.delegate = self

        if let window = settingsWindow {
            window.title = "Settings"
            window.level = .floating
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    @objc private func showAbout() {
        aboutWindow?.close()
        aboutWindow = nil
        aboutHostingView = nil

        aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        aboutWindow?.isReleasedWhenClosed = false

        let aboutView = AboutView()
        aboutHostingView = NSHostingView(rootView: aboutView)
        aboutWindow?.contentView = aboutHostingView
        aboutWindow?.delegate = self

        if let window = aboutWindow {
            window.title = "About Writing Tools"
            window.level = .floating
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Writing Tools"
        window.isReleasedWhenClosed = false

        window.center()

        let onboardingView = OnboardingView(appState: appState)
        let hostingView = NSHostingView(rootView: onboardingView)
        window.contentView = hostingView
        window.level = .floating

        WindowManager.shared.setOnboardingWindow(
            window,
            hostingView: hostingView
        )
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func showPopup() {
        appState.activeProvider.cancel()

        let previousApplication = NSWorkspace.shared.frontmostApplication
        let selectionContext = PopupSelectionContext(
            previousApplication: previousApplication,
            selectedTextScreenBounds: self.selectedTextScreenBounds(),
            accessibilitySelectedText: self.selectedTextViaAccessibility() ?? ""
        )
        self.appState.previousApplication = previousApplication
        self.appState.selectedTextScreenBounds = selectionContext.selectedTextScreenBounds

        self.closePopupWindow()

        let window = PopupWindow(appState: self.appState)
        window.positionNearMouse()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        startPopupSelectionCapture(using: selectionContext)
    }

    private func closePopupWindow() {
        WindowManager.shared.dismissPopup()
    }

    private func startPopupSelectionCapture(using context: PopupSelectionContext) {
        let requestID = UUID()
        let captureHandle = PopupSelectionCaptureHandle()
        appState.beginPopupSelectionCapture(requestID: requestID)
        appState.setPopupSelectionCanceller({
            captureHandle.cancel()
        }, for: requestID)

        captureHandle.task = Task { @MainActor [weak self] in
            guard let self else { return }

            // Yield once so AppKit can present the popup before selection capture starts.
            await Task.yield()

            do {
                let result = try await self.capturePopupSelection(using: context)
                try Task.checkCancellation()

                self.appState.applyPopupSelectionCaptureResult(
                    requestID: requestID,
                    richText: result.richText,
                    plainText: result.plainText,
                    images: result.images
                )
            } catch is CancellationError {
                logger.debug("Popup selection capture cancelled")
            } catch {
                logger.error("Popup selection capture failed: \(error.localizedDescription)")
                self.appState.failPopupSelectionCapture(
                    requestID: requestID,
                    message: error.localizedDescription
                )
            }

            if self.appState.popupCaptureRequestID == requestID {
                WindowManager.shared.reactivatePopupIfVisible()
            }
        }
    }

    private func capturePopupSelection(
        using context: PopupSelectionContext
    ) async throws -> PopupSelectionCaptureResult {
        let pb = NSPasteboard.general
        let oldChangeCount = pb.changeCount
        let clipboardSnapshot = pb.createSnapshot()
        logger.debug(
            "Captured clipboard snapshot with \(clipboardSnapshot.itemCount) items for popup selection"
        )

        defer {
            pb.restore(snapshot: clipboardSnapshot)
            logger.debug("Restored original clipboard after capturing popup selection")
        }

        guard
            let sourceApplication = context.previousApplication,
            sourceApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            logger.warning(
                "No valid source application for popup capture; using accessibility fallback"
            )
            return popupFallbackSelectionResult(using: context)
        }

        sourceApplication.activate()
        let sourceApplicationFocused = try await waitForApplicationToBecomeFrontmost(
            sourceApplication
        )

        guard sourceApplicationFocused else {
            logger.warning(
                "Source application did not become frontmost for popup capture; using accessibility fallback"
            )
            return popupFallbackSelectionResult(using: context)
        }

        guard let src = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: src,
                virtualKey: 0x08,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: src,
                virtualKey: 0x08,
                keyDown: false
              )
        else {
            throw PopupSelectionCaptureError.copyEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        try await Task.sleep(for: .milliseconds(50))

        let pasteboardChanged = try await waitForPasteboardChange(
            pb,
            initialChangeCount: oldChangeCount
        )

        guard pasteboardChanged, pb.changeCount > oldChangeCount else {
            logger.warning("Pasteboard did not change after popup copy; using accessibility fallback if available")
            return popupFallbackSelectionResult(using: context)
        }

        var foundImages: [Data] = []

        let classes = [NSURL.self]
        let imageTypeIdentifiers = [
            UTType.image,
            UTType.png,
            UTType.jpeg,
            UTType.tiff,
            UTType.gif,
        ].map(\.identifier)

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: imageTypeIdentifiers,
        ]

        if let urls = pb.readObjects(forClasses: classes, options: options) as? [URL] {
            let loadedImages = await loadImageData(from: urls)
            if !loadedImages.isEmpty {
                foundImages.append(contentsOf: loadedImages)
            }
        }

        if foundImages.isEmpty {
            let supportedImageTypes: [NSPasteboard.PasteboardType] = [
                NSPasteboard.PasteboardType(UTType.png.identifier),
                NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                NSPasteboard.PasteboardType(UTType.tiff.identifier),
                NSPasteboard.PasteboardType(UTType.gif.identifier),
                NSPasteboard.PasteboardType(UTType.image.identifier),
            ]

            for type in supportedImageTypes {
                if let data = pb.data(forType: type) {
                    foundImages.append(data)
                    logger.debug("Found direct image data of type: \(type.rawValue)")
                    break
                }
            }
        }

        let richText = pb.readAttributedSelection()
        let plainText = richText?.string ?? pb.string(forType: .string) ?? ""

        guard !plainText.isEmpty || !foundImages.isEmpty else {
            logger.warning(
                "Pasteboard capture returned no text or images; using accessibility fallback if available"
            )
            return popupFallbackSelectionResult(using: context)
        }

        return PopupSelectionCaptureResult(
            richText: richText,
            plainText: plainText,
            images: foundImages
        )
    }

    // MARK: - Accessibility: selected text screen position

    /// Returns the screen rect (AppKit coords, bottom-left origin) of the currently
    /// selected text in the frontmost app via the Accessibility API.
    /// Returns nil if unavailable (e.g. app doesn't support AX text attributes).
    private func selectedTextScreenBounds() -> NSRect? {
        guard let focused = focusedAccessibilityElement() else { return nil }

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success, let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        ) == .success, let boundsRef else { return nil }

        var quartzRect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &quartzRect),
              !quartzRect.isEmpty,
              let mainScreen = NSScreen.main
        else { return nil }

        // Quartz uses top-left origin; AppKit uses bottom-left — flip Y.
        let flippedY = mainScreen.frame.height - quartzRect.origin.y - quartzRect.height
        return NSRect(x: quartzRect.origin.x, y: flippedY,
                      width: quartzRect.width, height: quartzRect.height)
    }

    private func focusedAccessibilityElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
        let focusedRef
        else {
            return nil
        }

        guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(focusedRef, to: AXUIElement.self)
    }

    private func selectedTextViaAccessibility() -> String? {
        guard let focused = focusedAccessibilityElement() else { return nil }

        var selectedTextRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        ) == .success,
        let selectedTextRef
        else {
            return nil
        }

        if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }

        if let selectedText = selectedTextRef as? NSString, selectedText.length > 0 {
            return selectedText as String
        }

        return nil
    }

    private func popupFallbackSelectionResult(
        using context: PopupSelectionContext
    ) -> PopupSelectionCaptureResult {
        PopupSelectionCaptureResult(
            richText: nil,
            plainText: context.accessibilitySelectedText,
            images: []
        )
    }

    private func waitForApplicationToBecomeFrontmost(
        _ application: NSRunningApplication
    ) async throws -> Bool {
        let startTime = Date()
        let timeout: TimeInterval = 0.5

        while Date().timeIntervalSince(startTime) < timeout {
            try Task.checkCancellation()

            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier
            {
                return true
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return NSWorkspace.shared.frontmostApplication?.processIdentifier
            == application.processIdentifier
    }

    func windowWillClose(_ notification: Notification) {
        guard !isServiceTriggered else { return }

        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor [weak self] in
            if window == self?.settingsWindow {
                self?.settingsHostingView = nil
                self?.settingsWindow = nil
            } else if window == self?.aboutWindow {
                self?.aboutHostingView = nil
                self?.aboutWindow = nil
            }
        }
    }
}

// MARK: - Image Loading

private extension AppDelegate {
    func loadImageData(from urls: [URL]) async -> [Data] {
        await Task.detached(priority: .userInitiated) {
            var images: [Data] = []
            images.reserveCapacity(urls.count)

            for url in urls {
                if let imageData = try? Data(contentsOf: url),
                   await Self.isValidImageData(imageData) {
                    images.append(imageData)
                    logger.debug("Loaded image data from file: \(url.lastPathComponent)")
                }
            }
            return images
        }.value
    }

    static func isValidImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }
}

extension AppDelegate {
    override func awakeFromNib() {
        super.awakeFromNib()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
}

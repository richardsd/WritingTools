import SwiftUI

struct ProcessingHUDView: View {
    let commandName: String
    let commandIcon: String
    let onCancel: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Image(systemName: commandIcon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text(commandName + "…")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 240)
        .background {
            if #available(macOS 26, *) {
                Color.clear
                    .glassEffect(.regular, in: .capsule)
            } else {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(.capsule)
            }
        }
        .overlay(
            Capsule()
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing \(commandName)")
    }
}

// MARK: - Visual Effect (pre-macOS 26)

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - HUD Window

class ProcessingHUDWindow: NSPanel {
    private var retainedHostingView: NSHostingView<ProcessingHUDView>?
    private var autoDismissTask: Task<Void, Never>?

    init(commandName: String, commandIcon: String, anchorRect: NSRect?, onCancel: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isReleasedWhenClosed = false
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.transient, .ignoresCycle]
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow

        let hudView = ProcessingHUDView(
            commandName: commandName,
            commandIcon: commandIcon,
            onCancel: onCancel
        )

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        contentView = hostingView
        retainedHostingView = hostingView

        positionNear(anchorRect: anchorRect)
        scheduleAutoDismiss()
    }

    /// Positions the HUD just above the selected text rect when available,
    /// falling back to above the mouse cursor if AX data was unavailable.
    private func positionNear(anchorRect: NSRect?) {
        let padding: CGFloat = 10
        var windowFrame = frame

        if let anchor = anchorRect {
            let referenceX = anchor.midX
            let topOfSelection = anchor.maxY

            guard let screen = NSScreen.screens.first(where: {
                $0.frame.contains(NSPoint(x: referenceX, y: topOfSelection))
            }) ?? NSScreen.main else { return }

            // Centre horizontally over the selection, sit above its top edge
            windowFrame.origin.x = referenceX - (windowFrame.width / 2)
            windowFrame.origin.y = topOfSelection + padding

            windowFrame.origin.x = max(
                screen.visibleFrame.minX + padding,
                min(windowFrame.origin.x, screen.visibleFrame.maxX - windowFrame.width - padding)
            )

            // If no room above the selection, flip below it
            if windowFrame.maxY > screen.visibleFrame.maxY {
                windowFrame.origin.y = anchor.minY - windowFrame.height - padding
            }
        } else {
            // Fallback: anchor to the mouse cursor
            let mouseLocation = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: {
                $0.frame.contains(mouseLocation)
            }) ?? NSScreen.main else { return }

            windowFrame.origin.x = mouseLocation.x - (windowFrame.width / 2)
            windowFrame.origin.y = mouseLocation.y + padding

            windowFrame.origin.x = max(
                screen.visibleFrame.minX + padding,
                min(windowFrame.origin.x, screen.visibleFrame.maxX - windowFrame.width - padding)
            )

            if windowFrame.maxY > screen.visibleFrame.maxY {
                windowFrame.origin.y = mouseLocation.y - windowFrame.height - padding
            }
        }

        setFrame(windowFrame, display: true)
    }

    private func scheduleAutoDismiss() {
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.dismiss()
        }
    }

    func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
        })
    }

    override func close() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        retainedHostingView?.removeFromSuperview()
        retainedHostingView = nil
        super.close()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

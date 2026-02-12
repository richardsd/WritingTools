//
//  OnboardingPermissionsStep.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import SwiftUI
import ApplicationServices
import CoreGraphics

struct OnboardingPermissionsStep: View {
  @Binding var isAccessibilityGranted: Bool
  @Binding var isScreenRecordingGranted: Bool
  @Binding var wantsScreenshotOCR: Bool

  var onRefresh: () -> Void
  var onOpenPrivacyPane: (String) -> Void
  
  // Timer to auto-refresh permissions
  @State private var refreshTimer: Timer?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Required")
        .font(.headline)

      PermissionRow(
        icon: "figure.wave.circle.fill",
        title: "Accessibility",
        status: isAccessibilityGranted ? .granted : .missing,
        explanation: """
          Required to simulate ⌘C/⌘V for copying your selection and \
          pasting results back into the original app. WritingTools does \
          not monitor your keystrokes.
          """,
        primaryActionTitle: isAccessibilityGranted ? "Granted" : "Request Access",
        secondaryActionTitle: "Open Settings",
        onPrimary: {
          OnboardingPermissionsHelper.requestAccessibility()
          Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            onRefresh()
          }
        },
        onSecondary: {
          onOpenPrivacyPane("Privacy_Accessibility")
        }
      )

      Divider().padding(.vertical, 4)

      Toggle(isOn: $wantsScreenshotOCR) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Enable Screenshot OCR (Optional)")
          Text(
            "If enabled, you can run OCR on screenshot snippets. This requires Screen Recording permission."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .toggleStyle(.switch)

      if wantsScreenshotOCR {
        PermissionRow(
          icon: "rectangle.dashed.and.paperclip",
          title: "Screen Recording (Optional)",
          status: isScreenRecordingGranted ? .granted : .missing,
          explanation: """
            Required only if you use Screenshot OCR. macOS will show a \
            system prompt. You may need to restart the app for changes to \
            take effect. WritingTools does not record or store your \
            screen; it only uses this to capture the area you explicitly \
            select.
            """,
          primaryActionTitle: isScreenRecordingGranted ? "Granted" : "Request Access",
          secondaryActionTitle: "Open Settings",
          onPrimary: {
            OnboardingPermissionsHelper.requestScreenRecording { granted in
              isScreenRecordingGranted = granted
            }
          },
          onSecondary: {
            onOpenPrivacyPane("Privacy_ScreenCapture")
          }
        )
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Text("Notes")
            .font(.headline)
          VStack(alignment: .leading, spacing: 6) {
            Label(
              "You can revoke any permission later in System Settings.",
              systemImage: "info.circle"
            )
            Label(
              "Input Monitoring is NOT required. WritingTools only posts copy/paste commands.",
              systemImage: "checkmark.circle"
            )
          }
          .foregroundStyle(.secondary)
        }
        .padding(8)
      }

      HStack {
        Button("Refresh Status") {
          onRefresh()
        }
        .buttonStyle(.bordered)
        .help("Recheck current permission statuses.")

        Spacer()

        Button("Open Privacy & Security") {
          NSWorkspace.shared.open(
            URL(
              string:
                "x-apple.systempreferences:com.apple.preference.security"
            )!
          )
        }
        .buttonStyle(.link)
        .help("Open System Settings to manage permissions.")
      }
      .padding(.top, 4)
    }
    .onAppear {
      // Start auto-refresh timer when view appears
      startAutoRefresh()
    }
    .onDisappear {
      // Stop timer when view disappears
      stopAutoRefresh()
    }
  }
  
  private func startAutoRefresh() {
    // Check permissions every second while on this screen
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      onRefresh()
    }
  }
  
  private func stopAutoRefresh() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }
}

// MARK: - Permission Helpers

struct OnboardingPermissionsHelper {
  static func requestAccessibility() {
    // Show macOS system prompt - it includes a button to open System Settings
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as CFString
    let options: CFDictionary = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    
    // Note: We don't automatically open System Settings anymore.
    // The system prompt already has an "Open System Settings" button.
    // Users can also click the "Open Settings" button if they dismiss the prompt.
  }

  static func checkScreenRecording() -> Bool {
    if #available(macOS 10.15, *) {
      return CGPreflightScreenCaptureAccess()
    } else {
      return true
    }
  }

  static func requestScreenRecording(completion: @escaping (Bool) -> Void) {
    if #available(macOS 10.15, *) {
      Task.detached(priority: .userInitiated) {
        let granted = CGRequestScreenCaptureAccess()
        await MainActor.run {
          completion(granted)
        }
      }
    } else {
      completion(true)
    }
  }
}

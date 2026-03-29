import SwiftUI

struct AboutView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var updateChecker = UpdateChecker.shared

    private var appVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, let buildVersion, shortVersion != buildVersion {
            return "\(shortVersion) (\(buildVersion))"
        }

        return shortVersion ?? buildVersion ?? "Unknown"
    }

    private var updateButtonTitle: String {
        switch updateChecker.status {
        case .updateAvailable:
            return "Download Update"
        default:
            return "Check for Updates"
        }
    }

    private var isCheckingForUpdates: Bool {
        if case .checking = updateChecker.status {
            return true
        }
        return false
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            VStack(spacing: 6) {
                Text("About Writing Tools")
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("Writing Tools is a free, lightweight utility that enhances your writing with AI.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .padding(.horizontal)
            }
            .padding(.top, 8)

            Divider()

            // Authors
            GroupBox("Creators") {
                VStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Text("Created with care by Jesai, a high school student.")
                            .bold()
                        HStack(spacing: 12) {
                            Link("Email Jesai", destination: URL(string: "mailto:jesaitarun@gmail.com")!)
                            Link("Bliss AI on Google Play", destination: URL(string: "https://play.google.com/store/apps/details?id=com.jesai.blissai")!)
                        }
                    }

                    Divider()

                    VStack(spacing: 2) {
                        Text("macOS version by Arya Mirsepasi")
                            .bold()
                        HStack(spacing: 12) {
                            Link("Email Arya", destination: URL(string: "mailto:developer@aryamirsepasi.com")!)
                            Link("ProseKey AI (iOS port)", destination: URL(string: "https://apps.apple.com/us/app/prosekey-ai/id6741180175")!)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Version and updates
            GroupBox("Version & Updates") {
                VStack(spacing: 8) {
                    Text("Version: \(appVersion)")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    updateStatusView

                    HStack(spacing: 12) {
                        Button(action: {
                            if case .updateAvailable = updateChecker.status {
                                updateChecker.openReleasesPage()
                            } else {
                                Task { await updateChecker.checkForUpdates() }
                            }
                        }) {
                            Text(updateButtonTitle)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCheckingForUpdates)

                        Link("View Releases", destination: URL(string: "https://github.com/theJayTea/WritingTools/releases")!)
                            .buttonStyle(.link)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()
        }
        .padding()
        .frame(width: 420, height: 420)
        .frame(minWidth: 400, minHeight: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowBackground(useGradient: settings.useGradientTheme)
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateChecker.status {
        case .idle:
            Text("Check for updates to see whether a newer version is available.")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .checking:
            ProgressView("Checking for updates...")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let error):
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .updateAvailable(let latestVersion):
            Text("Version \(latestVersion) is available!")
                .foregroundStyle(.green)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .upToDate(let currentVersion):
            Text("The latest version is already installed (\(currentVersion)).")
                .foregroundStyle(.green)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

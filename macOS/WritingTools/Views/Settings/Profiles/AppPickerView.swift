import SwiftUI
import AppKit

// MARK: - Model

/// Represents an installed application available for selection in the picker.
struct AppPickerItem: Identifiable {
    let id: String  // bundle identifier, used as stable identity
    let name: String
    let bundleIdentifier: String
    let icon: NSImage
}

// MARK: - Main View

/// A modal sheet for selecting installed applications to add as profile matchers.
/// Multi-select; pre-selects apps whose bundle ID already exists in the profile.
struct AppPickerView: View {
    @Binding var profile: AppProfile
    @Environment(\.dismiss) private var dismiss

    @State private var allApps: [AppPickerItem] = []
    @State private var selectedBundleIds: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 12)]

    private var filteredApps: [AppPickerItem] {
        guard !searchText.isEmpty else { return allApps }
        return allApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Title bar ────────────────────────────────────────
            HStack {
                Text("Select Applications")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    applySelection()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // ── Search bar ───────────────────────────────────────
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search applications...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // ── Grid ─────────────────────────────────────────────
            Group {
                if isLoading {
                    ProgressView("Loading applications...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredApps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "No applications found" : "No results for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredApps) { app in
                                AppPickerItemCell(
                                    app: app,
                                    isSelected: selectedBundleIds.contains(app.bundleIdentifier)
                                ) {
                                    toggleSelection(app)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 612, height: 460)
        .task {
            await loadApps()
        }
    }

    // MARK: - Selection

    private func toggleSelection(_ app: AppPickerItem) {
        if selectedBundleIds.contains(app.bundleIdentifier) {
            selectedBundleIds.remove(app.bundleIdentifier)
        } else {
            selectedBundleIds.insert(app.bundleIdentifier)
        }
    }

    /// Adds matchers for newly-selected apps and removes matchers for deselected apps.
    /// Manual matchers without a bundle ID are left completely untouched.
    private func applySelection() {
        // Remove matchers for bundle IDs that were deselected
        // (only affects matchers that have a bundleIdentifierEquals set)
        let previousBundleIds = Set(
            profile.matchers
                .map(\.bundleIdentifierEquals)
                .filter { !$0.isEmpty }
        )

        let toRemove = previousBundleIds.subtracting(selectedBundleIds)
        profile.matchers.removeAll {
            !$0.bundleIdentifierEquals.isEmpty && toRemove.contains($0.bundleIdentifierEquals)
        }

        // Add matchers for newly-selected apps
        for bundleId in selectedBundleIds {
            let alreadyPresent = profile.matchers.contains {
                $0.bundleIdentifierEquals.lowercased() == bundleId.lowercased()
            }
            guard !alreadyPresent else { continue }

            let name = allApps.first(where: { $0.bundleIdentifier == bundleId })?.name ?? ""
            profile.matchers.append(AppMatcher(
                bundleIdentifierEquals: bundleId,
                appNameContains: name
            ))
        }
    }

    // MARK: - App Loading

    private func loadApps() async {
        let apps = await Task.detached(priority: .userInitiated) {
            Self.scanInstalledApps()
        }.value

        // Pre-select bundle IDs already present in the profile
        let existingBundleIds = Set(
            profile.matchers
                .map(\.bundleIdentifierEquals)
                .filter { !$0.isEmpty }
        )

        await MainActor.run {
            allApps = apps
            selectedBundleIds = existingBundleIds
            isLoading = false
        }
    }

    private static func scanInstalledApps() -> [AppPickerItem] {
        let searchDirs: [String] = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        ]

        var seen = Set<String>()
        var items: [AppPickerItem] = []

        for dir in searchDirs {
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "app" else { continue }

                let plistURL = url.appendingPathComponent("Contents/Info.plist")
                guard
                    let data = try? Data(contentsOf: plistURL),
                    let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                    let bundleId = plist["CFBundleIdentifier"] as? String,
                    !seen.contains(bundleId)
                else { continue }

                seen.insert(bundleId)

                let displayName: String = {
                    if let dn = plist["CFBundleDisplayName"] as? String, !dn.isEmpty { return dn }
                    if let bn = plist["CFBundleName"] as? String, !bn.isEmpty { return bn }
                    return url.deletingPathExtension().lastPathComponent
                }()

                let icon = NSWorkspace.shared.icon(forFile: url.path)

                items.append(AppPickerItem(
                    id: bundleId,
                    name: displayName,
                    bundleIdentifier: bundleId,
                    icon: icon
                ))
            }
        }

        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Cell

private struct AppPickerItemCell: View {
    let app: AppPickerItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 44, height: 44)

                    Text(app.name)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                }
                .frame(width: 90, height: 84)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )

                // Checkmark badge
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

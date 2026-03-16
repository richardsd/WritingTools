import SwiftUI
import AppKit

/// A full-width split-view pane for managing App-Aware Prompt Profiles.
struct AppProfilesSettingsPane<SaveButton: View>: View {
    let saveButton: SaveButton

    @State private var profileService = AppProfileService.shared
    @State private var selectedProfileId: UUID?

    // Derived binding into profileService.profiles for the selected profile
    private var selectedProfileBinding: Binding<AppProfile>? {
        guard let id = selectedProfileId,
              let idx = profileService.profiles.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return Binding(
            get: { profileService.profiles[idx] },
            set: { profileService.profiles[idx] = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // MARK: Left — Profile List
                VStack(spacing: 0) {
                    List(selection: $selectedProfileId) {
                        ForEach(profileService.profiles) { profile in
                            ProfileRowView(profile: profile)
                                .tag(profile.id)
                        }
                        .onMove(perform: profileService.moveProfiles)
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 200, maxWidth: 240)
                    .overlay {
                        if profileService.profiles.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.rectangle.stack")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No profiles yet")
                                    .foregroundStyle(.secondary)
                                Text("Click + to add one")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Bottom toolbar
                    HStack(spacing: 0) {
                        Button {
                            let fresh = AppProfile(name: "New Profile")
                            profileService.addProfile(fresh)
                            selectedProfileId = fresh.id
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 28, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("Add profile")

                        Divider()
                            .frame(height: 20)

                        Button {
                            deleteSelected()
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 28, height: 26)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedProfileId == nil)
                        .help("Delete selected profile")

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 32)
                    .background(.bar)
                }
                .frame(maxWidth: 240)

                Divider()

                // MARK: Right — Editor or Placeholder
                Group {
                    if let binding = selectedProfileBinding {
                        AppProfileEditorView(profile: binding)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle.stack")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("Select a profile to edit")
                                .foregroundStyle(.secondary)
                            Text("Or click + to create a new one")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider()

            // MARK: Debug Footer
            HStack {
                debugFooterContent
                Spacer()
                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Debug Footer

    @ViewBuilder
    private var debugFooterContent: some View {
        if let app = AppState.shared.previousApplication {
            let ctx = ActiveAppContext(from: app)
            let matched = AppProfileService.shared.resolveProfile(for: ctx)
            HStack(spacing: 4) {
                Image(systemName: "app.badge")
                    .foregroundStyle(.secondary)
                Text(ctx.appName)
                    .fontWeight(.medium)
                if let bid = ctx.bundleIdentifier {
                    Text("(\(bid))")
                        .foregroundStyle(.secondary)
                }
                Text("→")
                    .foregroundStyle(.secondary)
                Text(matched?.name ?? "Default fallback")
                    .foregroundStyle(matched != nil ? Color.accentColor : Color.secondary)
            }
            .font(.caption)
        } else {
            Text("No app detected yet — trigger Writing Tools once to populate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func deleteSelected() {
        guard let id = selectedProfileId,
              let profile = profileService.profiles.first(where: { $0.id == id }) else { return }

        let idx = profileService.profiles.firstIndex(where: { $0.id == id })
        profileService.deleteProfile(profile)

        // Select adjacent profile after deletion
        if !profileService.profiles.isEmpty {
            let newIdx = min((idx ?? 0), profileService.profiles.count - 1)
            selectedProfileId = profileService.profiles[newIdx].id
        } else {
            selectedProfileId = nil
        }
    }
}

// MARK: - Profile Row

private struct ProfileRowView: View {
    let profile: AppProfile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: profileIcon(for: profile.formattingPreset))
                .foregroundStyle(profile.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill((profile.isEnabled ? Color.accentColor : Color.secondary).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 13))
                    .foregroundStyle(profile.isEnabled ? .primary : .secondary)
                Text(profile.formattingPreset.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !profile.isEnabled {
                Text("Off")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func profileIcon(for preset: FormattingPreset) -> String {
        switch preset {
        case .plainText:     return "text.alignleft"
        case .markdown:      return "textformat"
        case .emailFriendly: return "envelope"
        case .codeFriendly:  return "chevron.left.forwardslash.chevron.right"
        }
    }
}

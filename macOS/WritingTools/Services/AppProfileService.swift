import Foundation
import Observation
import AppKit

/// Manages app-aware prompt profiles and resolves the correct profile at command execution time.
@Observable
@MainActor
final class AppProfileService {

    static let shared = AppProfileService()

    // MARK: - State

    var profiles: [AppProfile] = [] {
        didSet { saveProfiles() }
    }

    private let saveKey = "app_profiles"
    private let hasInitializedKey = "has_initialized_app_profiles"

    // MARK: - Init

    private init() {
        loadProfiles()
    }

    // MARK: - Public API

    /// Returns the first enabled profile whose matchers fire for the given context,
    /// or nil if no profile matches.
    func resolveProfile(for ctx: ActiveAppContext) -> AppProfile? {
        profiles.first { $0.isEnabled && $0.matches(ctx) }
    }

    /// Appends formatting instructions to `basePrompt` based on the matched profile
    /// for `app`. Falls back to a plain-text hint when no profile matches.
    func enrichSystemPrompt(_ basePrompt: String, for app: NSRunningApplication?) -> String {
        guard let app else { return basePrompt }

        let ctx = ActiveAppContext(from: app)
        let instructions: String

        if let profile = resolveProfile(for: ctx) {
            instructions = profile.combinedInstructions
        } else {
            // Always-on plain-text fallback — safe for any unknown app.
            instructions = FormattingPreset.plainText.instructionText
        }

        return basePrompt + "\n\n" + instructions
    }

    // MARK: - CRUD

    func addProfile(_ profile: AppProfile) {
        profiles.append(profile)
    }

    func updateProfile(_ profile: AppProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        }
    }

    func deleteProfile(_ profile: AppProfile) {
        profiles.removeAll { $0.id == profile.id }
    }

    func moveProfiles(fromOffsets source: IndexSet, toOffset destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Persistence

    private func loadProfiles() {
        let hasInitialized = UserDefaults.standard.bool(forKey: hasInitializedKey)

        if !hasInitialized {
            profiles = Self.starterProfiles
            saveProfiles()
            UserDefaults.standard.set(true, forKey: hasInitializedKey)
            return
        }

        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([AppProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = Self.starterProfiles
        }
    }

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    // MARK: - Starter Profiles

    static let starterProfiles: [AppProfile] = [
        AppProfile(
            name: "Obsidian",
            matchers: [
                AppMatcher(bundleIdentifierEquals: "md.obsidian", appNameContains: "Obsidian")
            ],
            formattingPreset: .markdown,
            additionalInstructions: "You are writing into an Obsidian vault. Wikilinks ([[link]]) are acceptable."
        ),
        AppProfile(
            name: "VS Code / Cursor",
            matchers: [
                AppMatcher(bundleIdentifierEquals: "com.microsoft.VSCode", appNameContains: ""),
                AppMatcher(bundleIdentifierEquals: "com.todesktop.230313mzl4w4u92", appNameContains: "Cursor")
            ],
            formattingPreset: .codeFriendly,
            additionalInstructions: "You are editing inside a code editor. Preserve indentation and use fenced code blocks with the correct language tag."
        ),
        AppProfile(
            name: "Microsoft Teams",
            matchers: [
                AppMatcher(bundleIdentifierEquals: "com.microsoft.teams2", appNameContains: "Teams")
            ],
            formattingPreset: .plainText,
            additionalInstructions: "You are writing a Teams message. Keep it concise and conversational."
        ),
        AppProfile(
            name: "Slack",
            matchers: [
                AppMatcher(bundleIdentifierEquals: "com.tinyspeck.slackmacgap", appNameContains: "Slack")
            ],
            formattingPreset: .plainText,
            additionalInstructions: "You are writing a Slack message. Use lightweight formatting only (bold with *word*, code with `code`)."
        ),
        AppProfile(
            name: "Apple Mail",
            matchers: [
                AppMatcher(bundleIdentifierEquals: "com.apple.mail", appNameContains: "Mail")
            ],
            formattingPreset: .emailFriendly,
            additionalInstructions: "You are composing an email in Apple Mail. Use a professional tone and proper salutation/closing where appropriate."
        )
    ]
}

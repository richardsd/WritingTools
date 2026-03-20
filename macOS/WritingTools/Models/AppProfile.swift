import Foundation
import AppKit

// MARK: - Active App Context

/// Ephemeral snapshot of the frontmost macOS application at the moment a command is triggered.
struct ActiveAppContext {
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String?

    init(from app: NSRunningApplication) {
        self.appName = app.localizedName ?? ""
        self.bundleIdentifier = app.bundleIdentifier
        self.windowTitle = nil // Window title not available from NSRunningApplication directly
    }
}

// MARK: - Formatting Preset

/// Built-in formatting style presets, each carrying ready-to-inject LLM instructions.
enum FormattingPreset: String, Codable, CaseIterable, Identifiable {
    case plainText      = "Plain Text"
    case markdown       = "Markdown"
    case emailFriendly  = "Email-Friendly"
    case codeFriendly   = "Code-Friendly"

    var id: String { rawValue }

    var instructionText: String {
        switch self {
        case .plainText:
            return "Return plain text only. Do not use Markdown headings, bullet syntax, tables, or code fences. Use natural prose and line breaks where needed."
        case .markdown:
            return "Markdown formatting is allowed and preferred. Use headings, bold, italics, bullet lists, numbered lists, code blocks, and tables where appropriate."
        case .emailFriendly:
            return "Return polished, email-friendly text. Use natural paragraphs and line breaks. Do not use raw Markdown syntax, code fences, or Markdown headings."
        case .codeFriendly:
            return "Markdown and code blocks are allowed. Use fenced code blocks with the appropriate language tag for any code. Prose may use standard Markdown formatting."
        }
    }
}

// MARK: - App Matcher

/// A single rule for matching an application.
/// Either field may be non-empty; at least one must match for the rule to fire.
struct AppMatcher: Codable, Identifiable {
    var id: UUID
    /// Exact match against the app's bundle identifier (e.g. "md.obsidian").
    var bundleIdentifierEquals: String
    /// Case-insensitive substring match against the app's localized name.
    var appNameContains: String

    init(id: UUID = UUID(), bundleIdentifierEquals: String = "", appNameContains: String = "") {
        self.id = id
        self.bundleIdentifierEquals = bundleIdentifierEquals
        self.appNameContains = appNameContains
    }

    /// Returns true if this matcher fires for the given context.
    func matches(_ ctx: ActiveAppContext) -> Bool {
        var matched = false

        if !bundleIdentifierEquals.isEmpty,
           let bid = ctx.bundleIdentifier {
            matched = matched || bid.lowercased() == bundleIdentifierEquals.lowercased()
        }

        if !appNameContains.isEmpty {
            matched = matched || ctx.appName.localizedCaseInsensitiveContains(appNameContains)
        }

        return matched
    }

    /// True when the matcher has at least one non-empty criterion.
    var isConfigured: Bool {
        !bundleIdentifierEquals.isEmpty || !appNameContains.isEmpty
    }
}

// MARK: - App Profile

/// A profile that describes formatting preferences for a set of matched applications.
struct AppProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var matchers: [AppMatcher]
    var formattingPreset: FormattingPreset
    /// Extra free-form instructions appended after the preset's built-in text.
    var additionalInstructions: String

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        matchers: [AppMatcher] = [],
        formattingPreset: FormattingPreset = .plainText,
        additionalInstructions: String = ""
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.matchers = matchers
        self.formattingPreset = formattingPreset
        self.additionalInstructions = additionalInstructions
    }

    /// Returns true when at least one configured matcher fires for the given context.
    func matches(_ ctx: ActiveAppContext) -> Bool {
        matchers.contains { $0.isConfigured && $0.matches(ctx) }
    }

    /// The combined instruction text sent to the LLM for this profile.
    var combinedInstructions: String {
        var parts: [String] = [formattingPreset.instructionText]
        let trimmed = additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: " ")
    }
}

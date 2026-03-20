# Writing Tools - Copilot Instructions

## Project Overview

Writing Tools is an AI-powered writing assistant that works system-wide on Windows, Linux, and macOS. It provides Apple Intelligence-inspired features like proofreading, rewriting, summarization, and custom text transformations using various LLM providers (Gemini, OpenAI-compatible APIs, Ollama, MLX).

**Two distinct implementations:**
- **Windows/Linux**: Python-based (PySide6) in `Windows_and_Linux/`
- **macOS**: Native Swift port in `macOS/`

## Running & Building

### Windows/Linux Version

**Run from source:**
```bash
cd Windows_and_Linux
pip install -r requirements.txt
python main.py
```

**Build executable:**
```bash
cd Windows_and_Linux
pip install virtualenv
virtualenv myvenv
# On Windows: myvenv\Scripts\activate
# On Linux: source myvenv/bin/activate
pip install -r requirements.txt
python pyinstaller-build-script.py
```

### macOS Version

**Requirements:** macOS 14+, Xcode 15+

**Build:**
1. Open `macOS/WritingTools.xcodeproj` in Xcode
2. Set Deployment Target to macOS 14.0
3. Configure Signing & Capabilities with your development team
4. Run on "My Mac" (⌘R)

**Note:** First run requires Accessibility and Screen Recording permissions.

## Architecture

### Windows/Linux (Python)

**Entry point:** `Windows_and_Linux/main.py` → initializes `WritingToolApp`

**Core components:**
- `WritingToolApp.py` - Main Qt application, manages hotkeys, system tray, and UI coordination
- `aiprovider.py` - Abstract provider system with concrete implementations:
  - `GeminiProvider` - Google Generative AI
  - `OpenAICompatibleProvider` - OpenAI API and compatibles
  - `OllamaProvider` - Local Ollama server
- `ui/` directory:
  - `CustomPopupWindow.py` - Main action selection popup
  - `ResponseWindow.py` - Display summaries with markdown rendering
  - `SettingsWindow.py` - Provider and app configuration
  - `OnboardingWindow.py` - First-time setup wizard
- `options.json` - Defines available actions (Proofread, Rewrite, etc.) with prompts and icons
- `update_checker.py` - Checks GitHub for new releases

**Data flow:**
1. Hotkey triggers → `CustomPopupWindow` shows options
2. User selects action → prompt constructed from `options.json`
3. `aiprovider` sends request to configured LLM
4. Response either:
   - Replaces selected text directly (Proofread, Rewrite, etc.)
   - Opens `ResponseWindow` for viewing (Summary, Key Points, Table)

**Provider pattern:**
All providers inherit from `AIProvider` abstract base class with:
- `get_response(system_instruction, prompt)` - Main method for getting LLM responses
- `load_config(config)` / `save_config()` - Persistence
- `get_settings()` - Returns list of `AIProviderSetting` objects for UI rendering
- `cancel_request()` - Abort ongoing requests

### macOS (Swift)

**Entry point:** `macOS/WritingTools/writing_toolsApp.swift` → SwiftUI app lifecycle

**Core structure:**
- `App/` - Application state, settings, keychain management
- `Models/` - Data models for commands, providers, responses
- `Services/` - AI provider integrations (OpenAI, Gemini, Anthropic, Mistral, OpenRouter, MLX, Ollama)
- `Views/` - SwiftUI views for UI components
- `Utilities/` - Helper classes for text manipulation, accessibility

**Key features:**
- Uses macOS Accessibility API for reading/replacing text
- Native MLX support for on-device Apple Silicon inference
- RTF-preserving proofread that maintains formatting
- Per-command provider configuration
- Localized in EN/DE/FR/ES

## Key Conventions

### Configuration Files

**Windows/Linux:**
- Config stored in same directory as executable
- `config.json` - Provider settings, hotkey, theme, locale
- `options.json` - Action definitions with prompts
- API keys obfuscated with XOR + Base64 (prefix: `enc:`)

**macOS:**
- Settings managed through `UserDefaults` and `AppSettings`
- API keys stored securely in macOS Keychain
- Commands editable through UI with custom shortcuts

### Custom Actions/Commands

**Windows/Linux:**
Add to `options.json`:
```json
"Action Name": {
  "prefix": "System instruction prefix:\n\n",
  "instruction": "Detailed system instruction...",
  "icon": "icons/icon-name",
  "open_in_window": false
}
```

**macOS:**
Commands editable through Settings UI - stored in app preferences.

### Localization

**Windows/Linux:**
- Uses GNU gettext (`.po` files in `locales/`)
- Translation strings wrapped with `_()`
- Run `create_translation.sh` to extract/update translations

**macOS:**
- Uses Xcode's Localizable.xcstrings
- Supports EN, DE, FR, ES out of the box

### Error Handling

Both implementations expect `ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST` response from LLM when input is incompatible with the requested action (e.g., gibberish text).

### Theme Support

**Windows/Linux:**
- Two themes: "gradient" (blurry) and "plain" (Windows-like)
- Dark mode detection via `darkdetect` library
- Background images in `Windows_and_Linux/` directory

**macOS:**
- Multiple SwiftUI themes
- Automatic dark mode via system preferences

## Important Notes

- **Portable app (Windows):** If extracted to protected folders (e.g., Program Files), must run as administrator on first launch to create config files
- **Linux Wayland:** Works on XWayland apps; native Wayland apps require Flatseal configuration
- **macOS permissions:** Both Accessibility and Screen Recording permissions may be needed depending on the target application
- **Streaming removed:** All streaming code has been removed; responses are now delivered complete
- **Conversation history:** Managed by main app for follow-up questions in response windows
- **Hotkey conflicts:** Default `Ctrl+Space` may conflict with system shortcuts - app allows custom hotkey configuration

## Testing

No formal test suite exists. Manual testing involves:
1. Installing dependencies
2. Running the application
3. Testing text replacement in various applications
4. Verifying AI provider responses
5. Checking UI interactions (settings, response windows, custom actions)

## Build Output

**Windows/Linux:**
- PyInstaller creates portable executable in `dist/` directory
- All assets (icons, backgrounds, config files) must be bundled

**macOS:**
- Xcode builds `.app` bundle
- Distributed as `.dmg` for easy installation
- Requires code signing for distribution outside App Store

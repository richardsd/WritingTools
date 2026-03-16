import SwiftUI

/// A single row in the matchers list inside the profile editor.
struct AppMatcherRowView: View {
    @Binding var matcher: AppMatcher
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bundle ID:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    TextField("e.g. md.obsidian", text: $matcher.bundleIdentifierEquals)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                HStack {
                    Text("App name:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    TextField("e.g. Obsidian", text: $matcher.appNameContains)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

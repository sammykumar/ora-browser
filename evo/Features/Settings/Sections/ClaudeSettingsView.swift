import SwiftUI

struct ClaudeSettingsView: View {
    @AppStorage("claude.binaryPath") private var binaryPath = ""
    @State private var resolved = ""

    var body: some View {
        SettingsSection {
            SettingsCard(
                header: "claude CLI",
                description: "Override the path to the claude binary, or leave blank to auto-detect it on your PATH."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Binary path (leave blank to auto-detect)", text: $binaryPath)

                    HStack {
                        Button("Detect") {
                            if case let .success(path) = ClaudeBinaryLocator.resolve() {
                                resolved = path
                            }
                        }

                        if !resolved.isEmpty {
                            Text("Resolved: \(resolved)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

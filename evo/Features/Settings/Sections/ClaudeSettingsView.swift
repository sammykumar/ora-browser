import SwiftUI

struct ClaudeSettingsView: View {
    private enum DetectState {
        case idle
        case resolved(String)
        case failed
    }

    @AppStorage("claude.binaryPath") private var binaryPath = ""
    @State private var detectState: DetectState = .idle

    var body: some View {
        SettingsSection {
            SettingsCard(
                header: "claude CLI",
                description: "Override the path to the claude binary, or leave blank to auto-detect it on your PATH."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Binary path (leave blank to auto-detect)", text: $binaryPath)

                    Button("Detect") {
                        detectState = .idle
                        switch ClaudeBinaryLocator.resolve() {
                        case let .success(path):
                            detectState = .resolved(path)
                        case .failure:
                            detectState = .failed
                        }
                    }

                    switch detectState {
                    case .idle:
                        EmptyView()
                    case let .resolved(path):
                        Text("Resolved: \(path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .failed:
                        Text("claude not found — install the Claude CLI or enter its path above")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

import SwiftUI

struct OnePasswordConnectionPanel: View {
    @StateObject private var service = OnePasswordService.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var newAccount = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OnePasswordPanelModel.statusLine(
                state: service.state,
                accountCount: settings.onePasswordAccounts.count,
                itemCount: service.metadata.count
            ))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)

            ForEach(settings.onePasswordAccounts, id: \.self) { account in
                HStack {
                    Text(account)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button(role: .destructive) {
                        settings.removeOnePasswordAccount(account)
                        reconfigure()
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Add account (e.g. my.1password.com)", text: $newAccount)
                    .textFieldStyle(.roundedBorder)
                EvoButton(label: "Add", variant: .secondary, size: .sm) {
                    settings.addOnePasswordAccount(newAccount)
                    newAccount = ""
                    reconfigure()
                }
            }

            EvoButton(label: "Reconnect", variant: .secondary, leadingIcon: "arrow.clockwise") {
                reconfigure()
            }
        }
    }

    private func reconfigure() {
        service.configureAccounts(settings.onePasswordAccounts)
        Task { await service.refresh() }
    }
}

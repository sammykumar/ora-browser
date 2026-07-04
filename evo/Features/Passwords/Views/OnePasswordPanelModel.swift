import Foundation

enum OnePasswordPanelModel {
    static func statusLine(state: ProviderState, accountCount: Int, itemCount: Int) -> String {
        switch state {
        case .ready:
            let accts = "\(accountCount) account\(accountCount == 1 ? "" : "s")"
            let items = "\(itemCount) item\(itemCount == 1 ? "" : "s")"
            return "Connected · \(accts) · \(items)"
        case .syncing:
            return "Syncing…"
        case .locked:
            return "Locked"
        case let .unavailable(reason):
            return reason
        }
    }
}

import Foundation

/// Pure model backing the 1Password save-prompt account + vault picker.
///
/// Resolved by fetching every configured account's vaults (`OnePasswordService.listVaults`)
/// before the save prompt is shown, so the destination vault id is always a real one — never
/// an empty string. When there's exactly one account with exactly one vault, `needsPicker` is
/// `false` and the caller saves directly to `defaultAccount` / `defaultVaultID(for:)` with no UI.
struct SaveTargetPickerModel {
    let accounts: [String]
    let vaultsByAccount: [String: [(id: String, title: String)]]

    var defaultAccount: String {
        accounts.first ?? ""
    }

    func defaultVaultID(for account: String) -> String? {
        vaultsByAccount[account]?.first?.id
    }

    var needsPicker: Bool {
        if accounts.count > 1 { return true }
        if let only = accounts.first, (vaultsByAccount[only]?.count ?? 0) > 1 { return true }
        return false
    }
}

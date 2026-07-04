//
//  PasswordAutofillCoordinator+Save.swift
//  evo
//
//  Save-prompt routing: builds the provider-appropriate `SaveTarget` and, for 1Password,
//  resolves a REAL destination vault before ever constructing that target.
//
//  Task 3.3 shipped `saveTarget(...)` with `defaultVaultID: nil`, which produced an empty
//  vault id for every 1Password save — the sidecar rejects `saveItem` with an empty vault id,
//  and the old `try?` swallowed the failure silently. Task 3.4 fixes that by always fetching
//  the configured accounts' real vaults (`OnePasswordService.listVaults`) first, then either
//  saving straight to the sole account+vault or showing an account/vault picker when there's
//  more than one place to save to. Failures now surface as a toast instead of vanishing.
//

import AppKit
import Foundation

extension PasswordAutofillCoordinator {
    func handleSubmit(_ payload: PasswordBridgeSubmitPayload, pageURL: URL?) {
        guard settings.passwordsEnabled,
              settings.passwordSavePromptsEnabled,
              tab?.isPrivate == false,
              let pageURL,
              let normalizedHost = PasswordManagerService.normalizedHost(from: pageURL)
        else {
            return
        }

        guard settings.allowsPasswordSavePrompts(for: normalizedHost) else {
            return
        }

        let trimmedUsername = payload.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = payload.password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard payload.action == .login || payload.action == .createAccount,
              !trimmedPassword.isEmpty
        else {
            return
        }

        // 1Password has no local record of its items (the Evo keychain is always empty for a
        // 1Password user), so the dedup/"is this already saved?" check must ask 1Password's own
        // metadata cache instead of `passwordManager.matchingEntries`. We deliberately don't
        // reveal the stored password to compare it (that would trigger an extra auth prompt) —
        // any match on username is treated as "prompt to update", never silently skipped.
        if settings.passwordManagerProvider == .onePassword {
            Task { @MainActor [weak self] in
                await self?.handleOnePasswordSubmit(
                    pageURL: pageURL,
                    normalizedHost: normalizedHost,
                    username: trimmedUsername,
                    password: trimmedPassword
                )
            }
            return
        }

        let matchingEntry = passwordManager
            .matchingEntries(for: pageURL, containerID: tab?.container.id)
            .first { $0.username == trimmedUsername }

        if let matchingEntry,
           let storedPassword = try? passwordManager.revealPassword(for: matchingEntry),
           storedPassword == trimmedPassword
        {
            return
        }

        let prompt = Self.savePromptDetails(
            for: pageURL,
            username: trimmedUsername,
            normalizedHost: normalizedHost,
            isUpdate: matchingEntry != nil
        )

        Task { @MainActor [weak self] in
            await self?.presentSaveFlow(
                prompt: prompt,
                normalizedHost: normalizedHost,
                pageURL: pageURL,
                username: trimmedUsername,
                password: trimmedPassword
            )
        }
    }

    /// Resolves the existing-match/dedup check for a 1Password submit, then hands off to
    /// `presentSaveFlow` with `existingOnePasswordItem` set when a matching item was found.
    @MainActor
    private func handleOnePasswordSubmit(
        pageURL: URL,
        normalizedHost: String,
        username: String,
        password: String
    ) async {
        let existingItem = Self.existingOnePasswordItemID(
            matching: username,
            in: OnePasswordService.shared.credentials(for: pageURL)
        )

        let prompt = Self.savePromptDetails(
            for: pageURL,
            username: username,
            normalizedHost: normalizedHost,
            isUpdate: existingItem != nil
        )

        await presentSaveFlow(
            prompt: prompt,
            normalizedHost: normalizedHost,
            pageURL: pageURL,
            username: username,
            password: password,
            existingOnePasswordItem: existingItem
        )
    }

    /// Returns the account/vault/item-id triple of the first 1Password credential whose username
    /// matches `username`, or `nil` if none of the already-saved items match. Used to route a save
    /// to the sidecar's UPDATE path (non-empty `itemId`) instead of always creating a new item.
    static func existingOnePasswordItemID(
        matching username: String,
        in credentials: [ProviderCredential]
    ) -> (accountName: String, vaultID: String, itemID: String)? {
        guard let match = credentials.first(where: { $0.username == username }) else {
            return nil
        }
        guard case let .onePassword(accountName, vaultID, itemID) = match.ref else {
            return nil
        }
        return (accountName: accountName, vaultID: vaultID, itemID: itemID)
    }

    /// Resolves the save destination before showing the confirmation alert. For 1Password this
    /// fetches every configured account's real vaults first — so both the direct-save path and
    /// the picker's defaults always carry a real vault id, never an empty one.
    ///
    /// When `existingOnePasswordItem` is non-nil (an already-saved 1Password item matches the
    /// submitted username), the save targets that exact account/vault/item — skipping the
    /// account/vault picker entirely, since the destination is already known — so the sidecar
    /// performs an UPDATE instead of creating a duplicate item.
    @MainActor
    func presentSaveFlow(
        prompt: PasswordSavePromptDetails,
        normalizedHost: String,
        pageURL: URL,
        username: String,
        password: String,
        existingOnePasswordItem: (accountName: String, vaultID: String, itemID: String)? = nil
    ) async {
        let providerKind = settings.passwordManagerProvider

        guard providerKind == .onePassword else {
            presentSavePrompt(prompt, normalizedHost: normalizedHost, pickerModel: nil) { [weak self] _, _ in
                let target = Self.saveTarget(
                    forProvider: providerKind, accounts: [], defaultVaultID: nil,
                    containerID: self?.tab?.container.id, existingItemID: nil
                )
                self?.performSave(
                    providerKind: providerKind,
                    target: target,
                    pageURL: pageURL,
                    username: username,
                    password: password
                )
            }
            return
        }

        if let existingOnePasswordItem {
            presentUpdateExistingOnePasswordItem(
                existingOnePasswordItem,
                prompt: prompt,
                normalizedHost: normalizedHost,
                pageURL: pageURL,
                username: username,
                password: password
            )
            return
        }

        let accounts = settings.onePasswordAccounts
        guard !accounts.isEmpty else {
            ToastManager.shared.show("No 1Password account configured", type: .error)
            return
        }

        let vaultsByAccount = await Self.fetchVaults(for: accounts)
        let pickerModel = SaveTargetPickerModel(accounts: accounts, vaultsByAccount: vaultsByAccount)

        guard pickerModel.defaultVaultID(for: pickerModel.defaultAccount) != nil else {
            ToastManager.shared.show("No 1Password vault available to save to", type: .error)
            return
        }

        presentSavePrompt(
            prompt,
            normalizedHost: normalizedHost,
            pickerModel: pickerModel.needsPicker ? pickerModel : nil
        ) { [weak self] selectedAccount, selectedVaultID in
            let accountName = selectedAccount ?? pickerModel.defaultAccount
            let vaultID = selectedVaultID ?? pickerModel.defaultVaultID(for: accountName) ?? ""
            let target = Self.saveTarget(
                forProvider: .onePassword, accounts: [accountName], defaultVaultID: vaultID,
                containerID: nil, existingItemID: nil
            )
            self?.performSave(
                providerKind: .onePassword,
                target: target,
                pageURL: pageURL,
                username: username,
                password: password
            )
        }
    }

    /// Shows the save prompt and, on confirm, saves straight to the known existing item's
    /// account/vault — the sidecar's UPDATE path (non-empty `existingItemID`), not a create.
    @MainActor
    private func presentUpdateExistingOnePasswordItem(
        _ existingItem: (accountName: String, vaultID: String, itemID: String),
        prompt: PasswordSavePromptDetails,
        normalizedHost: String,
        pageURL: URL,
        username: String,
        password: String
    ) {
        presentSavePrompt(prompt, normalizedHost: normalizedHost, pickerModel: nil) { [weak self] _, _ in
            let target = Self.saveTarget(
                forProvider: .onePassword,
                accounts: [existingItem.accountName],
                defaultVaultID: existingItem.vaultID,
                containerID: nil,
                existingItemID: existingItem.itemID
            )
            self?.performSave(
                providerKind: .onePassword,
                target: target,
                pageURL: pageURL,
                username: username,
                password: password
            )
        }
    }

    private static func fetchVaults(for accounts: [String]) async -> [String: [(id: String, title: String)]] {
        var vaultsByAccount: [String: [(id: String, title: String)]] = [:]
        await withTaskGroup(of: (String, [(id: String, title: String)]).self) { group in
            for account in accounts {
                group.addTask {
                    let vaults = await (try? OnePasswordService.shared.listVaults(accountName: account)) ?? []
                    return (account, vaults)
                }
            }
            for await (account, vaults) in group {
                vaultsByAccount[account] = vaults
            }
        }
        return vaultsByAccount
    }

    private func performSave(
        providerKind: PasswordManagerProviderKind,
        target: SaveTarget,
        pageURL: URL,
        username: String,
        password: String
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let provider = self.providers.activeProvider(for: providerKind)
            do {
                try await provider.save(url: pageURL, username: username, password: password, target: target)
                ToastManager.shared.show("Password saved", type: .success)
            } catch {
                ToastManager.shared.show("Couldn't save password: \(error.localizedDescription)", type: .error)
            }
        }
    }

    @MainActor
    func presentSavePrompt(
        _ prompt: PasswordSavePromptDetails,
        normalizedHost: String,
        pickerModel: SaveTargetPickerModel?,
        onConfirm: @escaping (_ selectedAccount: String?, _ selectedVaultID: String?) -> Void
    ) {
        guard let window = presentationWindow() else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = prompt.showsSecurityWarning ? .warning : .informational
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.addButton(withTitle: prompt.confirmButtonTitle)
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: prompt.neverButtonTitle)

        var pickerController: SaveTargetPickerAccessoryController?
        if let pickerModel, pickerModel.needsPicker {
            let controller = SaveTargetPickerAccessoryController(model: pickerModel)
            alert.accessoryView = controller.view
            pickerController = controller
        }

        alert.beginSheetModal(for: window) { response in
            // `pickerController` (and its target-action-bound popups) is kept alive by this
            // closure until the sheet's completion handler runs.
            switch response {
            case .alertFirstButtonReturn:
                onConfirm(pickerController?.selectedAccount, pickerController?.selectedVaultID)
            case .alertThirdButtonReturn:
                self.settings.suppressPasswordSavePrompts(for: normalizedHost)
            default:
                break
            }
        }
    }

    /// Builds the provider-appropriate save destination. Callers (see `presentSaveFlow` above)
    /// are responsible for resolving a REAL 1Password `defaultVaultID` first — an empty vault id
    /// makes the sidecar's `saveItem` fail.
    static func saveTarget(
        forProvider kind: PasswordManagerProviderKind,
        accounts: [String],
        defaultVaultID: String?,
        containerID: UUID?,
        existingItemID: String?
    ) -> SaveTarget {
        switch kind {
        case .onePassword:
            return .onePassword(
                accountName: accounts.first ?? "", vaultID: defaultVaultID ?? "", existingItemID: existingItemID
            )
        default:
            return .evoContainer(containerID)
        }
    }
}

/// Backs the account + vault `NSPopUpButton` pair shown as the save alert's accessory view when
/// there's more than one place to save to (`SaveTargetPickerModel.needsPicker`).
@MainActor
final class SaveTargetPickerAccessoryController: NSObject {
    private let model: SaveTargetPickerModel
    private let accountPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let vaultPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    var selectedAccount: String? {
        accountPopup.titleOfSelectedItem
    }

    var selectedVaultID: String? {
        vaultPopup.selectedItem?.representedObject as? String
    }

    lazy var view: NSView = makeView()

    init(model: SaveTargetPickerModel) {
        self.model = model
        super.init()
        configure()
    }

    private func configure() {
        accountPopup.removeAllItems()
        accountPopup.addItems(withTitles: model.accounts)
        accountPopup.selectItem(withTitle: model.defaultAccount)
        accountPopup.target = self
        accountPopup.action = #selector(accountSelectionChanged)
        updateVaultPopup(for: model.defaultAccount)
    }

    @objc private func accountSelectionChanged() {
        updateVaultPopup(for: accountPopup.titleOfSelectedItem ?? model.defaultAccount)
    }

    private func updateVaultPopup(for account: String) {
        vaultPopup.removeAllItems()
        for vault in model.vaultsByAccount[account] ?? [] {
            vaultPopup.addItem(withTitle: vault.title)
            vaultPopup.lastItem?.representedObject = vault.id
        }
    }

    private func makeView() -> NSView {
        let accountLabel = NSTextField(labelWithString: "Account:")
        let vaultLabel = NSTextField(labelWithString: "Vault:")
        let stack = NSStackView(views: [accountLabel, accountPopup, vaultLabel, vaultPopup])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 108))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }
}

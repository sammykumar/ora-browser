import AppKit
import Foundation

enum PasswordAutofillSuggestion: Identifiable, Equatable {
    case generatedPassword(host: String, password: String)
    case savedCredential(ProviderCredential)
    case email(PasswordEmailSuggestion)
    case unlockProvider(label: String)
    case fillOneTimeCode(ProviderCredential)
    case fillCard(ProviderStructuredItem)
    case fillIdentity(ProviderStructuredItem)

    var id: String {
        switch self {
        case let .generatedPassword(_, password):
            return "generated-\(password)"
        case let .savedCredential(credential):
            return "saved-\(credential.id)"
        case let .email(suggestion):
            return "email-\(suggestion.id)"
        case let .unlockProvider(label):
            return "unlock-\(label)"
        case let .fillOneTimeCode(credential):
            return "totp-\(credential.id)"
        case let .fillCard(item):
            return "card-\(item.id)"
        case let .fillIdentity(item):
            return "identity-\(item.id)"
        }
    }

    var host: String {
        switch self {
        case let .generatedPassword(host, _):
            return host
        case let .savedCredential(credential):
            return credential.host
        case let .email(suggestion):
            return suggestion.host
        case .unlockProvider:
            return ""
        case let .fillOneTimeCode(credential):
            return credential.host
        case .fillCard:
            return ""
        case .fillIdentity:
            return ""
        }
    }
}

struct PasswordAutofillOverlayState: Equatable {
    let focus: PasswordBridgeFocusPayload
    let savedPasswordEntries: [ProviderCredential]
    let emailSuggestions: [PasswordEmailSuggestion]
    let generatedPassword: String?
    let oneTimeCodeCredential: ProviderCredential?
    let structuredItems: [ProviderStructuredItem]
    let selectedSuggestionIndex: Int
    var lockedProviderLabel: String?
    var isSyncing: Bool = false

    init(
        focus: PasswordBridgeFocusPayload,
        savedPasswordEntries: [ProviderCredential],
        emailSuggestions: [PasswordEmailSuggestion],
        generatedPassword: String?,
        oneTimeCodeCredential: ProviderCredential? = nil,
        structuredItems: [ProviderStructuredItem] = [],
        selectedSuggestionIndex: Int,
        lockedProviderLabel: String? = nil,
        isSyncing: Bool = false
    ) {
        self.focus = focus
        self.savedPasswordEntries = savedPasswordEntries
        self.emailSuggestions = emailSuggestions
        self.generatedPassword = generatedPassword
        self.oneTimeCodeCredential = oneTimeCodeCredential
        self.structuredItems = structuredItems
        self.selectedSuggestionIndex = selectedSuggestionIndex
        self.lockedProviderLabel = lockedProviderLabel
        self.isSyncing = isSyncing
    }

    var suggestions: [PasswordAutofillSuggestion] {
        if let lockedProviderLabel {
            return [.unlockProvider(label: lockedProviderLabel)]
        }

        if let oneTimeCodeCredential {
            return [.fillOneTimeCode(oneTimeCodeCredential)]
        }

        if focus.fieldKind == .creditCard {
            return structuredItems.map(PasswordAutofillSuggestion.fillCard)
        }

        if focus.fieldKind == .identity {
            return structuredItems.map(PasswordAutofillSuggestion.fillIdentity)
        }

        var items: [PasswordAutofillSuggestion] = []

        if let generatedPassword {
            items.append(.generatedPassword(host: focus.hostname, password: generatedPassword))
        }

        items.append(contentsOf: savedPasswordEntries.prefix(4).map(PasswordAutofillSuggestion.savedCredential))
        items.append(contentsOf: emailSuggestions.prefix(4).map(PasswordAutofillSuggestion.email))

        return items
    }
}

struct PasswordSavePromptDetails: Equatable {
    let title: String
    let message: String
    let confirmButtonTitle: String
    let neverButtonTitle: String
    let showsSecurityWarning: Bool
}

final class PasswordAutofillCoordinator {
    weak var tab: Tab?

    let passwordManager = PasswordManagerService.shared
    let providers = PasswordManagerProviderRegistry.shared
    let settings = SettingsStore.shared
    private let decoder = JSONDecoder()

    private var dismissWorkItem: DispatchWorkItem?
    private var overlayGeneration = 0

    init(tab: Tab) {
        self.tab = tab
    }

    func handleMessage(_ messageBody: String, pageURL: URL?) {
        guard let data = messageBody.data(using: .utf8),
              let message = try? decoder.decode(PasswordBridgeEvent.self, from: data)
        else {
            return
        }

        switch message.type {
        case "focus":
            dismissWorkItem?.cancel()
            if let focus = message.focus {
                presentOverlay(for: focus, pageURL: pageURL)
            }
        case "blur":
            scheduleDismissOverlay()
        case "rect":
            if let fieldID = message.fieldID, let rect = message.rect {
                updateOverlayRect(for: fieldID, rect: rect)
            }
        case "keyCommand":
            if let command = message.keyCommand {
                handleKeyCommand(command)
            }
        case "submit":
            clearAutofillState()
            if let submit = message.submit {
                handleSubmit(submit, pageURL: pageURL)
            }
        default:
            break
        }
    }

    func dismissOverlay() {
        dismissWorkItem?.cancel()
        overlayGeneration += 1
        tab?.passwordOverlayState = nil
        setOverlayKeyboardActive(false)
    }

    func clearAutofillState() {
        dismissWorkItem?.cancel()
        overlayGeneration += 1
        tab?.passwordOverlayState = nil
        tab?.passwordTriggerOverlayState = nil
        setOverlayKeyboardActive(false)
    }

    func presentTriggerOverlay() {
        dismissWorkItem?.cancel()
        guard let overlay = tab?.passwordTriggerOverlayState else { return }
        tab?.passwordOverlayState = overlay
        setOverlayKeyboardActive(true)
    }

    func autofill(_ credential: ProviderCredential, for overlay: PasswordAutofillOverlayState) {
        Task { [weak self] in
            guard let self else { return }

            let provider = await self.providers.activeProvider(for: self.settings.passwordManagerProvider)
            guard let revealed = try? await provider.reveal(credential) else {
                return
            }

            await MainActor.run {
                let request = PasswordFillRequest(
                    usernameFieldID: overlay.focus.usernameFieldID,
                    passwordFieldIDs: overlay.focus.passwordFieldIDs,
                    username: revealed.username.isEmpty ? nil : revealed.username,
                    password: revealed.password,
                    highlightColor: "#E8F5E9",
                    submitAfterFill: overlay.focus.action == .login && self.settings.passwordAutofillSubmitEnabled
                )

                self.evaluate(scriptMethod: "fillCredentials", payload: request)
                self.dismissOverlay()
            }
        }
    }

    func fillGeneratedPassword(for overlay: PasswordAutofillOverlayState) {
        guard let generatedPassword = overlay.generatedPassword else {
            return
        }

        guard tab?.browserPage != nil else {
            return
        }

        let request = PasswordFillRequest(
            usernameFieldID: nil,
            passwordFieldIDs: overlay.focus.passwordFieldIDs,
            username: nil,
            password: generatedPassword,
            highlightColor: "#FFF4CC",
            submitAfterFill: false
        )

        evaluate(scriptMethod: "fillCredentials", payload: request)
        dismissOverlay()
    }

    func fillOneTimeCode(_ credential: ProviderCredential, for overlay: PasswordAutofillOverlayState) {
        Task { [weak self] in
            guard let self else { return }

            let provider = await self.providers.activeProvider(for: self.settings.passwordManagerProvider)
            guard let code = try? await provider.totp(for: credential) else { return }

            await MainActor.run {
                let request = PasswordFillRequest(
                    usernameFieldID: overlay.focus.fieldID, // the OTP field is the focused field
                    passwordFieldIDs: [],
                    username: code,
                    password: "",
                    highlightColor: "#E8F1FF",
                    submitAfterFill: false
                )
                self.evaluate(scriptMethod: "fillCredentials", payload: request)
                self.dismissOverlay()

                ClipboardUtils.copySensitive(code, clearingAfter: 90)
                ToastManager.shared.show("One-time code copied", type: .info, icon: .system("clock"))
            }
        }
    }

    // fillStructured / structuredFillEntries (card + identity fill) live in
    // PasswordAutofillCoordinator+Structured.swift.

    func fillEmailSuggestion(_ suggestion: PasswordEmailSuggestion, for overlay: PasswordAutofillOverlayState) {
        guard overlay.focus.fieldKind == .email else {
            return
        }

        guard tab?.browserPage != nil else {
            return
        }

        let request = PasswordFillRequest(
            usernameFieldID: overlay.focus.fieldID,
            passwordFieldIDs: [],
            username: suggestion.email,
            password: "",
            highlightColor: "#E8F1FF",
            submitAfterFill: false
        )

        evaluate(scriptMethod: "fillCredentials", payload: request)
        dismissOverlay()
    }

    func updateSelection(to index: Int, for overlay: PasswordAutofillOverlayState) {
        let boundedIndex = boundedSelectionIndex(index, for: overlay)
        applySelectionIndex(boundedIndex, forFieldID: overlay.focus.fieldID)
    }

    @MainActor
    func openPasswordsManager() {
        openPasswordsWindow()
        dismissOverlay()
    }

    private func resolvedSuggestions(
        for focus: PasswordBridgeFocusPayload,
        provider: PasswordProvider,
        providerKind: PasswordManagerProviderKind,
        pageURL: URL,
        containerID: UUID?
    ) async -> PasswordAutofillOverlayState {
        if focus.fieldKind == .creditCard {
            let cards = await provider.structuredItems(.creditCard)
            return Self.resolveSuggestions(
                for: focus,
                matchingEntries: [],
                emailSuggestions: [],
                generatedPassword: nil,
                structuredItems: cards
            )
        }

        if focus.fieldKind == .identity {
            let ids = await provider.structuredItems(.identity)
            return Self.resolveSuggestions(
                for: focus,
                matchingEntries: [],
                emailSuggestions: [],
                generatedPassword: nil,
                structuredItems: ids
            )
        }

        let matchingEntries = await provider.credentials(for: pageURL, containerID: containerID)

        let emailSuggestions: [PasswordEmailSuggestion] = providerKind == .evo
            ? passwordManager.emailSuggestions(for: containerID)
            : []
        let generatedPassword: String? = providerKind == .evo && focus.action == .createAccount
            ? passwordManager.generateStrongPassword()
            : nil

        return Self.resolveSuggestions(
            for: focus,
            matchingEntries: matchingEntries,
            emailSuggestions: emailSuggestions,
            generatedPassword: generatedPassword
        )
    }

    private func presentOverlay(for focus: PasswordBridgeFocusPayload, pageURL: URL?) {
        guard settings.passwordsEnabled,
              settings.passwordAutofillEnabled,
              tab?.isPrivate == false,
              let pageURL,
              let normalizedHost = PasswordManagerService.normalizedHost(from: pageURL)
        else {
            clearAutofillState()
            return
        }

        let providerKind = settings.passwordManagerProvider
        let containerID = tab?.container.id

        overlayGeneration += 1
        let generation = overlayGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }

            let provider = self.providers.activeProvider(for: providerKind)

            switch provider.state {
            case .locked:
                let providerLabel = self.providers.descriptor(for: providerKind).title
                self.presentPlaceholderOverlay(
                    for: focus,
                    normalizedHost: normalizedHost,
                    lockedProviderLabel: providerLabel
                )
                return
            case .syncing:
                self.presentPlaceholderOverlay(for: focus, normalizedHost: normalizedHost, isSyncing: true)
                return
            case .ready, .unavailable:
                break
            }

            let suggestions = await self.resolvedSuggestions(
                for: focus,
                provider: provider,
                providerKind: providerKind,
                pageURL: pageURL,
                containerID: containerID
            )

            guard generation == self.overlayGeneration else { return }

            guard !suggestions.savedPasswordEntries.isEmpty
                || !suggestions.emailSuggestions.isEmpty
                || suggestions.generatedPassword != nil
                || suggestions.oneTimeCodeCredential != nil
                || !suggestions.structuredItems.isEmpty
            else {
                self.clearAutofillState()
                return
            }

            let overlayState = Self.makeOverlayState(
                for: focus,
                normalizedHost: normalizedHost,
                suggestions: suggestions
            )

            self.tab?.passwordTriggerOverlayState = overlayState
            self.tab?.passwordOverlayState = overlayState
            self.setOverlayKeyboardActive(true)
        }
    }

    private func updateOverlayRect(for fieldID: String, rect: PasswordBridgeRect) {
        if let triggerOverlay = tab?.passwordTriggerOverlayState,
           triggerOverlay.focus.fieldID == fieldID
        {
            tab?.passwordTriggerOverlayState = overlayState(triggerOverlay, updatingRectTo: rect)
        }

        if let overlay = tab?.passwordOverlayState,
           overlay.focus.fieldID == fieldID
        {
            tab?.passwordOverlayState = overlayState(overlay, updatingRectTo: rect)
        }
    }

    // handleSubmit / presentSaveFlow / presentSavePrompt live in
    // PasswordAutofillCoordinator+Save.swift (save-prompt routing + account/vault picker).

    @MainActor
    func presentationWindow() -> NSWindow? {
        if let window = tab?.pageWindow {
            return window
        }

        if let appDelegate = NSApp.delegate as? AppDelegate {
            return appDelegate.getWindow()
        }

        return NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible })
            ?? NSApp.windows.first
    }

    private func scheduleDismissOverlay() {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.clearAutofillState()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func overlayState(
        _ overlay: PasswordAutofillOverlayState,
        updatingRectTo rect: PasswordBridgeRect
    ) -> PasswordAutofillOverlayState {
        PasswordAutofillOverlayState(
            focus: overlay.focus.withRect(rect),
            savedPasswordEntries: overlay.savedPasswordEntries,
            emailSuggestions: overlay.emailSuggestions,
            generatedPassword: overlay.generatedPassword,
            oneTimeCodeCredential: overlay.oneTimeCodeCredential,
            structuredItems: overlay.structuredItems,
            selectedSuggestionIndex: overlay.selectedSuggestionIndex,
            lockedProviderLabel: overlay.lockedProviderLabel,
            isSyncing: overlay.isSyncing
        )
    }

    private func overlayState(
        _ overlay: PasswordAutofillOverlayState,
        updatingSelectionIndexTo selectionIndex: Int
    ) -> PasswordAutofillOverlayState {
        PasswordAutofillOverlayState(
            focus: overlay.focus,
            savedPasswordEntries: overlay.savedPasswordEntries,
            emailSuggestions: overlay.emailSuggestions,
            generatedPassword: overlay.generatedPassword,
            oneTimeCodeCredential: overlay.oneTimeCodeCredential,
            structuredItems: overlay.structuredItems,
            selectedSuggestionIndex: selectionIndex,
            lockedProviderLabel: overlay.lockedProviderLabel,
            isSyncing: overlay.isSyncing
        )
    }

    func evaluate(scriptMethod: String, payload: some Encodable) {
        guard let data = try? JSONEncoder().encode(payload),
              let payloadString = String(data: data, encoding: .utf8)
        else {
            return
        }

        let script = """
        if (window.__evoPasswordManager && typeof window.__evoPasswordManager.\(scriptMethod) === 'function') {
            window.__evoPasswordManager.\(scriptMethod)(\(payloadString));
        }
        """
        tab?.evaluateJavaScript(script)
    }

    private func setOverlayKeyboardActive(_ isActive: Bool) {
        guard tab?.browserPage != nil else { return }
        evaluate(scriptMethod: "setOverlayKeyboardActive", payload: isActive)
    }

    func handleKeyCommand(_ command: PasswordAutofillKeyCommand) {
        switch command {
        case .moveUp:
            moveSelection(by: -1)
        case .moveDown:
            moveSelection(by: 1)
        case .activate:
            activateCurrentSelection()
        case .dismiss:
            dismissOverlay()
        }
    }

    func moveSelection(by delta: Int) {
        guard let overlay = tab?.passwordOverlayState else { return }
        let suggestionCount = overlay.suggestions.count
        guard suggestionCount > 0 else { return }

        let nextIndex = min(max(overlay.selectedSuggestionIndex + delta, 0), suggestionCount - 1)
        applySelectionIndex(nextIndex, forFieldID: overlay.focus.fieldID)
    }

    func activateCurrentSelection() {
        guard let overlay = tab?.passwordOverlayState,
              overlay.suggestions.indices.contains(overlay.selectedSuggestionIndex)
        else {
            return
        }

        switch overlay.suggestions[overlay.selectedSuggestionIndex] {
        case .generatedPassword:
            fillGeneratedPassword(for: overlay)
        case let .savedCredential(entry):
            autofill(entry, for: overlay)
        case let .email(suggestion):
            fillEmailSuggestion(suggestion, for: overlay)
        case let .fillOneTimeCode(credential):
            fillOneTimeCode(credential, for: overlay)
        case let .fillCard(item):
            fillStructured(item, for: overlay)
        case let .fillIdentity(item):
            fillStructured(item, for: overlay)
        case .unlockProvider:
            Task { @MainActor [weak self] in
                self?.unlockActiveProvider()
            }
        }
    }

    private func applySelectionIndex(_ selectionIndex: Int, forFieldID fieldID: String) {
        if let overlay = tab?.passwordOverlayState,
           overlay.focus.fieldID == fieldID
        {
            tab?.passwordOverlayState = overlayState(overlay, updatingSelectionIndexTo: selectionIndex)
        }

        if let triggerOverlay = tab?.passwordTriggerOverlayState,
           triggerOverlay.focus.fieldID == fieldID
        {
            tab?.passwordTriggerOverlayState = overlayState(triggerOverlay, updatingSelectionIndexTo: selectionIndex)
        }
    }

    private func boundedSelectionIndex(_ selectionIndex: Int, for overlay: PasswordAutofillOverlayState) -> Int {
        let suggestionCount = overlay.suggestions.count
        guard suggestionCount > 0 else { return -1 }
        return min(max(selectionIndex, 0), suggestionCount - 1)
    }

    static func savePromptDetails(
        for pageURL: URL,
        username: String,
        normalizedHost: String,
        isUpdate: Bool
    ) -> PasswordSavePromptDetails {
        let accountLabel = username.isEmpty ? normalizedHost : username
        let isInsecurePage = pageURL.scheme?.localizedCaseInsensitiveCompare("http") == .orderedSame

        if isInsecurePage {
            let actionTitle = isUpdate ? "Update Password on Insecure Page" : "Save Password on Insecure Page"
            let buttonTitle = isUpdate ? "Update Anyway" : "Save Anyway"
            let actionVerb = isUpdate ? "update" : "save"
            return PasswordSavePromptDetails(
                title: actionTitle,
                message: "This page uses an insecure connection (http://), so other people on the network may be able to read the password. Do you still want to \(actionVerb) the password for \(accountLabel)?",
                confirmButtonTitle: buttonTitle,
                neverButtonTitle: "Never on This Site",
                showsSecurityWarning: true
            )
        }

        let title = isUpdate ? "Update Password" : "Save Password"
        let message = isUpdate
            ? "Update the saved password for \(accountLabel)?"
            : "Save the password for \(accountLabel)?"

        return PasswordSavePromptDetails(
            title: title,
            message: message,
            confirmButtonTitle: title,
            neverButtonTitle: "Never on This Site",
            showsSecurityWarning: false
        )
    }

    static func resolveSuggestions(
        for focus: PasswordBridgeFocusPayload,
        matchingEntries: [ProviderCredential],
        emailSuggestions: [PasswordEmailSuggestion],
        generatedPassword: String?,
        structuredItems: [ProviderStructuredItem] = []
    ) -> PasswordAutofillOverlayState {
        if focus.fieldKind == .creditCard {
            let cards = structuredItems.filter { $0.category == .creditCard }
            return PasswordAutofillOverlayState(
                focus: focus, savedPasswordEntries: [], emailSuggestions: [],
                generatedPassword: nil, structuredItems: cards, selectedSuggestionIndex: 0
            )
        }

        if focus.fieldKind == .identity {
            let ids = structuredItems.filter { $0.category == .identity }
            return PasswordAutofillOverlayState(
                focus: focus, savedPasswordEntries: [], emailSuggestions: [],
                generatedPassword: nil, structuredItems: ids, selectedSuggestionIndex: 0
            )
        }

        let savedPasswordEntries: [ProviderCredential]
        let filteredEmailSuggestions: [PasswordEmailSuggestion]
        let filteredGeneratedPassword: String?
        let oneTimeCodeCredential: ProviderCredential?

        switch (focus.action, focus.fieldKind) {
        case (.createAccount, .password):
            savedPasswordEntries = []
            filteredEmailSuggestions = []
            filteredGeneratedPassword = generatedPassword
            oneTimeCodeCredential = nil
        case (.createAccount, .email):
            savedPasswordEntries = []
            filteredEmailSuggestions = emailSuggestions
            filteredGeneratedPassword = nil
            oneTimeCodeCredential = nil
        case (.createAccount, .username):
            savedPasswordEntries = []
            filteredEmailSuggestions = []
            filteredGeneratedPassword = nil
            oneTimeCodeCredential = nil
        case (.createAccount, .oneTimeCode):
            savedPasswordEntries = []
            filteredEmailSuggestions = []
            filteredGeneratedPassword = nil
            oneTimeCodeCredential = nil
        case (.createAccount, .creditCard), (.createAccount, .identity):
            // Card/identity overlay routing lands in a later slice; no suggestions yet.
            savedPasswordEntries = []
            filteredEmailSuggestions = []
            filteredGeneratedPassword = nil
            oneTimeCodeCredential = nil
        case (.login, .oneTimeCode):
            // Only credentials with a saved TOTP secret are relevant to an OTP field.
            // Surface the first match as a single "Fill one-time code" suggestion rather than
            // an ordinary saved-credential row.
            savedPasswordEntries = []
            filteredEmailSuggestions = []
            filteredGeneratedPassword = nil
            oneTimeCodeCredential = matchingEntries.filter(\.hasTotp).first
        case (.login, _):
            savedPasswordEntries = matchingEntries
            filteredEmailSuggestions = []
            filteredGeneratedPassword = nil
            oneTimeCodeCredential = nil
        }

        return PasswordAutofillOverlayState(
            focus: focus,
            savedPasswordEntries: savedPasswordEntries,
            emailSuggestions: filteredEmailSuggestions,
            generatedPassword: filteredGeneratedPassword,
            oneTimeCodeCredential: oneTimeCodeCredential,
            selectedSuggestionIndex: (savedPasswordEntries.isEmpty && filteredEmailSuggestions
                .isEmpty && filteredGeneratedPassword == nil && oneTimeCodeCredential == nil) ? -1 : 0
        )
    }
}

// MARK: - Locked / syncing provider overlays / save routing

extension PasswordAutofillCoordinator {
    private static func makeOverlayState(
        for focus: PasswordBridgeFocusPayload,
        normalizedHost: String,
        suggestions: PasswordAutofillOverlayState,
        lockedProviderLabel: String? = nil,
        isSyncing: Bool = false
    ) -> PasswordAutofillOverlayState {
        PasswordAutofillOverlayState(
            focus: focus.withHostname(normalizedHost),
            savedPasswordEntries: suggestions.savedPasswordEntries,
            emailSuggestions: suggestions.emailSuggestions,
            generatedPassword: suggestions.generatedPassword,
            oneTimeCodeCredential: suggestions.oneTimeCodeCredential,
            structuredItems: suggestions.structuredItems,
            selectedSuggestionIndex: suggestions.selectedSuggestionIndex,
            lockedProviderLabel: lockedProviderLabel,
            isSyncing: isSyncing
        )
    }

    /// Shows a single non-interactive/interactive placeholder row (unlock prompt or syncing spinner)
    /// in place of the normal suggestion list, e.g. while the active provider is locked or syncing.
    @MainActor
    private func presentPlaceholderOverlay(
        for focus: PasswordBridgeFocusPayload,
        normalizedHost: String,
        lockedProviderLabel: String? = nil,
        isSyncing: Bool = false
    ) {
        let placeholder = PasswordAutofillOverlayState(
            focus: focus,
            savedPasswordEntries: [],
            emailSuggestions: [],
            generatedPassword: nil,
            selectedSuggestionIndex: lockedProviderLabel != nil ? 0 : -1
        )
        let overlayState = Self.makeOverlayState(
            for: focus,
            normalizedHost: normalizedHost,
            suggestions: placeholder,
            lockedProviderLabel: lockedProviderLabel,
            isSyncing: isSyncing
        )

        tab?.passwordTriggerOverlayState = overlayState
        tab?.passwordOverlayState = overlayState
        setOverlayKeyboardActive(true)
    }

    @MainActor
    func unlockActiveProvider() {
        let provider = providers.activeProvider(for: settings.passwordManagerProvider)
        Task { @MainActor in
            if provider is OnePasswordProvider {
                await OnePasswordService.shared.refresh() // triggers the app auth prompt
            }
            // Re-present the overlay for the current field once unlocked.
        }
        dismissOverlay()
    }
}

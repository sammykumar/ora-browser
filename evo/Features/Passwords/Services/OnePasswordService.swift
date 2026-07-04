//
//  OnePasswordService.swift
//  evo
//
//  App-wide, lazily-initialized owner of the 1Password sidecar process(es).
//  Holds an in-memory metadata cache (titles/usernames/hosts — NO secrets),
//  publishes provider state for UI, and does host-matching for autofill.
//
//  Kept lazy + injectable: `shared` must not spawn a process at init time
//  because evoTests launches the whole app, and an eager singleton would
//  spawn real sidecars during unrelated tests. Only `configureAccounts` /
//  `refresh` create processes, and only when using the real (non-injected)
//  transport factory.
//

import AppKit
import Combine
import Foundation

@MainActor
final class OnePasswordService: ObservableObject {
    static let shared = OnePasswordService()

    @Published private(set) var state: ProviderState = .unavailable(reason: "Not configured")
    @Published private(set) var metadata: [ProviderCredential] = []

    private var accounts: [String] = []
    private var processes: [String: OpHelperProcess] = [:]
    private let transportFactory: (String) -> OpHelperTransport
    private var configureTask: Task<Void, Never>?

    init(transportFactory: ((String) -> OpHelperTransport)? = nil) {
        self.transportFactory = transportFactory ?? OnePasswordService.makeProcessTransport
    }

    private static func makeProcessTransport(accountName: String) -> OpHelperTransport {
        let binaryURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/evo-op-helper")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let transport = ProcessOpHelperTransport(
            binaryURL: binaryURL, accountName: accountName, integrationVersion: version
        )
        try? transport.start()
        return transport
    }

    func configureAccounts(_ names: [String]) {
        let unique = names.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        accounts = unique
        // Unconditionally tear down and recreate every sidecar so a Reconnect
        // always yields live processes, even if a prior sidecar exited (e.g.
        // the Go watchdog's os.Exit(1) on timeout) and was left stale here.
        for process in processes.values {
            process.shutdownSync()
        }
        processes.removeAll()
        for name in unique {
            processes[name] = OpHelperProcess(transport: transportFactory(name))
        }
        state = unique.isEmpty ? .unavailable(reason: "No account configured") : .syncing
    }

    func refresh() async {
        guard !accounts.isEmpty else { return }
        state = .syncing
        var merged: [ProviderCredential] = []
        var anyLocked = false
        var lastErrorState: ProviderState?
        for account in accounts {
            guard let process = processes[account] else { continue }
            do {
                let result = try await process.request(method: "listItems", params: [:])
                let items = result["items"] as? [[String: Any]] ?? []
                merged.append(contentsOf: items.compactMap { Self.credential(from: $0, account: account) })
            } catch let OpHelperError.wire(code, _) where code == "locked" {
                anyLocked = true
            } catch let OpHelperError.wire(code, _) {
                lastErrorState = Self.disambiguate(errorCode: code, appRunning: onePasswordRunning())
            } catch {
                continue
            }
        }
        var seen = Set<String>()
        metadata = merged.filter { credential in
            let key = "\(credential.host)|\(credential.username)|\(credential.accountLabel ?? "")"
            return seen.insert(key).inserted
        }
        if anyLocked {
            state = .locked
        } else if !metadata.isEmpty {
            state = .ready
        } else if let lastErrorState {
            // Empty cache AND at least one account errored — don't report "Connected".
            state = lastErrorState
        } else {
            state = .ready
        }
    }

    /// Disambiguates the sidecar's ambiguous `channelClosed` wire error (which can mean
    /// either "1Password isn't running" or "the integration toggle is off") using whether
    /// the 1Password app process is currently running.
    nonisolated static func disambiguate(errorCode: String, appRunning: Bool) -> ProviderState {
        switch errorCode {
        case "appMissing":
            return .unavailable(reason: "1Password isn’t installed")
        case "channelClosed":
            return appRunning
                ? .unavailable(reason: "Enable Settings → Developer → Integrate with other apps in 1Password")
                : .unavailable(reason: "1Password isn’t running")
        case "locked":
            return .locked
        default:
            return .unavailable(reason: "1Password error")
        }
    }

    private func onePasswordRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.1password.1password").isEmpty
    }

    /// Lazily configures all accounts from settings and populates the cache. Concurrent callers
    /// await the same in-flight configuration. If the attempt doesn't reach a usable state
    /// (`.ready`/`.locked` — e.g. 1Password wasn't running yet), the guard is cleared so a later
    /// call (e.g. on next credential request) can retry.
    func ensureConfigured() async {
        if let configureTask {
            await configureTask.value
            return
        }
        let names = SettingsStore.shared.onePasswordAccounts
        guard !names.isEmpty else { return }
        let task = Task { @MainActor in
            configureAccounts(names)
            await refresh()
        }
        configureTask = task
        await task.value
        switch state {
        case .ready, .locked:
            break
        default:
            configureTask = nil // allow a retry on the next credential request
        }
    }

    func credentials(for url: URL) -> [ProviderCredential] {
        guard let rawHost = url.host else { return [] }
        let host = PasswordManagerService.normalizeHost(rawHost)
        return metadata.filter { credential in
            PasswordManagerService.normalizeHost(credential.host) == host
        }
    }

    func reveal(_ credential: ProviderCredential) async throws -> RevealedCredential {
        guard case let .onePassword(accountName, vaultID, itemID) = credential.ref,
              let process = processes[accountName]
        else {
            throw OpHelperError.notRunning
        }
        let result = try await process.request(method: "reveal", params: ["vaultId": vaultID, "itemId": itemID])
        return RevealedCredential(
            username: result["username"] as? String ?? "",
            password: result["password"] as? String ?? ""
        )
    }

    func save(url: URL, username: String, password: String, target: SaveTarget) async throws {
        guard case let .onePassword(accountName, vaultID, existingItemID) = target,
              let process = processes[accountName]
        else {
            throw OpHelperError.notRunning
        }
        var params: [String: Any] = [
            "vaultId": vaultID,
            "title": url.host ?? url.absoluteString,
            "url": url.absoluteString,
            "username": username,
            "password": password
        ]
        if let existingItemID { params["itemId"] = existingItemID }
        _ = try await process.request(method: "saveItem", params: params)
        await refresh()
    }

    func listVaults(accountName: String) async throws -> [(id: String, title: String)] {
        guard let process = processes[accountName] else { throw OpHelperError.notRunning }
        let result = try await process.request(method: "listVaults", params: [:])
        let vaults = result["vaults"] as? [[String: Any]] ?? []
        return vaults.compactMap { dict in
            guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
            return (id: id, title: title)
        }
    }

    func totp(for credential: ProviderCredential) async throws -> String? {
        guard case let .onePassword(accountName, vaultID, itemID) = credential.ref,
              let process = processes[accountName]
        else {
            throw OpHelperError.notRunning
        }
        let result = try await process.request(method: "totp", params: ["vaultId": vaultID, "itemId": itemID])
        return result["code"] as? String
    }

    func shutdownAll() {
        for process in processes.values {
            process.shutdownSync()
        }
        processes.removeAll()
    }

    static func credential(from dict: [String: Any], account: String) -> ProviderCredential? {
        guard let itemID = dict["id"] as? String, let vaultID = dict["vaultId"] as? String else { return nil }
        let urls = dict["urls"] as? [String] ?? []
        let host = urls.first.flatMap { URL(string: $0)?.host }.map(PasswordManagerService.normalizeHost) ?? ""
        return ProviderCredential(
            id: "\(account):\(itemID)",
            ref: .onePassword(accountName: account, vaultID: vaultID, itemID: itemID),
            title: dict["title"] as? String ?? host,
            username: dict["username"] as? String ?? "",
            host: host,
            accountLabel: account,
            hasTotp: dict["hasTotp"] as? Bool ?? false
        )
    }
}

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
        // Tear down processes for removed accounts.
        for name in processes.keys where !unique.contains(name) {
            processes[name]?.shutdownSync()
            processes[name] = nil
        }
        // Lazily create processes for new accounts.
        for name in unique where processes[name] == nil {
            processes[name] = OpHelperProcess(transport: transportFactory(name))
        }
        state = unique.isEmpty ? .unavailable(reason: "No account configured") : .syncing
    }

    func refresh() async {
        guard !accounts.isEmpty else { return }
        state = .syncing
        var merged: [ProviderCredential] = []
        var anyLocked = false
        for account in accounts {
            guard let process = processes[account] else { continue }
            do {
                let result = try await process.request(method: "listItems", params: [:])
                let items = result["items"] as? [[String: Any]] ?? []
                merged.append(contentsOf: items.compactMap { Self.credential(from: $0, account: account) })
            } catch let OpHelperError.wire(code, _) where code == "locked" || code == "channelClosed" {
                anyLocked = true
            } catch {
                continue
            }
        }
        metadata = merged
        state = anyLocked ? .locked : .ready
    }

    /// Lazily configures accounts from settings and populates the cache, exactly once per
    /// service lifetime. Concurrent callers await the same in-flight configuration.
    func ensureConfigured() async {
        if let configureTask {
            await configureTask.value
            return
        }
        let account = SettingsStore.shared.onePasswordAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { return }
        let task = Task { @MainActor in
            configureAccounts([account])
            await refresh()
        }
        configureTask = task
        await task.value
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

    /// Stub — real save flow lands in a later slice.
    func save(url: URL, username: String, password: String, target: SaveTarget) async throws {
        throw OpHelperError.notRunning
    }

    /// Stub — real TOTP retrieval lands in a later slice.
    func totp(for credential: ProviderCredential) async throws -> String? {
        nil
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

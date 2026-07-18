#if DEBUG
    import AppKit
    import Foundation
    import os
    import SwiftData

    enum DebugHarnessRouter {
        enum HarnessError: Error {
            case timeout
        }

        /// Structured concurrency (`withThrowingTaskGroup`) cannot return until every child task
        /// completes, even after `cancelAll()` — cancellation is only a cooperative flag. An
        /// operation suspended inside `withCheckedContinuation` awaiting a non-cancellation-aware
        /// callback (e.g. WKWebView's `evaluateJavaScript`) never observes that flag, so a task
        /// group racing it against a timeout does not bound wall-clock time. Use a single
        /// continuation instead: whichever of {operation, timer} finishes first resumes it, guarded
        /// by a lock so only the first winner's result is delivered. If the operation hangs, its
        /// `Task` keeps running in the background and its eventual result/error is silently dropped
        /// via the `resumed` guard once the timeout has already resumed the continuation — this is
        /// intended, documented behavior, not a leak of the timeout guarantee.
        static func harnessTimeout<T: Sendable>(
            seconds: Double,
            _ operation: @escaping @Sendable () async throws -> T
        ) async throws -> T {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                Task {
                    do {
                        let value = try await operation()
                        let first = resumed.withLock { alreadyResumed -> Bool in
                            if alreadyResumed {
                                return false
                            }
                            alreadyResumed = true
                            return true
                        }
                        if first {
                            continuation.resume(returning: value)
                        }
                    } catch {
                        let first = resumed.withLock { alreadyResumed -> Bool in
                            if alreadyResumed {
                                return false
                            }
                            alreadyResumed = true
                            return true
                        }
                        if first {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    let first = resumed.withLock { alreadyResumed -> Bool in
                        if alreadyResumed {
                            return false
                        }
                        alreadyResumed = true
                        return true
                    }
                    if first {
                        continuation.resume(throwing: HarnessError.timeout)
                    }
                }
            }
        }

        /// WebKit hands back NSString/NSNumber/NSArray/NSDictionary/NSNull. Anything else is stringified.
        static func jsonSafe(_ value: Any?) -> Any {
            guard let value else { return NSNull() }
            if JSONSerialization.isValidJSONObject(["v": value]) {
                return value
            }
            return String(describing: value)
        }

        static func writePNG(image: NSImage, to path: String) -> HarnessHTTPResponse {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                return HarnessHTTPResponse.error("png encode failed", status: 500)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
                return HarnessHTTPResponse.json([
                    "path": path,
                    "width": Int(rep.pixelsWide),
                    "height": Int(rep.pixelsHigh)
                ])
            } catch {
                return HarnessHTTPResponse.error("write failed: \(error.localizedDescription)", status: 500)
            }
        }

        /// `TabManager.containers` is a `@Query` declared on a plain `ObservableObject`, not a `View`,
        /// so SwiftUI never binds it to a live `ModelContext` and it always reads as empty outside the
        /// normal view-update cycle. Fetch containers directly from the manager's `modelContext` instead
        /// (mirrors `TabManager.fetchContainers()`, which is `private`).
        @MainActor
        private static func liveContainers(for tabManager: TabManager) -> [TabContainer] {
            let descriptor = FetchDescriptor<TabContainer>(sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)])
            return (try? tabManager.modelContext.fetch(descriptor)) ?? []
        }

        @MainActor
        static func route(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return handleHealth()

            case ("GET", "/windows"):
                return handleWindows()

            case ("GET", "/tabs"):
                return handleTabs(request)

            case ("POST", "/navigate"):
                return handleNavigate(request)

            case ("POST", "/eval"):
                return await handleEval(request)

            case ("POST", "/screenshot"):
                return await handleScreenshot(request)

            case ("GET", "/overlay"):
                return handleOverlay(request)

            case ("POST", "/keypress"):
                return handleKeypress(request)

            case ("GET", "/provider"):
                return handleGetProvider()

            case ("POST", "/provider"):
                return handleSetProvider(request)

            default:
                return HarnessHTTPResponse.error("no route for \(request.method) \(request.path)", status: 404)
            }
        }

        private static func handleHealth() -> HarnessHTTPResponse {
            HarnessHTTPResponse.json([
                "ok": true,
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "pid": Int(ProcessInfo.processInfo.processIdentifier)
            ])
        }

        @MainActor
        private static func handleWindows() -> HarnessHTTPResponse {
            let windows = DebugHarnessRegistry.shared.snapshots().map { snapshot -> [String: Any] in
                let tabCount = liveContainers(for: snapshot.tabManager).reduce(0) { $0 + $1.tabs.count }
                return [
                    "windowID": snapshot.id.uuidString,
                    "isPrivate": snapshot.isPrivate,
                    "tabCount": tabCount
                ]
            }
            return HarnessHTTPResponse.json(windows)
        }

        @MainActor
        private static func handleTabs(_ request: HarnessHTTPRequest) -> HarnessHTTPResponse {
            var snapshots = DebugHarnessRegistry.shared.snapshots()
            if let windowRaw = request.query["window"] {
                guard let windowID = UUID(uuidString: windowRaw) else {
                    return HarnessHTTPResponse.error("bad window id", status: 400)
                }
                snapshots = snapshots.filter { $0.id == windowID }
            }
            var tabs: [[String: Any]] = []
            for snapshot in snapshots {
                for container in liveContainers(for: snapshot.tabManager) {
                    for tab in container.tabs {
                        tabs.append([
                            "tabID": tab.id.uuidString,
                            "windowID": snapshot.id.uuidString,
                            "url": tab.url.absoluteString,
                            "title": tab.title,
                            "isActive": tab.id == snapshot.tabManager.activeTab?.id
                        ])
                    }
                }
            }
            return HarnessHTTPResponse.json(tabs)
        }

        @MainActor
        private static func handleNavigate(_ request: HarnessHTTPRequest) -> HarnessHTTPResponse {
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let urlString = payload["url"] as? String,
                  let url = URL(string: urlString)
            else {
                return HarnessHTTPResponse.error("body must be {\"url\": \"...\"}", status: 400)
            }
            if let tabRaw = payload["tabID"] as? String {
                guard let tabID = UUID(uuidString: tabRaw),
                      let found = DebugHarnessRegistry.shared.findTab(tabID)
                else {
                    return HarnessHTTPResponse.error("unknown tab", status: 404)
                }
                let escaped = url.absoluteString
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                found.tab.browserPage?.evaluateJavaScript("location.assign('\(escaped)')")
                return HarnessHTTPResponse.json(["tabID": found.tab.id.uuidString])
            }
            guard let snapshot = DebugHarnessRegistry.shared.snapshots().first else {
                return HarnessHTTPResponse.error("no windows registered", status: 404)
            }
            let newTab = snapshot.tabManager.openTab(
                url: url,
                historyManager: snapshot.historyManager,
                focusAfterOpening: true,
                isPrivate: snapshot.isPrivate
            )
            guard let newTab else {
                return HarnessHTTPResponse.error("openTab returned nil (no active container?)", status: 500)
            }
            return HarnessHTTPResponse.json(["tabID": newTab.id.uuidString])
        }

        @MainActor
        private static func handleEval(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let tabRaw = payload["tabID"] as? String,
                  let tabID = UUID(uuidString: tabRaw),
                  let script = payload["js"] as? String
            else {
                return HarnessHTTPResponse.error("body must be {\"tabID\", \"js\"}", status: 400)
            }
            guard let found = DebugHarnessRegistry.shared.findTab(tabID),
                  let page = found.tab.browserPage
            else {
                return HarnessHTTPResponse.error("unknown tab or no page", status: 404)
            }
            do {
                let outcome: Swift.Result<Any?, Error> = try await Self.harnessTimeout(seconds: 5) {
                    await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            page.evaluateJavaScript(script) { value, error in
                                if let error {
                                    continuation.resume(returning: Swift.Result.failure(error))
                                } else {
                                    continuation.resume(returning: Swift.Result.success(value))
                                }
                            }
                        }
                    }
                }
                switch outcome {
                case let .success(value):
                    return HarnessHTTPResponse.json(["result": Self.jsonSafe(value)])
                case let .failure(error):
                    return HarnessHTTPResponse.json([
                        "error": error.localizedDescription,
                        "jsException": true
                    ])
                }
            } catch {
                return HarnessHTTPResponse.error("eval timed out", status: 504)
            }
        }

        @MainActor
        private static func handleScreenshot(_ request: HarnessHTTPRequest) async -> HarnessHTTPResponse {
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let scope = payload["scope"] as? String,
                  let path = payload["path"] as? String,
                  path.hasPrefix("/")
            else {
                return HarnessHTTPResponse.error(
                    "body must be {\"scope\": \"page\"|\"window\", \"path\": \"/abs.png\"}",
                    status: 400
                )
            }
            switch scope {
            case "page":
                return await handlePageScreenshot(payload: payload, path: path)
            case "window":
                return handleWindowScreenshot(path: path)
            default:
                return HarnessHTTPResponse.error("scope must be page or window", status: 400)
            }
        }

        @MainActor
        private static func handlePageScreenshot(payload: [String: Any], path: String) async -> HarnessHTTPResponse {
            guard let tabRaw = payload["tabID"] as? String,
                  let tabID = UUID(uuidString: tabRaw),
                  let found = DebugHarnessRegistry.shared.findTab(tabID),
                  let page = found.tab.browserPage
            else {
                return HarnessHTTPResponse.error("page scope needs a valid tabID", status: 404)
            }
            let image: NSImage? = await withCheckedContinuation { continuation in
                page.takeSnapshot(
                    configuration: BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: true)
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }
            guard let image else {
                return HarnessHTTPResponse.error("snapshot failed", status: 500)
            }
            return Self.writePNG(image: image, to: path)
        }

        @MainActor
        private static func handleWindowScreenshot(path: String) -> HarnessHTTPResponse {
            guard let window = NSApp.windows
                .first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }),
                let view = window.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else {
                return HarnessHTTPResponse.error("no visible window", status: 404)
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                return HarnessHTTPResponse.error("png encode failed", status: 500)
            }
            do {
                try png.write(to: URL(fileURLWithPath: path))
            } catch {
                return HarnessHTTPResponse.error("write failed: \(error.localizedDescription)", status: 500)
            }
            return HarnessHTTPResponse.json([
                "path": path,
                "width": Int(rep.pixelsWide),
                "height": Int(rep.pixelsHigh)
            ])
        }

        @MainActor
        private static func handleOverlay(_ request: HarnessHTTPRequest) -> HarnessHTTPResponse {
            guard let tabRaw = request.query["tab"], let tabID = UUID(uuidString: tabRaw) else {
                return HarnessHTTPResponse.error("query must include ?tab=<uuid>", status: 400)
            }
            guard let found = DebugHarnessRegistry.shared.findTab(tabID) else {
                return HarnessHTTPResponse.error("unknown tab", status: 404)
            }
            guard let overlay = found.tab.passwordOverlayState else {
                return HarnessHTTPResponse.json(["visible": false, "rows": [[String: Any]]()])
            }
            let rows: [[String: Any]] = overlay.suggestions.map { suggestion in
                let (label, detail): (String, String)
                switch suggestion {
                case let .generatedPassword(host, _):
                    (label, detail) = ("Generated password", host)
                case let .savedCredential(credential):
                    (label, detail) = (credential.title, credential.displayUsername)
                case let .email(emailSuggestion):
                    (label, detail) = (emailSuggestion.email, "email")
                case let .unlockProvider(providerLabel):
                    (label, detail) = ("Unlock \(providerLabel)", "locked")
                case let .fillOneTimeCode(credential):
                    (label, detail) = ("One-time code", credential.displayUsername)
                case let .fillCard(item):
                    (label, detail) = (item.title, item.subtitle)
                case let .fillIdentity(item):
                    (label, detail) = (item.title, item.subtitle)
                }
                return ["id": suggestion.id, "label": label, "detail": detail]
            }
            return HarnessHTTPResponse.json([
                "visible": true,
                "fieldID": overlay.focus.fieldID,
                "fieldKind": overlay.focus.fieldKind.rawValue,
                "hostname": overlay.focus.hostname,
                "selectionIndex": overlay.selectedSuggestionIndex,
                "rows": rows
            ])
        }

        @MainActor
        private static func handleKeypress(_ request: HarnessHTTPRequest) -> HarnessHTTPResponse {
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let tabRaw = payload["tabID"] as? String,
                  let tabID = UUID(uuidString: tabRaw),
                  let commandRaw = payload["command"] as? String,
                  let command = PasswordAutofillKeyCommand(rawValue: commandRaw)
            else {
                return HarnessHTTPResponse.error(
                    "body must be {\"tabID\", \"command\": moveUp|moveDown|activate|dismiss}",
                    status: 400
                )
            }
            guard let found = DebugHarnessRegistry.shared.findTab(tabID),
                  let coordinator = found.tab.passwordCoordinator
            else {
                return HarnessHTTPResponse.error("unknown tab or no coordinator", status: 404)
            }
            coordinator.handleKeyCommand(command)
            return HarnessHTTPResponse.json(["ok": true])
        }

        @MainActor
        private static func handleGetProvider() -> HarnessHTTPResponse {
            let kind = SettingsStore.shared.passwordManagerProvider
            let provider = PasswordManagerProviderRegistry.shared.activeProvider(for: kind)
            // Diagnostic: distinct credential hosts in the 1Password metadata cache
            // (titles/hosts only — the cache holds no secrets by design).
            var payload: [String: Any] = [
                "kind": kind.rawValue,
                "state": String(describing: provider.state)
            ]
            if kind == .onePassword {
                let hosts = OnePasswordService.shared.metadata.map(\.host)
                payload["credentialCount"] = hosts.count
                payload["hosts"] = Array(Set(hosts)).sorted()
            }
            return HarnessHTTPResponse.json(payload)
        }

        @MainActor
        private static func handleSetProvider(_ request: HarnessHTTPRequest) -> HarnessHTTPResponse {
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let kindRaw = payload["kind"] as? String,
                  let kind = PasswordManagerProviderKind(rawValue: kindRaw)
            else {
                return HarnessHTTPResponse.error("body must be {\"kind\": evo|onePassword|mock}", status: 400)
            }
            SettingsStore.shared.passwordManagerProvider = kind
            return HarnessHTTPResponse.json(["ok": true])
        }
    }
#endif
